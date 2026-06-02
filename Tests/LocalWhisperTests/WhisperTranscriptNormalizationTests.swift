import XCTest
@testable import LocalWhisper

// whisper-server returns one line per decode window / VAD segment. On long
// audio that is several `\n`-separated lines, which fragment the dictation when
// pasted into newline-submits apps so the user sees only the last line. These
// tests pin the normalization that collapses those breaks into single spaces.
final class WhisperTranscriptNormalizationTests: XCTestCase {
    func testCollapsesInternalNewlinesToSpaces() {
        let raw = " Prima frase.\n Seconda frase.\n Terza frase."
        XCTAssertEqual(
            WhisperServerWorker.normalizeTranscript(raw),
            "Prima frase. Seconda frase. Terza frase."
        )
    }

    func testNoNewlineInOutput() {
        let raw = "line one\nline two\nline three\n"
        let result = WhisperServerWorker.normalizeTranscript(raw)
        XCTAssertFalse(result.contains("\n"))
    }

    func testTrimsLeadingAndTrailingWhitespace() {
        XCTAssertEqual(WhisperServerWorker.normalizeTranscript("  hello world  "), "hello world")
    }

    func testCollapsesRunsOfWhitespace() {
        XCTAssertEqual(WhisperServerWorker.normalizeTranscript("a\t\t b   c"), "a b c")
    }

    func testSingleLineUnchanged() {
        XCTAssertEqual(WhisperServerWorker.normalizeTranscript("Ciao Marco, come stai?"),
                       "Ciao Marco, come stai?")
    }

    func testEmptyOrWhitespaceOnly() {
        XCTAssertEqual(WhisperServerWorker.normalizeTranscript(""), "")
        XCTAssertEqual(WhisperServerWorker.normalizeTranscript("   \n  \n"), "")
    }
}
