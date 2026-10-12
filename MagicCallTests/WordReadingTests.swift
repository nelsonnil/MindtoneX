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

    func testContactNumberMatchesCanonicalAcrossSpellings() {
        let target = "34629815339"
        XCTAssertTrue(WordApiContactPhoneParsing.number("+34 629 81 53 39", matchesCanonical: target))
        XCTAssertTrue(WordApiContactPhoneParsing.number("629 81 53 39", matchesCanonical: target))
        XCTAssertTrue(WordApiContactPhoneParsing.number("0034629815339", matchesCanonical: target))
        XCTAssertFalse(WordApiContactPhoneParsing.number("629 81 53 30", matchesCanonical: target))
        XCTAssertEqual(WordApiContactPhoneParsing.canonicalDigits(fromContactNumber: "+34 629 81 53 39"), target)
    }

    func testContactNameMatchIgnoresAccentsCaseAndSpacing() {
        XCTAssertTrue(SpectatorContactFetch.namesMatch("papa", "Papá"))
        XCTAssertTrue(SpectatorContactFetch.namesMatch("  PAPA ", "papá"))
        XCTAssertTrue(SpectatorContactFetch.namesMatch("José  María", "jose maria"))
        XCTAssertFalse(SpectatorContactFetch.namesMatch("papa", "mama"))
        XCTAssertFalse(SpectatorContactFetch.namesMatch("", ""))
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

    func testSongSearchQueriesTitleOnlyIncludesArticleStrip() {
        let queries = SongSearchQueries.variants(fromRawQuery: "La Gasolina")
        XCTAssertTrue(queries.contains(where: { $0.caseInsensitiveCompare("La Gasolina") == .orderedSame }))
        XCTAssertTrue(queries.contains(where: { $0.caseInsensitiveCompare("Gasolina") == .orderedSame }))
    }

    func testSongPickStoreQueriesTitleWithInferredArtist() {
        let pick = SongPick(
            hasSong: true,
            title: "Gasolina",
            artist: "Daddy Yankee",
            searchQuery: "Gasolina Daddy Yankee",
            confidence: 0.9,
            reasoning: "fixture"
        )
        let all = pick.allStoreSearchQueries
        XCTAssertTrue(all.contains(where: { ApiJSON.sameText($0, "Gasolina Daddy Yankee") }))
        XCTAssertTrue(all.contains(where: { ApiJSON.sameText($0, "Gasolina") }))
    }

    func testCardHandwritingPickStoreQueriesMatchSongSearchQueries() {
        var pick = CardHandwritingPick(
            hasSong: true,
            title: "Gasolina",
            artist: "Daddy Yankee",
            searchQuery: "Gasolina Daddy Yankee",
            confidence: 0.9,
            reasoning: "fixture",
            hasCallerWord: false,
            callerWord: "",
            hasNotesWord: false,
            notesWord: ""
        )
        XCTAssertEqual(
            pick.storeSearchQueries(),
            SongSearchQueries.variants(title: "Gasolina", artist: "Daddy Yankee", rawQuery: "Gasolina Daddy Yankee")
        )
        pick = CardHandwritingPick(
            hasSong: true,
            title: "La Gasolina",
            artist: "",
            searchQuery: "La Gasolina",
            confidence: 0.85,
            reasoning: "title only",
            hasCallerWord: false,
            callerWord: "",
            hasNotesWord: false,
            notesWord: ""
        )
        let queries = pick.storeSearchQueries() + pick.storeSearchRetryQueries()
        XCTAssertTrue(queries.contains(where: { ApiJSON.sameText($0, "Gasolina") }))
    }

    func testPreviewRankPrefersDaddyYankeeGasolinaForTitleOnlyQuery() {
        let tracks = [
            PreviewTrack(title: "Gasolina", artist: "Daddy Yankee", album: nil, artworkURL: nil,
                         previewURL: URL(string: "https://example.com/a.m4a")!, source: .itunes),
            PreviewTrack(title: "La Gasolina (feat. La Favi)", artist: "Bea Pelea", album: nil, artworkURL: nil,
                         previewURL: URL(string: "https://example.com/b.m4a")!, source: .itunes),
        ]
        let ranked = PreviewService.rank(tracks, for: "La Gasolina")
        XCTAssertEqual(ranked.first?.artist, "Daddy Yankee")
    }
}
