import XCTest
@testable import OfflineTranscription

@MainActor
final class SessionStateCITests: XCTestCase {
    func testSessionStateRawValuesAreStable() {
        XCTAssertEqual(SessionState.idle.rawValue, "idle")
        XCTAssertEqual(SessionState.starting.rawValue, "starting")
        XCTAssertEqual(SessionState.recording.rawValue, "recording")
        XCTAssertEqual(SessionState.stopping.rawValue, "stopping")
        XCTAssertEqual(SessionState.interrupted.rawValue, "interrupted")
    }

    func testWhisperServiceStartsIdle() {
        let service = WhisperService()
        XCTAssertEqual(service.sessionState, .idle)
        XCTAssertFalse(service.isRecording)
        XCTAssertFalse(service.isTranscribing)
    }
}
