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
    private var activeLocaleIdentifier: String?
    private let recorder = AudioRecorder()
    private var segmentIdCounter: Int = 0
    private static let minAudioDurationSeconds: Float = 0.30
    private static let recognitionTimeoutSeconds: TimeInterval = 12.0

    // MARK: - ASREngine

    func setupModel(_ model: ModelInfo) async throws {
        try await loadModel(model)
    }

    func loadModel(_ model: ModelInfo) async throws {
        _ = model
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

        let recognizer = try makeOnDeviceRecognizer(languageHint: nil)
        speechRecognizer = recognizer
        activeLocaleIdentifier = recognizer.locale.identifier
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
        activeLocaleIdentifier = nil
        modelState = .unloaded
    }

    func startRecording(captureMode: AudioCaptureMode) async throws {
        try await recorder.startRecording(captureMode: captureMode)
    }

    func stopRecording() {
        recorder.stopRecording()
    }

    func transcribe(audioArray: [Float], options: ASRTranscriptionOptions) async throws -> ASRResult {
        guard !audioArray.isEmpty else {
            return ASRResult(text: "", segments: [], language: options.language)
        }

        let audioDuration = Float(audioArray.count) / 16000.0
        if audioDuration < Self.minAudioDurationSeconds {
            return ASRResult(text: "", segments: [], language: options.language)
        }

        let recognizer = try recognizerForRequest(languageHint: options.language)
        guard recognizer.supportsOnDeviceRecognition else {
            throw AppError.modelNotReady
        }

        NSLog("[AppleSpeechEngine] TRANSCRIBE samples=%d duration=%.2fs",
              audioArray.count, audioDuration)
        if !recognizer.isAvailable {
            // isAvailable can be transient even when on-device recognition works.
            NSLog("[AppleSpeechEngine] recognizer reported unavailable; continuing with on-device request")
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.taskHint = .dictation

        // Convert Float32 samples to AVAudioPCMBuffer (16kHz mono).
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
        let result = try await recognizeFinalResult(recognizer: recognizer, request: request)

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

        // Apple Speech doesn't provide language detection — use the active recognizer locale.
        let detectedLang = Self.languageCode(from: recognizer.locale.identifier)

        return ASRResult(
            text: text,
            segments: segments,
            language: detectedLang
        )
    }

    // MARK: - Private

    private func recognizerForRequest(languageHint: String?) throws -> SFSpeechRecognizer {
        let normalizedHint = Self.normalizedLocaleIdentifier(languageHint)
        if let recognizer = speechRecognizer {
            let hint: String? = normalizedHint.isEmpty ? nil : normalizedHint
            if hint == nil || Self.localeMatches(identifier: recognizer.locale.identifier, hint: hint) {
                return recognizer
            }
        }

        let recognizer = try makeOnDeviceRecognizer(languageHint: languageHint)
        speechRecognizer = recognizer
        activeLocaleIdentifier = recognizer.locale.identifier
        NSLog("[AppleSpeechEngine] Switched recognizer locale=%@", recognizer.locale.identifier)
        return recognizer
    }

    private func makeOnDeviceRecognizer(languageHint: String?) throws -> SFSpeechRecognizer {
        let candidates = Self.localeCandidates(languageHint: languageHint)
        let supported = SFSpeechRecognizer.supportedLocales().sorted { $0.identifier < $1.identifier }

        for candidate in candidates {
            if let locale = Self.bestLocaleMatch(for: candidate, supported: supported),
               let recognizer = SFSpeechRecognizer(locale: locale),
               recognizer.supportsOnDeviceRecognition {
                return recognizer
            }
        }

        if let fallback = supported.first(where: {
            guard let recognizer = SFSpeechRecognizer(locale: $0) else { return false }
            return recognizer.supportsOnDeviceRecognition
        }), let recognizer = SFSpeechRecognizer(locale: fallback) {
            return recognizer
        }

        throw AppError.modelLoadFailed(underlying: NSError(
            domain: "AppleSpeechEngine", code: -3,
            userInfo: [NSLocalizedDescriptionKey: "No on-device speech recognition locale is available on this device."]
        ))
    }

    private func recognizeFinalResult(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest
    ) async throws -> SFSpeechRecognitionResult {
        try await withCheckedThrowingContinuation { continuation in
            let timeoutError = NSError(
                domain: "AppleSpeechEngine",
                code: -5,
                userInfo: [NSLocalizedDescriptionKey: "Apple Speech recognition timed out waiting for a final result."]
            )

            let stateQueue = DispatchQueue(label: "AppleSpeechEngine.RecognitionState")
            var hasResumed = false
            var recognitionTask: SFSpeechRecognitionTask?
            var timeoutWorkItem: DispatchWorkItem?

            let resumeOnce: (Result<SFSpeechRecognitionResult, Error>) -> Void = { outcome in
                stateQueue.sync {
                    guard !hasResumed else { return }
                    hasResumed = true
                    timeoutWorkItem?.cancel()
                    switch outcome {
                    case .success(let result):
                        continuation.resume(returning: result)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }

            let timeout = DispatchWorkItem {
                recognitionTask?.cancel()
                resumeOnce(.failure(timeoutError))
            }
            timeoutWorkItem = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.recognitionTimeoutSeconds, execute: timeout)

            recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    resumeOnce(.failure(error))
                    return
                }
                guard let result else { return }
                if result.isFinal {
                    resumeOnce(.success(result))
                }
            }
        }
    }

    private static func localeCandidates(languageHint: String?) -> [String] {
        var values: [String] = []
        let normalizedHint = normalizedLocaleIdentifier(languageHint)
        if !normalizedHint.isEmpty {
            values.append(normalizedHint)
            values.append(languageCode(from: normalizedHint))
        }
        values.append(normalizedLocaleIdentifier(Locale.autoupdatingCurrent.identifier))
        values.append(contentsOf: Locale.preferredLanguages.map(normalizedLocaleIdentifier))
        values.append("en-US")

        var deduped: [String] = []
        var seen: Set<String> = []
        for value in values where !value.isEmpty {
            let key = value.lowercased()
            if seen.insert(key).inserted {
                deduped.append(value)
            }
        }
        return deduped
    }

    private static func bestLocaleMatch(for candidate: String, supported: [Locale]) -> Locale? {
        let normalizedCandidate = normalizedLocaleIdentifier(candidate)
        if let exact = supported.first(where: {
            normalizedLocaleIdentifier($0.identifier).lowercased() == normalizedCandidate.lowercased()
        }) {
            return exact
        }

        let candidateLang = languageCode(from: normalizedCandidate)
        return supported.first(where: { languageCode(from: $0.identifier) == candidateLang })
    }

    private static func localeMatches(identifier: String, hint: String?) -> Bool {
        guard let hint else { return true }
        let current = normalizedLocaleIdentifier(identifier)
        let normalizedHint = normalizedLocaleIdentifier(hint)
        if current.lowercased() == normalizedHint.lowercased() {
            return true
        }
        return languageCode(from: current) == languageCode(from: normalizedHint)
    }

    private static func normalizedLocaleIdentifier(_ raw: String?) -> String {
        guard let raw else { return "" }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
    }

    private static func languageCode(from localeIdentifier: String) -> String {
        let normalized = normalizedLocaleIdentifier(localeIdentifier)
        if let first = normalized.split(separator: "-", maxSplits: 1).first {
            return first.lowercased()
        }
        return normalized.lowercased()
    }
}
