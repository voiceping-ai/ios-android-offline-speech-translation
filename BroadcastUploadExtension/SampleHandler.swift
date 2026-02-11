import ReplayKit
import CoreMedia

/// Broadcast Upload Extension handler — receives system audio from ReplayKit
/// and writes PCM Float32 to a shared ring buffer for the main app to read.
class SampleHandler: RPBroadcastSampleHandler {
    private var ringBuffer: SharedAudioRingBuffer?

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        ringBuffer = SharedAudioRingBuffer(isProducer: true)
        ringBuffer?.setActive(true)

        // Notify main app that broadcast started
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName("com.voiceping.translate.broadcastStarted" as CFString),
            nil, nil, true
        )
    }

    override func broadcastPaused() {
        ringBuffer?.setActive(false)
    }

    override func broadcastResumed() {
        ringBuffer?.setActive(true)
    }

    override func broadcastFinished() {
        ringBuffer?.setActive(false)
        ringBuffer = nil

        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName("com.voiceping.translate.broadcastStopped" as CFString),
            nil, nil, true
        )
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case .audioApp:
            // App audio — this is what we want to transcribe
            guard let ringBuffer else { return }
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

            let format = CMSampleBufferGetFormatDescription(sampleBuffer)
            guard let asbd = format.map({ CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }) else { return }
            guard let asbd else { return }

            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
            guard status == kCMBlockBufferNoErr, let dataPointer else { return }

            let sampleRate = asbd.mSampleRate
            let channelCount = Int(asbd.mChannelsPerFrame)
            let bytesPerSample = Int(asbd.mBitsPerChannel / 8)
            let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
            let sampleCount = length / (bytesPerSample * channelCount)

            // Convert to mono Float32
            var monoSamples = [Float](repeating: 0, count: sampleCount)

            if isFloat && bytesPerSample == 4 {
                // Already Float32
                dataPointer.withMemoryRebound(to: Float.self, capacity: sampleCount * channelCount) { floatPtr in
                    if channelCount == 1 {
                        monoSamples = Array(UnsafeBufferPointer(start: floatPtr, count: sampleCount))
                    } else {
                        for i in 0..<sampleCount {
                            var sum: Float = 0
                            for ch in 0..<channelCount {
                                sum += floatPtr[i * channelCount + ch]
                            }
                            monoSamples[i] = sum / Float(channelCount)
                        }
                    }
                }
            } else if !isFloat && bytesPerSample == 2 {
                // Int16 PCM
                dataPointer.withMemoryRebound(to: Int16.self, capacity: sampleCount * channelCount) { int16Ptr in
                    for i in 0..<sampleCount {
                        var sum: Float = 0
                        for ch in 0..<channelCount {
                            sum += Float(int16Ptr[i * channelCount + ch]) / 32768.0
                        }
                        monoSamples[i] = sum / Float(channelCount)
                    }
                }
            }

            // Resample to 16kHz if needed
            if abs(sampleRate - 16000) > 1.0 {
                monoSamples = resample(monoSamples, from: sampleRate, to: 16000)
            }

            ringBuffer.write(monoSamples)

            // Notify main app audio is available
            let center = CFNotificationCenterGetDarwinNotifyCenter()
            CFNotificationCenterPostNotification(
                center,
                CFNotificationName("com.voiceping.translate.audioReady" as CFString),
                nil, nil, true
            )

        case .audioMic:
            // Microphone audio — discard (we only want app audio)
            break
        case .video:
            // Video frames — discard
            break
        @unknown default:
            break
        }
    }

    /// Simple linear resampling from source to target sample rate.
    private func resample(_ samples: [Float], from sourceSR: Double, to targetSR: Double) -> [Float] {
        let ratio = sourceSR / targetSR
        let outputCount = Int(Double(samples.count) / ratio)
        guard outputCount > 0 else { return [] }

        var output = [Float](repeating: 0, count: outputCount)
        for i in 0..<outputCount {
            let srcIndex = Double(i) * ratio
            let idx0 = Int(srcIndex)
            let frac = Float(srcIndex - Double(idx0))
            let idx1 = min(idx0 + 1, samples.count - 1)
            output[i] = samples[idx0] * (1 - frac) + samples[idx1] * frac
        }
        return output
    }
}
