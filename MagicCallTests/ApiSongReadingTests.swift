import XCTest
@testable import MagicCall

final class ApiSongReadingTests: XCTestCase {
    func testElipsParseSongAndReceiveCount() throws {
        let json = #"{"count":3,"song":"Eish Besho'ak","artist":"Fairuz","receiveCount":12}"#.data(using: .utf8)!
        guard let object = ApiJSON.object(from: json) else {
            XCTFail("expected JSON object")
            return
        }
        let reading = try ApiSongClient.parse(object, provider: .elips, raw: "")
        XCTAssertEqual(reading.title, "Eish Besho'ak")
        XCTAssertEqual(reading.artist, "Fairuz")
        XCTAssertEqual(reading.receiveCount, 12)
        XCTAssertTrue(reading.label.contains("Fairuz"))
    }

    func testShouldLockOnReceiveCountBumpWithSameTitle() {
        let baseline = ApiReading(count: 3, receiveCount: 11, title: "Same", artist: "", raw: "{}")
        let previous = baseline
        let next = ApiReading(count: 3, receiveCount: 12, title: "Same", artist: "", raw: #"{"receiveCount":12}"#)
        XCTAssertTrue(next.shouldLockPerformSong(comparedTo: baseline, previousPoll: previous))
    }

    func testShouldLockWhenTitleChangesAfterBaseline() {
        let baseline = ApiReading(count: 1, receiveCount: 1, title: "Old", artist: "", raw: "{}")
        let previous = baseline
        let next = ApiReading(count: 1, receiveCount: 1, title: "New", artist: "", raw: #"{"song":"New"}"#)
        XCTAssertTrue(next.shouldLockPerformSong(comparedTo: baseline, previousPoll: previous))
    }

    func testHandoffSnapshotMatchesSameArabicTitle() {
        let seed = ApiReading(count: 5, receiveCount: 9, title: "Eish Besho'ak", artist: "Fairuz", raw: "a")
        let poll = ApiReading(count: 5, receiveCount: 9, title: "Eish Besho'ak", artist: "Fairuz", raw: "a")
        XCTAssertTrue(poll.matchesSnapshot(of: seed))
        XCTAssertFalse(poll.isNewSearch(comparedTo: seed))
    }
}
