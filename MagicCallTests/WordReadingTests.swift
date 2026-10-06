import XCTest
@testable import MagicCall

final class WordReadingTests: XCTestCase {
    func testInjectParseValueAndReceiveCount() throws {
        let json = #"{"count":786,"value":"Nelson, 1 676","receiveCount":291}"#.data(using: .utf8)!
        guard let object = ApiJSON.object(from: json) else {
            XCTFail("expected JSON object")
            return
        }
        let reading = try WordApiClient.parse(object, provider: .inject, raw: "")
        XCTAssertEqual(reading.count, 786)
        XCTAssertEqual(reading.receiveCount, 291)
        XCTAssertEqual(reading.word, "Nelson, 1 676")
    }

    func testInjectParseSelectionField() throws {
        let json = #"{"count":1,"selection":"Rose","receiveCount":2}"#.data(using: .utf8)!
        guard let object = ApiJSON.object(from: json) else {
            XCTFail("expected JSON object")
            return
        }
        let reading = try WordApiClient.parse(object, provider: .inject, raw: "")
        XCTAssertEqual(reading.word, "Rose")
    }

    func testIsNewWordWhenReceiveCountIncreases() {
        let base = WordReading(count: 786, receiveCount: 10, word: "Same", raw: "")
        let next = WordReading(count: 786, receiveCount: 11, word: "Same", raw: "")
        XCTAssertTrue(next.isNewWord(comparedTo: base))
    }

    func testIsNewWordWhenTextChanges() {
        let base = WordReading(count: 786, receiveCount: 10, word: "Alpha", raw: "")
        let next = WordReading(count: 786, receiveCount: 10, word: "Beta", raw: "")
        XCTAssertTrue(next.isNewWord(comparedTo: base))
    }

    func testIsNewWordUnchangedSnapshot() {
        let base = WordReading(count: 786, receiveCount: 10, word: "Alpha", raw: "")
        let next = WordReading(count: 786, receiveCount: 10, word: "Alpha", raw: "")
        XCTAssertFalse(next.isNewWord(comparedTo: base))
    }

    func testIsNewWordWhenCountIncreases() {
        let base = WordReading(count: 5, receiveCount: nil, word: "X", raw: "")
        let next = WordReading(count: 6, receiveCount: nil, word: "X", raw: "")
        XCTAssertTrue(next.isNewWord(comparedTo: base))
    }

    func testShouldLockOnPollDeltaFromBaseline() {
        let baseline = WordReading(count: 786, receiveCount: 291, word: "Old", raw: #"{"value":"Old"}"#)
        let previous = baseline
        let next = WordReading(count: 786, receiveCount: 292, word: "Old", raw: #"{"value":"Old","receiveCount":292}"#)
        XCTAssertTrue(next.shouldLockPerformWord(comparedTo: baseline, previousPoll: previous))
    }

    func testShouldNotLockWhenFrozenLikeBaseline() {
        let baseline = WordReading(count: 786, receiveCount: 291, word: "Same", raw: "{}")
        let previous = baseline
        let next = baseline
        XCTAssertFalse(next.shouldLockPerformWord(comparedTo: baseline, previousPoll: previous))
    }
}
