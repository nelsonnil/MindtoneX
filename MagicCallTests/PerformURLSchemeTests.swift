import XCTest
@testable import MagicCall

final class PerformURLSchemeTests: XCTestCase {
    func testSongQueriesFromSong1AndSong2() throws {
        let url = try XCTUnwrap(URL(string: "magiccall://start-perform?song1=Thriller%20Michael%20Jackson&song2=Billie%20Jean%20Michael%20Jackson"))
        let queries = PerformURLScheme.songQueries(from: url)
        XCTAssertEqual(queries, ["Thriller Michael Jackson", "Billie Jean Michael Jackson"])
    }

    func testSongQueriesFromSongAlias() throws {
        let url = try XCTUnwrap(URL(string: "magiccall://start-perform?song=Despacito%20Luis%20Fonsi"))
        XCTAssertEqual(PerformURLScheme.songQueries(from: url), ["Despacito Luis Fonsi"])
    }

    func testSongQueriesFromPipeSeparatedSongsParam() throws {
        let url = try XCTUnwrap(URL(string: "magiccall://start-perform?songs=Gasolina%20Daddy%20Yankee|Despacito%20Luis%20Fonsi"))
        XCTAssertEqual(
            PerformURLScheme.songQueries(from: url),
            ["Gasolina Daddy Yankee", "Despacito Luis Fonsi"]
        )
    }

    func testPerformDeepLinkWithoutSongs() throws {
        let url = try XCTUnwrap(URL(string: "magiccall://start-perform"))
        XCTAssertTrue(PerformURLScheme.songQueries(from: url).isEmpty)
    }
}
