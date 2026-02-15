using System.Diagnostics;
using System.IO.Compression;
using OfflineSpeechTranslation.Models;

namespace OfflineSpeechTranslation.Services;

public sealed class TranslationModelDownloader
{
    private static readonly HttpClient _client = new()
    {
        Timeout = TimeSpan.FromMinutes(10)
    };

    public static string TranslationModelsBaseDir =>
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "OfflineSpeechTranslation", "TranslationModels");

    public static string GetModelDir(TranslationModelInfo model) =>
        Path.Combine(TranslationModelsBaseDir, model.Id);

    public static string GetExtractedDir(TranslationModelInfo model) =>
        Path.Combine(GetModelDir(model), "model");

    private static string GetMarkerPath(TranslationModelInfo model) =>
        Path.Combine(GetModelDir(model), "extracted.ok");

    public static bool IsModelDownloaded(TranslationModelInfo model)
    {
        if (!File.Exists(GetMarkerPath(model))) return false;

        var extractedDir = GetExtractedDir(model);
        if (!Directory.Exists(extractedDir)) return false;

        // Minimal sanity check so stale markers don't cause confusing failures.
        if (!File.Exists(Path.Combine(extractedDir, "model.bin"))) return false;
        if (!File.Exists(Path.Combine(extractedDir, "config.json"))) return false;

        return true;
    }

    private static void TryDeleteFile(string path)
    {
        if (!File.Exists(path)) return;
        for (int attempt = 0; attempt < 5; attempt++)
        {
            try
            {
                File.Delete(path);
                return;
            }
            catch (IOException) when (attempt < 4)
            {
                Thread.Sleep(500);
            }
        }
    }

    private static void TryDeleteDirectory(string path)
    {
        if (!Directory.Exists(path)) return;
        for (int attempt = 0; attempt < 5; attempt++)
        {
            try
            {
                Directory.Delete(path, recursive: true);
                return;
            }
            catch (IOException) when (attempt < 4)
            {
                Thread.Sleep(800);
            }
            catch (UnauthorizedAccessException) when (attempt < 4)
            {
                Thread.Sleep(800);
            }
        }
    }

    private static void TryMoveFile(string source, string dest)
    {
        for (int attempt = 0; attempt < 10; attempt++)
        {
            try
            {
                File.Move(source, dest, overwrite: true);
                return;
            }
            catch (IOException) when (attempt < 9)
            {
                Debug.WriteLine($"[TranslationModelDownloader] File.Move attempt {attempt + 1} failed, retrying...");
                Thread.Sleep(1000);
            }
        }
    }

    public static async Task DownloadAndExtractAsync(
        TranslationModelInfo model,
        IProgress<double>? progress = null,
        CancellationToken ct = default)
    {
        var modelDir = GetModelDir(model);
        Directory.CreateDirectory(modelDir);

        var extractedDir = GetExtractedDir(model);

        try
        {
            if (!string.IsNullOrWhiteSpace(model.ZipUrl))
            {
                // Extract zip to a staging folder then swap into place (safer than overwriting in-place).
                var stagingDir = extractedDir + ".staging";
                TryDeleteDirectory(stagingDir);
                Directory.CreateDirectory(stagingDir);

                var zipPath = Path.Combine(modelDir, "model.zip");
                var tmpPath = zipPath + ".tmp";

                if (!File.Exists(zipPath))
                    await DownloadFileWithResumeAsync(model.ZipUrl, zipPath, tmpPath, progress, ct);

                // ZipFile extraction can throw if Defender has the zip locked; retry briefly.
                for (int attempt = 0; attempt < 4; attempt++)
                {
                    try
                    {
                        ZipFile.ExtractToDirectory(zipPath, stagingDir, overwriteFiles: true);
                        break;
                    }
                    catch (IOException) when (attempt < 3)
                    {
                        await Task.Delay(1000, ct);
                    }
                }

                // Swap staging -> extracted.
                TryDeleteDirectory(extractedDir);
                Directory.Move(stagingDir, extractedDir);
            }
            else if (model.Files is { Count: > 0 })
            {
                // Download directly into the extracted dir so partial downloads can be resumed.
                Directory.CreateDirectory(extractedDir);
                await DownloadFilesWithResumeAsync(model.Files, extractedDir, progress, ct);
            }
            else
            {
                throw new InvalidOperationException($"Translation model '{model.Id}' has no ZipUrl or Files.");
            }

            File.WriteAllText(GetMarkerPath(model), DateTime.UtcNow.ToString("O"));
            progress?.Report(1.0);
        }
        catch
        {
            // Best-effort cleanup:
            // - zip staging dir is cleaned on the next attempt
            // - file-based downloads keep partial .tmp files in extractedDir for resume
            throw;
        }
    }

    private static async Task DownloadFilesWithResumeAsync(
        IReadOnlyList<ModelFile> files,
        string destDir,
        IProgress<double>? progress,
        CancellationToken ct)
    {
        if (files.Count == 0) return;

        for (int i = 0; i < files.Count; i++)
        {
            ct.ThrowIfCancellationRequested();

            var f = files[i];
            var destPath = Path.Combine(destDir, f.LocalName);
            var destParent = Path.GetDirectoryName(destPath);
            if (!string.IsNullOrWhiteSpace(destParent))
                Directory.CreateDirectory(destParent);

            if (File.Exists(destPath))
            {
                try
                {
                    if (new FileInfo(destPath).Length > 0)
                    {
                        progress?.Report((i + 1) / (double)files.Count);
                        continue;
                    }
                }
                catch
                {
                    // If we can't stat the file, fall through to re-download.
                }
            }

            var tmpPath = destPath + ".tmp";

            IProgress<double>? scaledProgress = null;
            if (progress != null)
            {
                int idx = i;
                int count = files.Count;
                scaledProgress = new Progress<double>(p =>
                {
                    // Scale current-file progress into overall [0..1].
                    progress.Report((idx + Math.Clamp(p, 0.0, 1.0)) / count);
                });
            }

            await DownloadFileWithResumeAsync(f.Url, destPath, tmpPath, scaledProgress, ct);
        }
    }

    private static async Task DownloadFileWithResumeAsync(
        string url,
        string targetPath,
        string tempPath,
        IProgress<double>? progress,
        CancellationToken ct)
    {
        long existingBytes = 0;
        if (File.Exists(tempPath))
        {
            try { existingBytes = new FileInfo(tempPath).Length; }
            catch (IOException) { existingBytes = 0; }
        }

        if (existingBytes > 0)
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            request.Headers.Range = new System.Net.Http.Headers.RangeHeaderValue(existingBytes, null);
            Debug.WriteLine($"[TranslationModelDownloader] Resuming from byte {existingBytes}");

            using var response = await _client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct);
            if (response.StatusCode == System.Net.HttpStatusCode.PartialContent)
            {
                var totalBytes = (response.Content.Headers.ContentLength ?? 0) + existingBytes;
                await using var contentStream = await response.Content.ReadAsStreamAsync(ct);
                await using var fileStream = new FileStream(tempPath, FileMode.Append, FileAccess.Write, FileShare.Read, 81920, true);

                long bytesWritten = existingBytes;
                var buffer = new byte[81920];
                int bytesRead;
                while ((bytesRead = await contentStream.ReadAsync(buffer, ct)) > 0)
                {
                    await fileStream.WriteAsync(buffer.AsMemory(0, bytesRead), ct);
                    bytesWritten += bytesRead;
                    if (totalBytes > 0)
                        progress?.Report((double)bytesWritten / totalBytes);
                }
                await fileStream.FlushAsync(ct);
                TryMoveFile(tempPath, targetPath);
                return;
            }
        }

        // Fresh download
        TryDeleteFile(tempPath);
        using (var request = new HttpRequestMessage(HttpMethod.Get, url))
        using (var response = await _client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct))
        {
            response.EnsureSuccessStatusCode();
            var totalBytes = response.Content.Headers.ContentLength ?? 0;
            long bytesWritten = 0;

            await using var contentStream = await response.Content.ReadAsStreamAsync(ct);
            await using var fileStream = new FileStream(tempPath, FileMode.Create, FileAccess.Write, FileShare.Read, 81920, true);

            var buffer = new byte[81920];
            int bytesRead;
            while ((bytesRead = await contentStream.ReadAsync(buffer, ct)) > 0)
            {
                await fileStream.WriteAsync(buffer.AsMemory(0, bytesRead), ct);
                bytesWritten += bytesRead;
                if (totalBytes > 0)
                    progress?.Report((double)bytesWritten / totalBytes);
            }
            await fileStream.FlushAsync(ct);
        }

        TryMoveFile(tempPath, targetPath);
    }
}
