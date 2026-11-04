import Contacts
import ContactsUI
import SwiftUI
import UIKit

/// Spotlight input: a swipe down on the stage screenshot opens a copy of iOS 26 Spotlight. The performer
/// types the song on the real keyboard; the search bar shows the performer's own contact name instead,
/// one character per key press. Opening the top hit shows the real contact card and hands the typed song
/// to `NotesSongSession`, which finds and prefetches it; nothing is searched before that tap.
@MainActor
final class SpotlightSession: ObservableObject {
    static let shared = SpotlightSession()

    struct ContactEntry: Identifiable, Equatable {
        let id: String
        let name: String
        let initials: String
        let words: [String]
        let thumbnail: UIImage?

        static func == (a: ContactEntry, b: ContactEntry) -> Bool { a.id == b.id && a.name == b.name }
    }

    @Published private(set) var isOpen = false
    /// 0 = home screen, 1 = Spotlight fully shown. Follows the finger during the swipe.
    @Published private(set) var reveal: CGFloat = 0
    @Published private(set) var secret = ""
    @Published private(set) var contactCardShown = false
    @Published private(set) var contacts: [ContactEntry] = []
    @Published private(set) var target: ContactEntry?

    /// Downscaled stage screenshot behind the blur; loaded once per Perform, not on every drag frame.
    private(set) var backdrop: UIImage?
    private var contactsLoading = false
    private weak var presentedCard: UIViewController?
    private let peek = SpotlightPeekHold()

    private init() {}

    var isVisible: Bool { reveal > 0 }

    var visibleText: String { String(SpotlightSettings.disguiseText.prefix(secret.count)) }

    var topHit: ContactEntry? { visibleText.count >= 2 ? (target ?? fallbackTarget) : nil }

    /// Other contacts whose name words start with what the spectator sees, like real Spotlight.
    var otherMatches: [ContactEntry] {
        let tokens = Self.words(visibleText)
        guard !tokens.isEmpty else { return [] }
        let shownAsTopHit = topHit == nil ? nil : target?.id
        return Array(contacts.lazy.filter { entry in
            entry.id != shownAsTopHit && tokens.allSatisfy { token in
                // Chinese / Japanese / Korean names have no spaces, so any part of the name can match.
                let anywhere = Self.isCJK(token)
                return entry.words.contains { anywhere ? $0.contains(token) : $0.hasPrefix(token) }
            }
        }.prefix(3))
    }

    var recents: [ContactEntry] {
        Array(contacts.lazy.filter { $0.id != self.target?.id }.prefix(2))
    }

    private var fallbackTarget: ContactEntry {
        let name = SpotlightSettings.contactName.isEmpty
            ? SpotlightSettings.disguiseText.capitalized
            : SpotlightSettings.contactName
        return ContactEntry(id: "", name: name, initials: Self.initials(name), words: Self.words(name), thumbnail: nil)
    }

    // MARK: Swipe

    func drag(translation: CGFloat) {
        guard !isOpen else { return }
        loadBackdropIfNeeded()
        reveal = min(1, max(0, translation / 260))
    }

    private func loadBackdropIfNeeded() {
        guard backdrop == nil, let image = StageImageStore.load() else { return }
        let size = CGSize(width: image.size.width / 4, height: image.size.height / 4)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        backdrop = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func dragEnded(translation: CGFloat, velocity: CGFloat) {
        guard !isOpen else { return }
        if translation > 70 || velocity > 600 {
            open()
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { reveal = 0 }
        }
    }

    func open() {
        guard !isOpen else { return }
        loadBackdropIfNeeded()
        isOpen = true
        withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) { reveal = 1 }
        SpotlightAppIconStore.shared.prefetch(SpotlightSettings.suggestedApps + [SpotlightSettings.browser.bundleId])
        target = Self.findTarget(in: contacts)
        reloadContacts()
        peek.install()
        dlog("[SPOTLIGHT] ▶︎ open · \(SpotlightSettings.summary())")
    }

    func close() {
        guard isOpen else { return }
        peek.uninstall()
        isOpen = false
        secret = ""
        withAnimation(.easeOut(duration: 0.25)) { reveal = 0 }
        dlog("[SPOTLIGHT] ◼︎ close")
    }

