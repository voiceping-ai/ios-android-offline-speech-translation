package com.voiceping.offlinetranscription.service

import android.os.Build
import android.util.Log
import com.k2fsa.sherpa.onnx.FeatureConfig
import com.k2fsa.sherpa.onnx.OfflineModelConfig
import com.k2fsa.sherpa.onnx.OfflineMoonshineModelConfig
import com.k2fsa.sherpa.onnx.OfflineOmnilingualAsrCtcModelConfig
import com.k2fsa.sherpa.onnx.OfflineRecognizer
import com.k2fsa.sherpa.onnx.OfflineRecognizerConfig
import com.k2fsa.sherpa.onnx.OfflineSenseVoiceModelConfig
import com.k2fsa.sherpa.onnx.OfflineTransducerModelConfig
import com.voiceping.offlinetranscription.model.SherpaModelType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * ASR engine backed by sherpa-onnx for offline models such as SenseVoice and Parakeet.
 * Expects a model directory containing the required ONNX files + tokens.txt.
 *
 * All access to [recognizer] is guarded by [lock] so that release()
 * cannot free the recognizer while transcribe() is in-flight.
 */
class SherpaOnnxEngine(
    private val modelType: SherpaModelType
) : AsrEngine {
    companion object {
        private const val TAG = "SherpaOnnxEngine"
    }

    private var recognizer: OfflineRecognizer? = null
    private val lock = ReentrantLock()

    override val isLoaded: Boolean get() = lock.withLock { recognizer != null }

    override suspend fun loadModel(modelPath: String): Boolean {
        release()
        return withContext(Dispatchers.IO) {
            lock.withLock {
                val providers = preferredProviders()
                val threads = computeOfflineThreads()
                var lastError: Throwable? = null
                try {
                    for (provider in providers) {
                        try {
                            val config = buildConfig(
                                modelDir = modelPath,
                                threads = threads,
                                provider = provider
                            )
                            recognizer = OfflineRecognizer(config = config)
                            Log.i(TAG, "Loaded sherpa model with provider=$provider threads=$threads")
                            return@withContext true
                        } catch (e: Throwable) {
                            lastError = e
                            Log.w(TAG, "Failed to initialize provider=$provider, trying fallback", e)
                        }
                    }
                } catch (outer: Throwable) {
                    lastError = outer
                }
                Log.e(TAG, "Failed to load sherpa model from $modelPath", lastError)
                recognizer = null
                false
            }
        }
    }

    override suspend fun transcribe(
        audioSamples: FloatArray,
        numThreads: Int,
        language: String
    ): List<TranscriptionSegment> {
        return withContext(Dispatchers.IO) {
            lock.withLock {
                val rec = recognizer ?: return@withContext emptyList()
                val stream = rec.createStream()
                try {
                    stream.acceptWaveform(audioSamples, sampleRate = 16000)
                    rec.decode(stream)
                    val result = rec.getResult(stream)

                    if (result.text.isBlank()) return@withContext emptyList()

                    val lang = result.lang.takeIf { it.isNotBlank() }
                    buildSegments(result.text, result.timestamps, lang)
                } catch (e: Throwable) {
                    Log.e(TAG, "Sherpa transcribe failed", e)
                    emptyList()
                } finally {
                    stream.release()
                }
            }
        }
    }

    override fun release() {
        lock.withLock {
            recognizer?.release()
            recognizer = null
        }
    }

    private fun buildConfig(modelDir: String, threads: Int, provider: String): OfflineRecognizerConfig {
        val tokensPath = File(modelDir, "tokens.txt").absolutePath

        val modelConfig = when (modelType) {
            SherpaModelType.MOONSHINE -> OfflineModelConfig(
                moonshine = OfflineMoonshineModelConfig(
                    preprocessor = File(modelDir, "preprocess.onnx").absolutePath,
                    encoder = findFile(modelDir, "encode"),
                    uncachedDecoder = findFile(modelDir, "uncached_decode"),
                    cachedDecoder = findFile(modelDir, "cached_decode"),
                ),
                tokens = tokensPath,
                numThreads = threads,
                debug = false,
                provider = provider,
            )
            SherpaModelType.ZIPFORMER_TRANSDUCER -> throw IllegalArgumentException(
                "ZIPFORMER_TRANSDUCER should use SherpaOnnxStreamingEngine, not SherpaOnnxEngine"
            )
            SherpaModelType.SENSE_VOICE -> OfflineModelConfig(
                senseVoice = OfflineSenseVoiceModelConfig(
                    model = findFile(modelDir, "model"),
                    language = "auto",
                    useInverseTextNormalization = true,
                ),
                tokens = tokensPath,
                numThreads = threads,
                debug = false,
                provider = provider,
            )
            SherpaModelType.OMNILINGUAL_CTC -> OfflineModelConfig(
                omnilingual = OfflineOmnilingualAsrCtcModelConfig(
                    model = findFile(modelDir, "model"),
                ),
                tokens = tokensPath,
                numThreads = threads,
                debug = false,
                provider = provider,
            )
            SherpaModelType.PARAKEET_NEMO_TRANSDUCER -> OfflineModelConfig(
                transducer = OfflineTransducerModelConfig(
                    encoder = findFile(modelDir, "encoder"),
                    decoder = findFile(modelDir, "decoder"),
                    joiner = findFile(modelDir, "joiner"),
                ),
                tokens = tokensPath,
                numThreads = threads,
                debug = false,
                provider = provider,
                // Required by sherpa-onnx for NeMo transducer exports (Parakeet-TDT).
                modelType = "nemo_transducer",
            )
        }

        return OfflineRecognizerConfig(
            featConfig = FeatureConfig(sampleRate = 16000, featureDim = 80),
            modelConfig = modelConfig,
            decodingMethod = "greedy_search",
        )
    }

    private fun computeOfflineThreads(): Int {
        val cores = Runtime.getRuntime().availableProcessors().coerceAtLeast(1)
        return when {
            cores <= 2 -> 1
            cores <= 4 -> 2
            cores <= 8 -> 4
            else -> 6
        }
    }

    private fun preferredProviders(): List<String> {
        val providers = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= 27) {
            providers += "nnapi"
        }
        providers += "cpu"
        return providers
    }

    /** Find the int8 version of a model file, falling back to the non-quantized version. */
    private fun findFile(dir: String, baseName: String): String {
        val int8 = File(dir, "$baseName.int8.onnx")
        if (int8.exists()) return int8.absolutePath
        return File(dir, "$baseName.onnx").absolutePath
    }

    private fun buildSegments(
        text: String,
        timestamps: FloatArray?,
        detectedLanguage: String? = null
    ): List<TranscriptionSegment> {
        if (timestamps != null && timestamps.size >= 2) {
            val startMs = (timestamps.first() * 1000).toLong()
            val endMs = (timestamps.last() * 1000).toLong()
            return listOf(TranscriptionSegment(
                text = text.trim(), startMs = startMs, endMs = endMs,
                detectedLanguage = detectedLanguage
            ))
        }
        return listOf(TranscriptionSegment(
            text = text.trim(), startMs = 0, endMs = 0,
            detectedLanguage = detectedLanguage
        ))
    }
}
