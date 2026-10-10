import Contacts
import Foundation
import UIKit

/// Applies locked song album artwork to the spectator contact (center-cropped for iOS call UI).
enum AlbumArtContactService {
    private static let store = CNContactStore()
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        return URLSession(configuration: config)
    }()

    @MainActor
    static func applyOnSongLock(track: PreviewTrack, reason: String) {
        guard AlbumArtContactSettings.enabled else { return }
        guard let url = track.artworkURL else {
            dlog("[ALBUM-ART] skip (\(reason)): no artwork URL · \(track.title)")
            return
        }
        Task {
            await applyArtwork(from: url, trackLabel: "\(track.title) — \(track.artist)", reason: reason)
        }
    }

    @MainActor
    static func restoreContactsAfterPerform(reason: String) {
        let snapshots = AlbumArtContactRestoreStore.entries
        guard !snapshots.isEmpty else { return }

        guard WordApiSettings.restoreKnownNameOnSettingsExit else {
            AlbumArtContactRestoreStore.clear()
            return
        }

        Task {
            await runRestoreSnapshots(snapshots, reason: reason)
        }
    }

    // MARK: - Private

    @MainActor
    private static func applyArtwork(from url: URL, trackLabel: String, reason: String) async {
        guard await ensureContactsAccess(reason: reason) else { return }
        guard let phone = WordApiSettings.spectatorContactPhoneE164String() else {
            dlog("[ALBUM-ART] skip (\(reason)): no spectator phone — dial or pick contact first")
            PerformUserLog.shared.log("Album art · no phone yet · dial or choose contact on Album art card")
            return
        }

        let fetchURL = upgradedArtworkURL(url)
        do {
            let (data, _) = try await session.data(from: fetchURL)
            guard let image = UIImage(data: data) else {
                dlog("[ALBUM-ART] skip (\(reason)): invalid image data")
                return
            }
            guard let jpeg = centerCroppedSquareJPEG(image) else {
                dlog("[ALBUM-ART] skip (\(reason)): crop failed")
                return
            }
            let count = try applyImageData(jpeg, phone: phone, reason: reason)
            dlog("[ALBUM-ART] applied «\(trackLabel)» → \(count) card(s) (\(reason))")
            PerformUserLog.shared.log("Album art on contact · \(count) card(s) · «\(WordApiInputPanel.truncated(trackLabel, max: 36))»")
        } catch {
            dlog("✗ [ALBUM-ART] download (\(reason)): \(error.localizedDescription)")
        }
    }

    private static func upgradedArtworkURL(_ url: URL) -> URL {
        var raw = url.absoluteString
        if raw.contains("100x100bb") {
            raw = raw.replacingOccurrences(of: "100x100bb", with: "600x600bb")
        } else if raw.contains("100x100") {
            raw = raw.replacingOccurrences(of: "100x100", with: "600x600")
        }
        return URL(string: raw) ?? url
    }

    private static func centerCroppedSquareJPEG(_ image: UIImage, side: CGFloat = 600) -> Data? {
        let scale = image.scale
        guard let cg = image.cgImage else { return nil }
        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)
        let cropSide = min(w, h)
        let originX = (w - cropSide) / 2
        let originY = (h - cropSide) / 2
        guard let cropped = cg.cropping(to: CGRect(x: originX, y: originY, width: cropSide, height: cropSide)) else {
            return nil
        }
        let square = UIImage(cgImage: cropped, scale: scale, orientation: image.imageOrientation)
        let targetSide = min(side, max(square.size.width, square.size.height))
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: targetSide, height: targetSide))
        let rendered = renderer.image { _ in
            square.draw(in: CGRect(origin: .zero, size: CGSize(width: targetSide, height: targetSide)))
        }
        return rendered.jpegData(compressionQuality: 0.92)
    }

    private static func applyImageData(_ jpeg: Data, phone: String, reason: String) throws -> Int {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactImageDataKey as CNKeyDescriptor,
        ]
        let matches = try cards(withPhone: phone, keysToFetch: keys)
        let save = CNSaveRequest()
        var restoreEntries: [AlbumArtContactRestoreEntry] = []

        if matches.isEmpty {
            let contact = CNMutableContact()
            contact.givenName = "MindtoneX"
            contact.phoneNumbers = [
                CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: phone)),
            ]
            contact.imageData = jpeg
            save.add(contact, toContainerWithIdentifier: store.defaultContainerIdentifier())
            try store.execute(save)
            restoreEntries = [
                AlbumArtContactRestoreEntry(
                    identifier: contact.identifier,
                    previousImageData: nil,
                    hadImage: false,
                    createdForShow: true
                ),
            ]
            AlbumArtContactRestoreStore.replaceEntries(restoreEntries)
            return 1
        }

        restoreEntries = matches.map { existing in
            let had = existing.imageDataAvailable && existing.imageData != nil
            return AlbumArtContactRestoreEntry(
                identifier: existing.identifier,
                previousImageData: had ? existing.imageData : nil,
                hadImage: had,
                createdForShow: false
            )
        }

        for existing in matches {
            let mutable = existing.mutableCopy() as! CNMutableContact
            mutable.imageData = jpeg
            save.update(mutable)
        }
        try store.execute(save)
        AlbumArtContactRestoreStore.replaceEntries(restoreEntries)
        return matches.count
    }

    @MainActor
    private static func runRestoreSnapshots(_ snapshots: [AlbumArtContactRestoreEntry], reason: String) async {
        guard await ensureContactsAccess(reason: reason) else { return }
        var restored = 0
        for entry in snapshots {
            do {
                if entry.createdForShow {
                    try deleteContact(identifier: entry.identifier)
                } else {
                    try restoreImage(entry)
                }
                restored += 1
            } catch {
                dlog("✗ [ALBUM-ART] restore \(entry.identifier) (\(reason)): \(error.localizedDescription)")
            }
        }
        AlbumArtContactRestoreStore.clear()
        if restored > 0 {
            dlog("[ALBUM-ART] restore (\(reason)) · \(restored) card(s)")
            PerformUserLog.shared.log("Album art restored · \(restored) contact photo(s)")
        }
    }

    private static func deleteContact(identifier: String) throws {
        let keys: [CNKeyDescriptor] = [CNContactIdentifierKey as CNKeyDescriptor]
        let contact = try store.unifiedContact(withIdentifier: identifier, keysToFetch: keys)
        let mutable = contact.mutableCopy() as! CNMutableContact
        let save = CNSaveRequest()
        save.delete(mutable)
        try store.execute(save)
    }

    private static func restoreImage(_ entry: AlbumArtContactRestoreEntry) throws {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactImageDataKey as CNKeyDescriptor,
        ]
        let contact = try store.unifiedContact(withIdentifier: entry.identifier, keysToFetch: keys)
        let mutable = contact.mutableCopy() as! CNMutableContact
        if entry.hadImage, let data = entry.previousImageData {
            mutable.imageData = data
        } else {
            mutable.imageData = nil
        }
        let save = CNSaveRequest()
        save.update(mutable)
        try store.execute(save)
    }

    private static func cards(withPhone phone: String, keysToFetch keys: [CNKeyDescriptor]) throws -> [CNContact] {
        try store.unifiedContacts(
            matching: CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: phone)),
            keysToFetch: keys
        )
    }

    @MainActor
    private static func ensureContactsAccess(reason: String) async -> Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let granted = await requestAccess()
            if !granted { logDenied(reason: reason) }
            return granted
        case .denied, .restricted:
            logDenied(reason: reason)
            return false
        @unknown default:
            logDenied(reason: reason)
            return false
        }
    }

    private static func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            store.requestAccess(for: .contacts) { granted, error in
                if let error {
                    dlog("✗ [ALBUM-ART] permission: \(error.localizedDescription)")
                }
                continuation.resume(returning: granted)
            }
        }
    }

    @MainActor
    private static func logDenied(reason: String) {
        dlog("[ALBUM-ART] denied (\(reason))")
        PerformUserLog.shared.logConnectionIssue(
            "Album art needs Contacts access — enable in Settings to show song artwork on the incoming call."
        )
    }
}
