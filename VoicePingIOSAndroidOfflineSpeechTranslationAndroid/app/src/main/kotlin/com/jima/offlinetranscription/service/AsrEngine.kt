package com.voiceping.offlinetranscription.service

/**
 * Abstraction over ASR backends (sherpa-onnx offline, Android SpeechRecognizer).
 * Handles model loading, transcription, and resource cleanup.
 */
interface AsrEngine {
    /** Load a model from the given directory path. Returns true on success. */
    suspend fun loadModel(modelPath: String): Boolean

    /** Transcribe audio samples (16kHz mono float). Returns segments with timestamps. */
    suspend fun transcribe(
        audioSamples: FloatArray,
        numThreads: Int,
        language: String
    ): List<TranscriptionSegment>

    /** Whether a model is currently loaded and ready for transcription. */
    val isLoaded: Boolean

    /** Release all native resources. Must be called before discarding the engine. */
    fun release()

    /**
     * Whether this engine captures audio from the microphone itself (e.g. Android SpeechRecognizer).
     * When true, WhisperEngine skips its own AudioRecorder + transcribe loop and instead
     * delegates recording to the engine via [startListening] / [stopListening].
     */
    val isSelfRecording: Boolean get() = false

    /** Start self-managed microphone recording and recognition. Only called when [isSelfRecording] is true. */
    fun startListening() {}

    /** Stop self-managed recording. Only called when [isSelfRecording] is true. */
    fun stopListening() {}

    /** Get the current confirmed (final) transcription text. Only used when [isSelfRecording] is true. */
    fun getConfirmedText(): String = ""

    /** Get the current partial/hypothesis text. Only used when [isSelfRecording] is true. */
    fun getHypothesisText(): String = ""

    /** Get detected language code, or null. Only used when [isSelfRecording] is true. */
    fun getDetectedLanguage(): String? = null
}
