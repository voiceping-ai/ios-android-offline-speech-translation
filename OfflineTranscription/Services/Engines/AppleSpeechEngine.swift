import Foundation
import Speech
import AVFoundation

/// ASREngine implementation using Apple's built-in Speech framework (SFSpeechRecognizer).
/// Uses on-device recognition only — no network requests, no model downloads.
@MainActor
final class AppleSpeechEngine: ASREngine {
    var isStreaming: Bool { false }
    private(set) var modelState: ASRModelState = .unloaded
    private(set) var downloadProgress: Double = 0.0
    private(set) var loadingStatusMessage: String = ""
    var audioSamples: [Float] { recorder.audioSamples }
    var relativeEnergy: [Float] { recorder.relativeEnergy }

    private var speechRecognizer: SFSpeechRecognizer?
    private let recorder = AudioRecorder()
    private var segmentIdCounter: Int = 0

    // MARK: - ASREngine

    func setupModel(_ model: ModelInfo) async throws {
        try await loadModel(model)
    }

    func loadModel(_ model: ModelInfo) async throws {
        modelState = .loading
        loadingStatusMessage = "Requesting speech authorization..."

        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard status == .authorized else {
            modelState = .error
            loadingStatusMessage = ""
            let message: String
            switch status {
            case .denied:
                message = "Speech recognition permission denied. Enable it in Settings > Privacy > Speech Recognition."
            case .restricted:
                message = "Speech recognition is restricted on this device."
            case .notDetermined:
                message = "Speech recognition authorization not determined."
            default:
                message = "Speech recognition unavailable (status: \(status.rawValue))."
            }
            throw AppError.modelLoadFailed(underlying: NSError(
                domain: "AppleSpeechEngine", code: -1,
                userInfo: [NSLocalizedDescriptionKey: message]
            ))
        }

        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else {
            modelState = .error
            loadingStatusMessage = ""
            throw AppError.modelLoadFailed(underlying: NSError(
                domain: "AppleSpeechEngine", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "SFSpeechRecognizer is not available on this device."]
            ))
        }

        guard recognizer.supportsOnDeviceRecognition else {
            modelState = .error
            loadingStatusMessage = ""
            throw AppError.modelLoadFailed(underlying: NSError(
                domain: "AppleSpeechEngine", code: -3,
                userInfo: [NSLocalizedDescriptionKey: "On-device speech recognition is not supported for this locale."]
            ))
        }

        self.speechRecognizer = recognizer
        modelState = .loaded
        loadingStatusMessage = ""
        NSLog("[AppleSpeechEngine] Loaded SFSpeechRecognizer locale=%@ onDevice=%@",
              recognizer.locale.identifier,
              recognizer.supportsOnDeviceRecognition ? "YES" : "NO")
    }

    func isModelDownloaded(_ model: ModelInfo) -> Bool {
        // Apple Speech is built into iOS — always "downloaded"
        return true
    }

    func unloadModel() async {
        speechRecognizer = nil
        modelState = .unloaded
    }

    func startRecording() async throws {
        try await recorder.startRecording()
    }

    func stopRecording() {
        recorder.stopRecording()
    }

    func transcribe(audioArray: [Float], options: ASRTranscriptionOptions) async throws -> ASRResult {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw AppError.modelNotReady
        }

        let audioDuration = Float(audioArray.count) / 16000.0
        NSLog("[AppleSpeechEngine] TRANSCRIBE samples=%d duration=%.2fs",
              audioArray.count, audioDuration)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        // Set language from options if provided
        if let lang = options.language {
            request.contextualStrings = [] // Could add domain-specific hints here
            // SFSpeechRecognizer uses locale set at init, but we set task hint
            if lang == "en" || lang.hasPrefix("en-") {
                request.taskHint = .dictation
            }
        }

        // Convert Float32 samples to AVAudioPCMBuffer (16kHz mono)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audioArray.count)) else {
            throw AppError.transcriptionFailed(underlying: NSError(
                domain: "AppleSpeechEngine", code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create PCM buffer"]
            ))
        }
        pcmBuffer.frameLength = AVAudioFrameCount(audioArray.count)
        let channelData = pcmBuffer.floatChannelData![0]
        audioArray.withUnsafeBufferPointer { ptr in
            channelData.update(from: ptr.baseAddress!, count: audioArray.count)
        }

        request.append(pcmBuffer)
        request.endAudio()

        let startTime = CFAbsoluteTimeGetCurrent()

        // Use async/await with the recognition task
        let result: SFSpeechRecognitionResult = try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !hasResumed else { return }
                if let error {
                    hasResumed = true
                    continuation.resume(throwing: error)
                    return
                }
                guard let result else { return }
                if result.isFinal {
                    hasResumed = true
                    continuation.resume(returning: result)
                }
            }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        let text = result.bestTranscription.formattedString
            .trimmingCharacters(in: .whitespacesAndNewlines)
        NSLog("[AppleSpeechEngine] Transcription took %.3fs text=\"%@\"",
              elapsed, String(text.prefix(200)))

        guard !text.isEmpty else {
            return ASRResult(text: "", segments: [], language: options.language)
        }

        // Build segments from SFTranscriptionSegment
        var segments: [ASRSegment] = []
        let sfSegments = result.bestTranscription.segments
        if sfSegments.isEmpty {
            let segId = segmentIdCounter
            segmentIdCounter += 1
            segments.append(ASRSegment(
                id: segId,
                text: " " + text,
                start: 0,
                end: audioDuration
            ))
        } else {
            for sfSeg in sfSegments {
                let segId = segmentIdCounter
                segmentIdCounter += 1
                segments.append(ASRSegment(
                    id: segId,
                    text: " " + sfSeg.substring,
                    start: Float(sfSeg.timestamp),
                    end: Float(sfSeg.timestamp + sfSeg.duration)
                ))
            }
        }

        // Apple Speech doesn't provide language detection — use the recognizer's locale
        let detectedLang = String(recognizer.locale.identifier.prefix(2))

        return ASRResult(
            text: text,
            segments: segments,
            language: detectedLang
        )
    }
}
