namespace OfflineSpeechTranslation.Utilities;

/// <summary>
/// Helper for UI-facing text normalization and "speak only the delta" behavior.
/// Kept as a small pure utility so it can be unit-tested without WinUI dependencies.
/// </summary>
public static class TextDelta
{
    /// <summary>
    /// Collapse whitespace but preserve newlines. Intended for display and delta comparisons.
    /// </summary>
    public static string NormalizeDisplayText(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return "";

        // Collapse spaces per line but keep explicit newlines.
        var lines = text.Replace("\r\n", "\n").Split('\n');
        for (int i = 0; i < lines.Length; i++)
            lines[i] = string.Join(' ', lines[i].Split(' ', StringSplitOptions.RemoveEmptyEntries)).Trim();

        return string.Join("\n", lines).Trim();
    }

    /// <summary>
    /// Returns the new suffix of <paramref name="fullText"/> after <paramref name="lastFullText"/> if it is a prefix.
    /// Otherwise returns <paramref name="fullText"/> (normalized).
    /// </summary>
    public static string ComputeDelta(string fullText, string lastFullText)
    {
        var normalized = NormalizeDisplayText(fullText);
        var prev = NormalizeDisplayText(lastFullText);

        if (prev.Length > 0 && normalized.StartsWith(prev, StringComparison.Ordinal))
            return NormalizeDisplayText(normalized[prev.Length..]);

        return normalized;
    }

    /// <summary>
    /// True if <paramref name="delta"/> contains enough letters/digits to be worth speaking.
    /// </summary>
    public static bool IsMeaningfulDelta(string delta, int minLettersOrDigits = 2)
    {
        if (string.IsNullOrWhiteSpace(delta)) return false;

        int count = 0;
        foreach (var ch in delta)
        {
            if (!char.IsLetterOrDigit(ch)) continue;
            count++;
            if (count >= minLettersOrDigits) return true;
        }

        return false;
    }
}

