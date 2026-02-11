import Foundation

/// Reads audio from the shared ring buffer (written by the Broadcast Upload Extension)
/// and provides the same interface as AudioRecorder for use with ASR engines.
@MainActor
final class SystemAudioSource {
    private(set) var audioSamples: [Float] = []
    private(set) var relativeEnergy: [Float] = []
    private(set) var isActive = false

    /// Called on the main actor whenever new audio arrives from the broadcast.
    var onNewAudio: (([Float]) -> Void)?

    private var ringBuffer: SharedAudioRingBuffer?
    private var pollTimer: Timer?
    private var darwinObserverToken: NSObjectProtocol?

    /// Cap audioSamples to prevent unbounded memory growth.
    private static let maxAudioSamples = 28_800_000 // ~30 min at 16kHz
    private static let maxEnergyFrames = 60_000

    func start() {
        guard !isActive else { return }

        ringBuffer = SharedAudioRingBuffer(isProducer: false)
        guard ringBuffer != nil else {
            NSLog("[SystemAudioSource] Failed to open shared ring buffer")
            return
        }

        audioSamples = []
        relativeEnergy = []
        isActive = true

        // Register for Darwin notification when audio is ready
        registerDarwinNotification()

        // Also poll periodically as a fallback (Darwin notifications can be coalesced)
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.readFromBuffer()
            }
        }
    }

    func stop() {
        guard isActive else { return }
        isActive = false

        pollTimer?.invalidate()
        pollTimer = nil
        unregisterDarwinNotification()
        onNewAudio = nil
        ringBuffer = nil
    }

    // MARK: - Read from ring buffer

    private func readFromBuffer() {
        guard let ringBuffer, isActive else { return }

        let samples = ringBuffer.readAvailable()
        guard !samples.isEmpty else { return }

        // Compute energy
        let sumSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        let rms = sqrt(sumSquares / Float(samples.count))
        let dbFS = 20 * log10(max(rms, 1e-10))
        let normalizedEnergy = max(0, min(1, (dbFS + 60) / 60))

        audioSamples.append(contentsOf: samples)
        if audioSamples.count > Self.maxAudioSamples {
            audioSamples = Array(audioSamples.suffix(Self.maxAudioSamples / 2))
        }

        relativeEnergy.append(normalizedEnergy)
        if relativeEnergy.count > Self.maxEnergyFrames {
            relativeEnergy = Array(relativeEnergy.suffix(Self.maxEnergyFrames / 2))
        }

        onNewAudio?(samples)
    }

    // MARK: - Darwin Notifications

    private func registerDarwinNotification() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()

        // Audio ready notification — triggers buffer read
        let audioReadyName = "com.voiceping.translate.audioReady" as CFString
        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let source = Unmanaged<SystemAudioSource>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in
                    source.readFromBuffer()
                }
            },
            audioReadyName,
            nil,
            .deliverImmediately
        )

        // Broadcast stopped notification
        let stoppedName = "com.voiceping.translate.broadcastStopped" as CFString
        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let source = Unmanaged<SystemAudioSource>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in
                    source.isActive = false
                    NSLog("[SystemAudioSource] Broadcast stopped notification received")
                }
            },
            stoppedName,
            nil,
            .deliverImmediately
        )
    }

    private func unregisterDarwinNotification() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterRemoveEveryObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    func clearBuffers() {
        audioSamples = []
        relativeEnergy = []
    }
}
