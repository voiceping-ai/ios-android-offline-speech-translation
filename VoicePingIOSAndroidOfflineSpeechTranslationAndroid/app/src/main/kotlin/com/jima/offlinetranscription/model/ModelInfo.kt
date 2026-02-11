package com.voiceping.offlinetranscription.model

enum class EngineType { SHERPA_ONNX, ANDROID_SPEECH }
enum class SherpaModelType { SENSE_VOICE }

data class ModelFile(val url: String, val localName: String)

data class ModelInfo(
    val id: String,
    val displayName: String,
    val engineType: EngineType,
    val sherpaModelType: SherpaModelType? = null,
    val parameterCount: String,
    val sizeOnDisk: String,
    val description: String,
    val languages: String = "99 languages",
    val files: List<ModelFile>,
) {
    val inferenceMethod: String
        get() = when (engineType) {
            EngineType.SHERPA_ONNX -> "sherpa-onnx offline (ONNX Runtime)"
            EngineType.ANDROID_SPEECH -> "Android SpeechRecognizer (on-device)"
        }

    companion object {
        private const val SENSEVOICE_BASE_URL =
            "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/"

        val availableModels = listOf(
            ModelInfo(
                id = "sensevoice-small",
                displayName = "SenseVoice Small",
                engineType = EngineType.SHERPA_ONNX,
                sherpaModelType = SherpaModelType.SENSE_VOICE,
                parameterCount = "234M",
                sizeOnDisk = "~240 MB",
                description = "Multilingual (zh/en/ja/ko/yue). 5x faster than Whisper Small.",
                languages = "zh/en/ja/ko/yue",
                files = listOf(
                    ModelFile("${SENSEVOICE_BASE_URL}model.int8.onnx", "model.int8.onnx"),
                    ModelFile("${SENSEVOICE_BASE_URL}tokens.txt", "tokens.txt"),
                )
            ),
            ModelInfo(
                id = "android-speech",
                displayName = "Android Speech",
                engineType = EngineType.ANDROID_SPEECH,
                parameterCount = "System",
                sizeOnDisk = "0 MB",
                description = "Built-in Android speech recognition. No download required. On-device on Android 12+.",
                languages = "System languages",
                files = emptyList()
            ),
        )

        val defaultModel = availableModels.first { it.id == "sensevoice-small" }

        /** Group models by engine for UI display. */
        val modelsByEngine: Map<EngineType, List<ModelInfo>>
            get() = availableModels.groupBy { it.engineType }
    }
}
