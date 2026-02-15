namespace OfflineSpeechTranslation.Models;

/// <summary>
/// Metadata for an available offline translation model (CTranslate2).
/// Models can be downloaded either:
/// - as a single .zip and extracted under LocalAppData, or
/// - as a list of required files (Hugging Face "resolve/main" URLs).
/// </summary>
public sealed record TranslationModelInfo(
    string Id,
    string DisplayName,
    string SourceLanguageCode,
    string TargetLanguageCode,
    string SizeOnDisk
)
{
    /// <summary>
    /// Optional: a single zip package URL containing the CT2 model directory + tokenizers.
    /// When set, <see cref="Services.TranslationModelDownloader"/> will download + extract this zip.
    /// </summary>
    public string? ZipUrl { get; init; }

    /// <summary>
    /// Optional: list of files to download directly into the extracted model folder.
    /// Use this to reference an existing Hugging Face repo without re-packaging into a zip.
    /// </summary>
    public IReadOnlyList<ModelFile>? Files { get; init; }

    public static IReadOnlyList<TranslationModelInfo> AvailableModels { get; } =
    [
        // NOTE: These models are hosted as individual files on Hugging Face.
        // They are downloaded and cached locally under LocalAppData.
        new TranslationModelInfo(
            Id: "ct2-opus-mt-en-ja-int8",
            DisplayName: "EN → JA (OPUS-MT, INT8, CTranslate2)",
            SourceLanguageCode: "en",
            TargetLanguageCode: "ja",
            SizeOnDisk: "~75 MB"
        )
        {
            Files =
            [
                new ModelFile("https://huggingface.co/manancode/opus-mt-en-jap-ctranslate2-android/resolve/main/model.bin", "model.bin"),
                new ModelFile("https://huggingface.co/manancode/opus-mt-en-jap-ctranslate2-android/resolve/main/config.json", "config.json"),
                new ModelFile("https://huggingface.co/manancode/opus-mt-en-jap-ctranslate2-android/resolve/main/shared_vocabulary.json", "shared_vocabulary.json"),
                new ModelFile("https://huggingface.co/manancode/opus-mt-en-jap-ctranslate2-android/resolve/main/source.spm", "source.spm"),
                new ModelFile("https://huggingface.co/manancode/opus-mt-en-jap-ctranslate2-android/resolve/main/target.spm", "target.spm"),
                // Small, but helpful for transparency/debugging (not strictly required by the native wrapper).
                new ModelFile("https://huggingface.co/manancode/opus-mt-en-jap-ctranslate2-android/resolve/main/tokenizer_config.json", "tokenizer_config.json"),
                new ModelFile("https://huggingface.co/manancode/opus-mt-en-jap-ctranslate2-android/resolve/main/vocab.json", "vocab.json"),
            ]
        },

        new TranslationModelInfo(
            Id: "ct2-opus-mt-ja-en-int8",
            DisplayName: "JA → EN (OPUS-MT, INT8, CTranslate2)",
            SourceLanguageCode: "ja",
            TargetLanguageCode: "en",
            SizeOnDisk: "~90 MB"
        )
        {
            Files =
            [
                new ModelFile("https://huggingface.co/manancode/opus-mt-ja-en-ctranslate2-android/resolve/main/model.bin", "model.bin"),
                new ModelFile("https://huggingface.co/manancode/opus-mt-ja-en-ctranslate2-android/resolve/main/config.json", "config.json"),
                new ModelFile("https://huggingface.co/manancode/opus-mt-ja-en-ctranslate2-android/resolve/main/shared_vocabulary.json", "shared_vocabulary.json"),
                new ModelFile("https://huggingface.co/manancode/opus-mt-ja-en-ctranslate2-android/resolve/main/source.spm", "source.spm"),
                new ModelFile("https://huggingface.co/manancode/opus-mt-ja-en-ctranslate2-android/resolve/main/target.spm", "target.spm"),
                new ModelFile("https://huggingface.co/manancode/opus-mt-ja-en-ctranslate2-android/resolve/main/tokenizer_config.json", "tokenizer_config.json"),
                new ModelFile("https://huggingface.co/manancode/opus-mt-ja-en-ctranslate2-android/resolve/main/vocab.json", "vocab.json"),
            ]
        }
    ];

    public static TranslationModelInfo? Find(string sourceLanguageCode, string targetLanguageCode)
    {
        var src = NormalizeLang(sourceLanguageCode);
        var tgt = NormalizeLang(targetLanguageCode);
        return AvailableModels.FirstOrDefault(m =>
            m.SourceLanguageCode == src && m.TargetLanguageCode == tgt);
    }

    private static string NormalizeLang(string code) =>
        (code ?? "").Trim().ToLowerInvariant();
}
