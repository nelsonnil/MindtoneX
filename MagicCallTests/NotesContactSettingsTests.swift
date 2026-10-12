import XCTest
@testable import MagicCall

final class NotesContactSettingsTests: XCTestCase {
    private var savedNoteBody: String?

    override func setUp() {
        super.setUp()
        savedNoteBody = UserDefaults.standard.string(forKey: NotesContactSettings.Key.noteBody)
        UserDefaults.standard.removeObject(forKey: NotesContactSettings.Key.noteBody)
        UserDefaults.standard.removeObject(forKey: NotesContactSettings.Key.buttonPlaceholder)
        NotesContactSettings.registerDefaults()
    }

    override func tearDown() {
        if let savedNoteBody {
            UserDefaults.standard.set(savedNoteBody, forKey: NotesContactSettings.Key.noteBody)
        } else {
            UserDefaults.standard.removeObject(forKey: NotesContactSettings.Key.noteBody)
        }
        super.tearDown()
    }

    func testStaticTemplateReadyWithoutLockedWord() {
        UserDefaults.standard.set("Prediction: rose", forKey: NotesContactSettings.Key.noteBody)
        XCTAssertTrue(NotesContactSettings.isContactNoteReadyForSave(lockedWord: nil))
        XCTAssertEqual(
            NotesContactSettings.resolvedContactNote(lockedWord: nil),
            "Prediction: rose"
        )
    }

    func testTokenTemplateNotReadyUntilWordLocked() {
        UserDefaults.standard.set("Word was {word}", forKey: NotesContactSettings.Key.noteBody)
        XCTAssertFalse(NotesContactSettings.isContactNoteReadyForSave(lockedWord: nil))
        XCTAssertEqual(
            NotesContactSettings.resolvedContactNote(lockedWord: "Oracle"),
            "Word was Oracle"
        )
        XCTAssertTrue(NotesContactSettings.isContactNoteReadyForSave(lockedWord: "Oracle"))
    }
}
