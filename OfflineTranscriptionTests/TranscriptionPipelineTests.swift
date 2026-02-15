import XCTest
@testable import OfflineTranscription

/// Tests that emulate audio feeding and the transcription pipeline.
/// Uses testFeedResult() to exercise processTranscriptionResult directly.
///
/// NOTE: The translation project disables eager segment confirmation
/// (SenseVoice returns a single segment whose text changes every cycle).
/// All segments go to `unconfirmedSegments`; `confirmedSegments` stays empty.
@MainActor
final class TranscriptionPipelineTests: XCTestCase {

    private var service: WhisperService!

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "selectedModelVariant")
        service = WhisperService()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "selectedModelVariant")
        service = nil
        super.tearDown()
    }

    private func seg(_ text: String, _ start: Float, _ end: Float) -> ASRSegment {
        ASRSegment(id: Int.random(in: 0...10000), text: text, start: start, end: end)
    }

    private func result(_ segments: [ASRSegment]) -> ASRResult {
        ASRResult(
            text: segments.map(\.text).joined(separator: " "),
            segments: segments, language: "en"
        )
    }

    // MARK: - Basic feeding

    func testFirstResultGoesToUnconfirmed() {
        service.testFeedResult(result([seg(" Hello", 0, 1), seg(" world", 1, 2)]))
        XCTAssertEqual(service.confirmedSegments.count, 0)
        XCTAssertEqual(service.unconfirmedSegments.count, 2)
        XCTAssertEqual(service.confirmedText, "")
        XCTAssertTrue(service.hypothesisText.contains("Hello"))
    }

    func testSecondResultReplacesFirst() {
        service.testFeedResult(result([seg(" Hello", 0, 1), seg(" world", 1, 2)]))
        service.testFeedResult(result([seg(" Hello", 0, 1), seg(" there", 1, 2.5)]))

        // No eager confirmation in translation project — all in unconfirmed
        XCTAssertEqual(service.confirmedSegments.count, 0)
        XCTAssertEqual(service.unconfirmedSegments.count, 2)
        XCTAssertTrue(service.hypothesisText.contains("Hello"))
        XCTAssertTrue(service.hypothesisText.contains("there"))
        XCTAssertFalse(service.hypothesisText.contains("world"))
    }

    func testMultipleFeedsReplaceUnconfirmed() {
        service.testFeedResult(result([
            seg(" The", 0, 0.5), seg(" quick", 0.5, 1), seg(" brown", 1, 1.5),
        ]))
        service.testFeedResult(result([
            seg(" The", 0, 0.5), seg(" quick", 0.5, 1), seg(" brown", 1, 1.5), seg(" fox", 1.5, 2),
        ]))

        XCTAssertEqual(service.confirmedSegments.count, 0)
        XCTAssertEqual(service.unconfirmedSegments.count, 4)
        XCTAssertTrue(service.hypothesisText.contains("fox"))
    }

    func testCompletelyDifferentResultReplaces() {
        service.testFeedResult(result([seg(" Hello", 0, 1)]))
        service.testFeedResult(result([seg(" Goodbye", 0, 1)]))

        XCTAssertEqual(service.confirmedSegments.count, 0)
        XCTAssertEqual(service.unconfirmedSegments.count, 1)
        XCTAssertEqual(service.unconfirmedSegments[0].text, " Goodbye")
    }

    // MARK: - Empty result

    func testEmptyResult() {
        service.testFeedResult(result([]))
        XCTAssertEqual(service.confirmedSegments.count, 0)
        XCTAssertEqual(service.unconfirmedSegments.count, 0)
        XCTAssertEqual(service.fullTranscriptionText, "")
    }

    // MARK: - Progressive transcription

    func testProgressiveGrowth() {
        service.testFeedResult(result([seg(" The quick", 0, 1)]))
        XCTAssertEqual(service.fullTranscriptionText, "The quick")

        service.testFeedResult(result([seg(" The quick", 0, 1), seg(" brown", 1, 1.5)]))
        XCTAssertTrue(service.fullTranscriptionText.contains("quick"))
        XCTAssertTrue(service.fullTranscriptionText.contains("brown"))
    }

    // MARK: - Stress test

    func testRapidSuccessiveResults() {
        for i in 0..<20 {
            var segs: [ASRSegment] = []
            for j in 0...i {
                segs.append(seg(" word\(j)", Float(j), Float(j + 1)))
            }
            service.testFeedResult(result(segs))
        }

        let total = service.confirmedSegments.count + service.unconfirmedSegments.count
        XCTAssertGreaterThan(total, 0)
        // Last feed had 20 segments (word0..word19)
        XCTAssertEqual(service.unconfirmedSegments.count, 20)
    }

    // MARK: - Clear and session isolation

    func testClearResetsAllState() {
        service.testFeedResult(result([seg(" Session one", 0, 5)]))
        XCTAssertTrue(service.fullTranscriptionText.contains("Session one"))

        service.clearTranscription()

        XCTAssertEqual(service.confirmedSegments.count, 0)
        XCTAssertEqual(service.unconfirmedSegments.count, 0)
        XCTAssertEqual(service.confirmedText, "")
        XCTAssertEqual(service.hypothesisText, "")
        XCTAssertEqual(service.fullTranscriptionText, "")
    }

    func testClearBetweenSessions() {
        service.testFeedResult(result([seg(" Session one", 0, 2)]))
        XCTAssertTrue(service.fullTranscriptionText.contains("Session one"))

        service.clearTranscription()
        XCTAssertEqual(service.fullTranscriptionText, "")

        service.testFeedResult(result([seg(" Session two", 0, 2)]))
        XCTAssertEqual(service.unconfirmedSegments.count, 1)
        XCTAssertEqual(service.unconfirmedSegments[0].text, " Session two")
        XCTAssertFalse(service.fullTranscriptionText.contains("Session one"))
        XCTAssertTrue(service.fullTranscriptionText.contains("Session two"))
    }

    func testFiveRapidClearCycles() {
        for cycle in 0..<5 {
            service.testFeedResult(result([seg(" Cycle \(cycle)", 0, 2)]))
            XCTAssertTrue(service.fullTranscriptionText.contains("Cycle \(cycle)"))

            service.clearTranscription()
            XCTAssertEqual(service.fullTranscriptionText, "",
                           "Cycle \(cycle): state should be clean after clear")
        }
    }

    // MARK: - Language detection

    func testLanguageDetectionUpdated() {
        service.testFeedResult(ASRResult(text: "Bonjour", segments: [seg(" Bonjour", 0, 1)], language: "fr"))
        XCTAssertEqual(service.detectedLanguage, "fr")

        service.testFeedResult(ASRResult(text: "Hello", segments: [seg(" Hello", 0, 1)], language: "en"))
        XCTAssertEqual(service.detectedLanguage, "en")
    }

    // MARK: - Hypothesis text

    func testHypothesisTextUpdates() {
        service.testFeedResult(result([seg(" first pass", 0, 2)]))
        XCTAssertTrue(service.hypothesisText.contains("first pass"))

        service.testFeedResult(result([seg(" second pass", 0, 2)]))
        XCTAssertTrue(service.hypothesisText.contains("second pass"))
        XCTAssertFalse(service.hypothesisText.contains("first pass"))
    }
}
