import Foundation

/// Creates the appropriate ASREngine for a given model.
@MainActor
enum EngineFactory {
    static func makeEngine(for model: ModelInfo) -> ASREngine {
        switch model.engineType {
        case .appleSpeech:
            return AppleSpeechEngine()
        case .sherpaOnnxOffline:
            return SherpaOnnxOfflineEngine()
        }
    }
}
