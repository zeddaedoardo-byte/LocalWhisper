import XCTest
@testable import LocalWhisper

// whisper.cpp VAD (silero, this build) drops large contiguous spans of speech
// on long audio. VAD only benefits very short utterances, so the worker must
// enable it per-request only below a duration threshold. These tests pin that
// gating decision, which is pure arithmetic over the recorded WAV byte count.
final class WhisperVADGatingTests: XCTestCase {
    // 16 kHz mono int16 PCM (AudioRecorderService output) => 32000 bytes/s.
    private let bytesPerSecond = 32_000
    private let header = 44

    private func bytes(seconds: Double) -> Int {
        header + Int(seconds * Double(bytesPerSecond))
    }

    func testShortClipUsesVAD() {
        XCTAssertTrue(WhisperServerWorker.shouldUseVAD(audioByteCount: bytes(seconds: 1.5)))
        XCTAssertTrue(WhisperServerWorker.shouldUseVAD(audioByteCount: bytes(seconds: 8)))
    }

    func testLongClipDisablesVAD() {
        XCTAssertFalse(WhisperServerWorker.shouldUseVAD(audioByteCount: bytes(seconds: 12)))
        XCTAssertFalse(WhisperServerWorker.shouldUseVAD(audioByteCount: bytes(seconds: 60)))
        XCTAssertFalse(WhisperServerWorker.shouldUseVAD(audioByteCount: bytes(seconds: 258)))
    }

    func testBoundaryIsInclusiveAtThreshold() {
        XCTAssertTrue(WhisperServerWorker.shouldUseVAD(audioByteCount: bytes(seconds: 10)))
        XCTAssertFalse(WhisperServerWorker.shouldUseVAD(audioByteCount: bytes(seconds: 10.5)))
    }

    func testTinyOrEmptyAudioDoesNotUnderflow() {
        XCTAssertTrue(WhisperServerWorker.shouldUseVAD(audioByteCount: 0))
        XCTAssertTrue(WhisperServerWorker.shouldUseVAD(audioByteCount: 10))
    }
}