    func reset() {
        peek.uninstall()
        presentedCard?.dismiss(animated: false)
        presentedCard = nil
        contactCardShown = false
        isOpen = false
        reveal = 0
        secret = ""
        backdrop = nil
    }

    // MARK: Typing

    func secretChanged(_ text: String) {
        guard isOpen else { return }
        secret = text
        NotesSongSession.shared.textChanged(Self.sessionText(text))
    }

    /// 2 songs: a double space separates song 1 from song 2, e.g. “rihanna  michael jackson”.
    /// Notes reads one song per line, so the gap becomes a line break.
    static func sessionText(_ typed: String) -> String {
        guard SpectatorSettings.isTwo else { return typed }
        return typed.replacingOccurrences(of: " {2,}", with: "\n", options: .regularExpression)
    }

    func clearPressed() {
        secretChanged("")
    }

    /// Like real Spotlight, Return opens the top hit; that is also the only moment the song is searched.
    func returnPressed() {
        guard topHit != nil else { return }
        openTopHit()
    }

    // MARK: Contact card

    func openTopHit() {
        NotesSongSession.shared.submit(reason: "Spotlight contact")
        guard presentedCard == nil else { return }
        guard let contact = Self.cardContact(id: target?.id) else {
            dlog("✗ [SPOTLIGHT] top hit tapped · card unavailable · id=\(SpotlightSettings.contactIdentifier?.prefix(12) ?? "none") · access=\(CNContactStore.authorizationStatus(for: .contacts).rawValue) · picked=\(SpotlightSettings.pickedCard != nil)")
            return
        }
        guard let presenter = Self.topViewController() else {
            dlog("✗ [SPOTLIGHT] no view controller to present the card")
            return
        }
        let card = CNContactViewController(for: contact)
        card.allowsActions = true
        let nav = UINavigationController(rootViewController: card)
        nav.modalPresentationStyle = .fullScreen
        nav.overrideUserInterfaceStyle = .dark
        card.navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            primaryAction: UIAction { [weak self] _ in self?.dismissContactCard() }
        )
        contactCardShown = true
        presentedCard = nav
        presenter.present(nav, animated: true)
        dlog("[SPOTLIGHT] contact card · \(target?.name ?? "?")")
    }

    /// The live card from Contacts; otherwise the copy saved when the contact was picked.
    private static func cardContact(id targetId: String?) -> CNContact? {
        let keys = [CNContactViewController.descriptorForRequiredKeys()]
        let ids = [targetId, SpotlightSettings.contactIdentifier].compactMap { $0 }.filter { !$0.isEmpty }
        for id in ids {
            if let contact = try? CNContactStore().unifiedContact(withIdentifier: id, keysToFetch: keys) {
                return contact
            }
        }
        if let picked = SpotlightSettings.pickedCard, picked.areKeysAvailable(keys) {
            dlog("[SPOTLIGHT] card from the picked copy (Contacts store unavailable)")
            return picked
        }
        return nil
    }

    private func dismissContactCard() {
        presentedCard?.dismiss(animated: true)
        presentedCard = nil
        contactCardShown = false
    }

    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        var top = window?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }

    // MARK: Contacts

    /// Every open, so a contact created or chosen since the last Perform is found.
    private func reloadContacts() {
        guard !contactsLoading else { return }
        guard Self.contactsReadable else {
            dlog("[SPOTLIGHT] contacts not allowed — only the chosen name is shown")
            return
        }
        contactsLoading = true
        Task.detached(priority: .userInitiated) {
            let entries = Self.fetchEntries()
            await MainActor.run {
                self.contactsLoading = false
                self.contacts = entries
                self.target = Self.findTarget(in: entries)
                if let target = self.target, target.name != SpotlightSettings.contactName {
                    SpotlightSettings.saveContact(identifier: target.id, name: target.name)
                }
                dlog("[SPOTLIGHT] contacts loaded · \(entries.count) · target=\(self.target?.name ?? "none")")
            }
        }
    }

    /// The chosen card by identifier; by name when the identifier changed (iCloud re-sync, restored backup).
    private static func findTarget(in entries: [ContactEntry]) -> ContactEntry? {
        if let id = SpotlightSettings.contactIdentifier, let entry = entries.first(where: { $0.id == id }) {
            return entry
        }
        let name = nameKey(SpotlightSettings.contactName)
        guard !name.isEmpty else { return nil }
        return entries.first { nameKey($0.name) == name }
    }

    /// Same letters in any order and spacing, so an older “新松 卞” still finds “卞新松”.
    private static func nameKey(_ name: String) -> String {
        String(words(name).joined().sorted())
    }

    static var contactsReadable: Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if #available(iOS 18.0, *), status == .limited { return true }
        return status == .authorized
    }

    nonisolated private static func fetchEntries() -> [ContactEntry] {
        let keys = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .userDefault
        var entries: [ContactEntry] = []
        try? CNContactStore().enumerateContacts(with: request) { contact, _ in
            let name = displayName(of: contact)
            guard !name.isEmpty else { return }
            entries.append(ContactEntry(
                id: contact.identifier,
                name: name,
                initials: initials(name, given: contact.givenName, family: contact.familyName),
                words: words(name) + words(contact.givenName) + words(contact.familyName),
                thumbnail: contact.thumbnailImageData.flatMap(UIImage.init(data:))
            ))
        }
        return entries
    }

    /// Name as the Contacts app shows it: “Nelson Suárez”, but “卞新松” (family name first, no space) for Chinese.
    nonisolated static func displayName(of contact: CNContact) -> String {
        if contact.areKeysAvailable([CNContactFormatter.descriptorForRequiredKeys(for: .fullName)]),
           let formatted = CNContactFormatter.string(from: contact, style: .fullName), !formatted.isEmpty {
            return formatted
        }
        let person = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        return person.isEmpty ? contact.organizationName : person
    }

    nonisolated static func words(_ text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    nonisolated static func isCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x1100...0x11FF, 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF:
                return true
            default:
                return false
            }
        }
    }

    /// Latin names: “NS”. Chinese / Japanese / Korean names: the family name character (“卞”), not two mixed characters.
    nonisolated static func initials(_ name: String, given: String = "", family: String = "") -> String {
        if isCJK(name) {
            return String((family.isEmpty ? name : family).prefix(1))
        }
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map { String($0).uppercased() } }.joined()
    }
}

