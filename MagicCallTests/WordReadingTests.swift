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

    func testElipsParseWordField() throws {
        let json = #"{"count":3,"outputWords":"Madrid","receiveCount":9}"#.data(using: .utf8)!
        guard let object = ApiJSON.object(from: json) else {
            XCTFail("expected JSON object")
            return
        }
        let reading = try WordApiClient.parse(object, provider: .elips, raw: "")
        XCTAssertEqual(reading.word, "Madrid")
        XCTAssertEqual(reading.receiveCount, 9)
    }

    func testCustomParseLabelWithOptionalCounters() throws {
        let json = #"{"count":2,"receiveCount":5,"word":"Car"}"#.data(using: .utf8)!
        guard let object = ApiJSON.object(from: json) else {
            XCTFail("expected JSON object")
            return
        }
        let reading = try WordApiClient.parse(object, provider: .custom, raw: "")
        XCTAssertEqual(reading.word, "Car")
        XCTAssertEqual(reading.count, 2)
        XCTAssertEqual(reading.receiveCount, 5)
    }

    func testCanonicalPhoneDigitsSpain() {
        XCTAssertEqual(WordApiSettings.canonicalPhoneDigits("690 808 919", region: "ES"), "34690808919")
        XCTAssertEqual(WordApiSettings.canonicalPhoneDigits("+34 690 808 919", region: "ES"), "34690808919")
        XCTAssertEqual(WordApiSettings.canonicalPhoneDigits("0034690808919", region: "ES"), "34690808919")
        XCTAssertEqual(WordApiSettings.canonicalPhoneDigits("034690808919", region: "ES"), "34690808919")
        XCTAssertEqual(WordApiSettings.canonicalPhoneDigits("812 345 678", region: "ES"), "34812345678")
    }

    func testCanonicalPhoneDigitsDropsTrunkZero() {
        XCTAssertEqual(WordApiSettings.canonicalPhoneDigits("06 12 34 56 78", region: "FR"), "33612345678")
        XCTAssertEqual(WordApiSettings.canonicalPhoneDigits("030 1234567", region: "DE"), "49301234567")
        XCTAssertEqual(WordApiSettings.canonicalPhoneDigits("07700 900123", region: "GB"), "447700900123")
        XCTAssertEqual(WordApiSettings.canonicalPhoneDigits("020 7123 4567", region: "GB"), "442071234567")
        XCTAssertEqual(WordApiSettings.canonicalPhoneDigits("06 12345678", region: "NL"), "31612345678")
    }

    func testCallerNumberFormatWarningFlagsNumbersWithoutCountryCode() {
        XCTAssertNotNil(WordApiSettings.callerNumberFormatWarning(digits: "690 808 919", region: "US"))
        XCTAssertNil(WordApiSettings.callerNumberFormatWarning(digits: "690 808 919", region: "ES"))
        XCTAssertNil(WordApiSettings.callerNumberFormatWarning(digits: "34690808919", region: "US"))
        XCTAssertNil(WordApiSettings.callerNumberFormatWarning(digits: "", region: "ES"))
        XCTAssertNotNil(WordApiSettings.callerNumberFormatWarning(digits: "34690808919", region: "RU"))
    }

    func testCanonicalPhoneDigitsKeepsInternationalAndItalianZero() {
        XCTAssertEqual(WordApiSettings.canonicalPhoneDigits("+33 6 12 34 56 78", region: "ES"), "33612345678")
        XCTAssertEqual(WordApiSettings.canonicalPhoneDigits("(415) 555-0123", region: "US"), "14155550123")
        XCTAssertEqual(WordApiSettings.canonicalPhoneDigits("06 1234567", region: "IT"), "39061234567")
        XCTAssertEqual(WordApiSettings.canonicalPhoneDigits("987 654 321", region: "PE"), "51987654321")
    }
}
