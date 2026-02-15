using OfflineSpeechTranslation.Utilities;

namespace OfflineSpeechTranslation.Tests;

public class TextDeltaTests
{
    [Fact]
    public void NormalizeDisplayText_CollapsesSpaces_PreservesNewlines()
    {
        var input = "  hello   world \r\n  foo   bar  ";
        var normalized = TextDelta.NormalizeDisplayText(input);
        Assert.Equal("hello world\nfoo bar", normalized);
    }

    [Fact]
    public void ComputeDelta_WhenLastIsPrefix_ReturnsSuffix()
    {
        var delta = TextDelta.ComputeDelta("hello   world", "hello");
        Assert.Equal("world", delta);
    }

    [Fact]
    public void ComputeDelta_WhenLastNotPrefix_ReturnsFullNormalized()
    {
        var delta = TextDelta.ComputeDelta("hello world", "goodbye");
        Assert.Equal("hello world", delta);
    }

    [Theory]
    [InlineData("", false)]
    [InlineData("!", false)]
    [InlineData("a", false)]
    [InlineData("ab", true)]
    [InlineData("あ", false)]
    [InlineData("ありがとう", true)]
    public void IsMeaningfulDelta_Works(string delta, bool expected)
    {
        Assert.Equal(expected, TextDelta.IsMeaningfulDelta(delta));
    }
}

