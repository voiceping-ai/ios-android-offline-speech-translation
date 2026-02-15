package com.voiceping.offlinetranscription.service

import com.voiceping.offlinetranscription.model.ModelInfo
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.TimeUnit

class ModelDownloader(private val modelsDir: File) {

    companion object {
        private const val DOWNLOAD_BUFFER_BYTES = 8 * 1024
        private const val TEMP_SUFFIX = ".tmp"
    }

    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .followRedirects(true)
        .build()

    /** Directory for a specific model's files. */
    fun modelDir(model: ModelInfo): File = File(modelsDir, model.id)

    /** For whisper.cpp models: path to the single model file. */
    fun modelFilePath(model: ModelInfo): String {
        val dir = modelDir(model)
        return File(dir, model.files.first().localName).absolutePath
    }

    /** Check that all files for a model are downloaded. Models with no files are always "downloaded". */
    fun isModelDownloaded(model: ModelInfo): Boolean {
        if (model.files.isEmpty()) return true
        val dir = modelDir(model)
        return model.files.all { File(dir, it.localName).exists() }
    }

    /** Downloads all files for a model, emitting overall progress (0.0 to 1.0). */
    fun download(model: ModelInfo): Flow<Float> = flow {
        if (model.files.isEmpty()) {
            emit(1.0f)
            return@flow
        }

        val dir = modelDir(model)
        dir.mkdirs()

        val totalFiles = model.files.size
        for ((fileIndex, modelFile) in model.files.withIndex()) {
            val targetFile = File(dir, modelFile.localName)

            // Skip already downloaded files
            if (targetFile.exists()) {
                val overallProgress = (fileIndex + 1).toFloat() / totalFiles
                emit(overallProgress)
                continue
            }

            val tempFile = File(dir, "${modelFile.localName}$TEMP_SUFFIX")
            val requestBuilder = Request.Builder().url(modelFile.url)

            // Support resume if temp file exists
            if (tempFile.exists()) {
                requestBuilder.addHeader("Range", "bytes=${tempFile.length()}-")
            }

            var bytesRead: Long
            var totalBytes: Long
            client.newCall(requestBuilder.build()).execute().use { response ->
                if (!response.isSuccessful) {
                    throw Exception("Download failed: HTTP ${response.code} for ${modelFile.localName}")
                }

                val body = response.body ?: throw Exception("Empty response body")
                val contentLength = body.contentLength()
                val existingBytes = if (response.code == 206) tempFile.length() else 0L
                totalBytes = contentLength + existingBytes

                val outputStream = FileOutputStream(tempFile, response.code == 206)
                val buffer = ByteArray(DOWNLOAD_BUFFER_BYTES)
                bytesRead = existingBytes

                body.byteStream().use { input ->
                    outputStream.use { output ->
                        var read: Int
                        while (input.read(buffer).also { read = it } != -1) {
                            output.write(buffer, 0, read)
                            bytesRead += read
                            if (totalBytes > 0) {
                                // Progress within this file, scaled to overall progress
                                val fileProgress = bytesRead.toFloat() / totalBytes.toFloat()
                                val overallProgress = (fileIndex + fileProgress) / totalFiles
                                emit(overallProgress)
                            }
                        }
                    }
                }
            }

            // Verify download size matches Content-Length
            if (totalBytes > 0 && bytesRead != totalBytes) {
                tempFile.safeDelete()
                throw Exception(
                    "Download incomplete for ${modelFile.localName}: " +
                    "expected $totalBytes bytes, got $bytesRead bytes"
                )
            }

            // Rename temp to final
            if (!tempFile.renameTo(targetFile)) {
                tempFile.copyTo(targetFile, overwrite = true)
                if (targetFile.exists() && targetFile.length() == tempFile.length()) {
                    tempFile.safeDelete()
                } else {
                    targetFile.safeDelete()
                    throw IOException("Failed to finalize ${modelFile.localName}: copy verification failed")
                }
            }
        }
        emit(1.0f)
    }.flowOn(Dispatchers.IO)

    private fun File.safeDelete() {
        if (exists() && !delete()) {
            // Best effort cleanup only; caller validates final artifacts separately.
        }
    }
}