/// Performer peek while Spotlight or the contact card is up: holding a finger anywhere shows the stage peek
/// (typed song, found song) on top of everything. Lives on the window because the card is a UIKit modal.
@MainActor
final class SpotlightPeekHold: NSObject, UIGestureRecognizerDelegate {
    private var recognizer: UILongPressGestureRecognizer?
    private var overlay: UIViewController?

    func install() {
        guard recognizer == nil,
              let window = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return }
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        // Long enough that taps on the top hit and the card’s buttons stay taps.
        hold.minimumPressDuration = 0.4
        hold.cancelsTouchesInView = false
        hold.delaysTouchesEnded = false
        hold.delegate = self
        window.addGestureRecognizer(hold)
        recognizer = hold
    }

    func uninstall() {
        hide()
        if let recognizer { recognizer.view?.removeGestureRecognizer(recognizer) }
        recognizer = nil
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began: show(in: recognizer.view?.window)
        case .ended, .cancelled, .failed: hide()
        default: break
        }
    }

    private func show(in window: UIWindow?) {
        guard overlay == nil, PerformanceCues.peekEnabled, let window else { return }
        let store = UserDefaults.standard
        let fontSize = store.object(forKey: PerformanceCues.PeekKey.fontSize) as? Double ?? PerformanceCues.defaultPeekFontSize
        let host = UIHostingController(rootView: StagePeekOverlay(
            lines: StagePeekLines.build(model: AppModel.shared),
            fontSize: fontSize,
            colorHex: store.string(forKey: PerformanceCues.PeekKey.color) ?? PerformanceCues.defaultPeekColor,
            anchorX: store.object(forKey: PerformanceCues.PeekKey.anchorX) as? Double ?? PerformanceCues.defaultPeekAnchorX,
            anchorY: store.object(forKey: PerformanceCues.PeekKey.anchorY) as? Double ?? PerformanceCues.defaultPeekAnchorY
        ))
        let view = host.view!
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.frame = window.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(view)
        overlay = host
    }

    private func hide() {
        overlay?.view.removeFromSuperview()
        overlay = nil
    }
}
