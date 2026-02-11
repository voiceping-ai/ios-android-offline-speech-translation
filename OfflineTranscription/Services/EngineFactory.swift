import Foundation

/// Creates the appropriate ASREngine for a given model.
@MainActor
enum EngineFactory {
    private typealias EngineBuilder = @MainActor () -> ASREngine
    private static let builders: [ASREngineType: EngineBuilder] = [
        .appleSpeech: { AppleSpeechEngine() },
        .sherpaOnnxOffline: { SherpaOnnxOfflineEngine() }
    ]

    static func makeEngine(for model: ModelInfo) -> ASREngine {
        if let builder = builders[model.engineType] {
            return builder()
        }
        return AppleSpeechEngine()
    }
}
