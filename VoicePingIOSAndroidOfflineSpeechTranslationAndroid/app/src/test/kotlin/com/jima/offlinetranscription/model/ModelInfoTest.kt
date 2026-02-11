package com.voiceping.offlinetranscription.model

import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class ModelInfoTest {

    @Test
    fun availableModels_hasExpectedEntries() {
        val ids = ModelInfo.availableModels.map { it.id }
        assertEquals(2, ids.size)
        assertTrue("sensevoice-small" in ids)
        assertTrue("android-speech" in ids)
    }

    @Test
    fun defaultModel_isSenseVoiceSmall() {
        assertEquals("sensevoice-small", ModelInfo.defaultModel.id)
        assertEquals(EngineType.SHERPA_ONNX, ModelInfo.defaultModel.engineType)
        assertEquals(SherpaModelType.SENSE_VOICE, ModelInfo.defaultModel.sherpaModelType)
    }

    @Test
    fun modelIds_areUnique() {
        val ids = ModelInfo.availableModels.map { it.id }
        assertEquals(ids.size, ids.toSet().size, "Model IDs must be unique")
    }

    @Test
    fun sensevoiceModel_hasExpectedFilesAndMetadata() {
        val model = ModelInfo.availableModels.first { it.id == "sensevoice-small" }
        assertEquals("SenseVoice Small", model.displayName)
        assertEquals(EngineType.SHERPA_ONNX, model.engineType)
        assertEquals(SherpaModelType.SENSE_VOICE, model.sherpaModelType)
        assertEquals("zh/en/ja/ko/yue", model.languages)
        assertEquals(2, model.files.size)

        val names = model.files.map { it.localName }.toSet()
        assertTrue("model.int8.onnx" in names)
        assertTrue("tokens.txt" in names)
    }

    @Test
    fun allFiles_haveHttpsHuggingFaceUrls() {
        ModelInfo.availableModels
            .filter { it.files.isNotEmpty() }
            .forEach { model ->
                model.files.forEach { file ->
                    assertTrue(file.url.startsWith("https://"), "URL should be HTTPS for ${model.id}:${file.localName}")
                    assertTrue(file.url.contains("huggingface.co"), "URL should be HuggingFace for ${model.id}:${file.localName}")
                }
            }
    }

    @Test
    fun modelsByEngine_groupsCorrectly() {
        val grouped = ModelInfo.modelsByEngine
        val sherpa = grouped[EngineType.SHERPA_ONNX]
        assertNotNull(sherpa)
        assertEquals(1, sherpa.size)
        assertTrue(sherpa.any { it.id == "sensevoice-small" })

        val androidSpeech = grouped[EngineType.ANDROID_SPEECH]
        assertNotNull(androidSpeech)
        assertEquals(1, androidSpeech.size)
        assertTrue(androidSpeech.any { it.id == "android-speech" })
    }

    @Test
    fun inferenceMethodLabel_isEngineSpecific() {
        val sherpa = ModelInfo.availableModels.first { it.engineType == EngineType.SHERPA_ONNX }
        assertEquals("sherpa-onnx offline (ONNX Runtime)", sherpa.inferenceMethod)

        val androidSpeech = ModelInfo.availableModels.first { it.engineType == EngineType.ANDROID_SPEECH }
        assertEquals("Android SpeechRecognizer (on-device)", androidSpeech.inferenceMethod)
    }

    @Test
    fun enumCardinality_isExpected() {
        assertEquals(2, EngineType.entries.size)
        assertEquals(1, SherpaModelType.entries.size)
    }

    @Test
    fun androidSpeechModel_hasExpectedMetadata() {
        val model = ModelInfo.availableModels.first { it.id == "android-speech" }
        assertEquals("Android Speech", model.displayName)
        assertEquals(EngineType.ANDROID_SPEECH, model.engineType)
        assertEquals(null, model.sherpaModelType)
        assertTrue(model.files.isEmpty(), "Android Speech should have no files to download")
        assertEquals("0 MB", model.sizeOnDisk)
        assertEquals("System", model.parameterCount)
    }

    @Test
    fun dataClassEquality_stillWorks() {
        val a = ModelInfo(
            id = "test",
            displayName = "Test",
            engineType = EngineType.SHERPA_ONNX,
            sherpaModelType = SherpaModelType.SENSE_VOICE,
            parameterCount = "1M",
            sizeOnDisk = "~1 MB",
            description = "desc",
            files = listOf(ModelFile("https://huggingface.co/test.bin", "test.bin"))
        )
        val b = a.copy()
        assertEquals(a, b)
    }
}
