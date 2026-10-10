import Contacts
import Foundation
import Photos
import UIKit

/// Outcome for Home **Test contact photo** (and other user-visible apply attempts).
enum AlbumArtContactApplyOutcome: Equatable {
    case success(String)
    case failure(String)

    var message: String {
        switch self {
        case .success(let text), .failure(let text): return text
        }
    }

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

/// Album artwork on song lock — contact photo and/or Photo Library (shared download + crop).
enum AlbumArtContactService {
    private static let store = CNContactStore()
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        return URLSession(configuration: config)
    }()

    @MainActor
    static func processOnSongLock(track: PreviewTrack, reason: String) {
        guard AlbumArtContactSettings.anyOutputEnabled else { return }
        guard track.artworkURL != nil else {
            dlogDebug("[ALBUM-ART] skip (\(reason)): no artwork URL · \(track.title)")
            return
        }
        let trackLabel = "\(track.title) — \(track.artist)"
        AppModel.shared.runAlbumArtContactWork {
            await processArtwork(for: track, trackLabel: trackLabel, reason: reason)
        }
    }

    /// Backward-compatible entry for older call sites.
    @MainActor
    static func applyOnSongLock(track: PreviewTrack, reason: String) {
        processOnSongLock(track: track, reason: reason)
    }

    /// Home test lab — same download, crop, and Contacts save as song lock (no Perform required).
    @MainActor
    static func applyTestContactPhoto(
        track: PreviewTrack,
        contactIdentifier: String,
        contactPhoneDigits: String,
        contactDisplayName: String
    ) async -> AlbumArtContactApplyOutcome {
        let trackLabel = "\(track.title) — \(track.artist)"
        let idSnippet = WordApiInputPanel.truncated(contactIdentifier, max: 16)
        let phoneLabel = contactPhoneDigits.isEmpty ? "none" : "+\(contactPhoneDigits)"
        albumArtLog(
            "contact · id=\(idSnippet) · name=\(WordApiInputPanel.truncated(contactDisplayName, max: 24)) · phone=\(phoneLabel) · auth=\(contactsAuthorizationLabel())"
        )
        if let url = track.artworkURL {
            albumArtLog("artwork URL · \(url.absoluteString)")
        } else {
            albumArtLog("artwork URL · nil")
            return finishTestApply(.failure("No artwork for this track."), trackLabel: trackLabel)
        }
        do {
            let jpeg = try await fetchSquareJPEGForTest(track: track)
            guard await ensureContactsAccess(reason: "test") else {
                albumArtLog("save skipped · Contacts access denied")
                return finishTestApply(
                    .failure("Contacts access denied — enable in Settings → MindtoneX → Contacts."),
                    trackLabel: trackLabel
                )
            }
            let fallbackPhones = storedPhoneFallbacks(identifier: contactIdentifier, displayName: contactDisplayName)
            do {
                let count = try await SpectatorContactFetch.run {
                    try applyImageData(
                        jpeg,
                        contactIdentifier: contactIdentifier,
                        phoneDigits: contactPhoneDigits,
                        displayName: contactDisplayName,
                        fallbackPhoneDigits: fallbackPhones,
                        reason: "test"
                    )
                }
                albumArtLog("save ok · updated \(count) contact(s)")
                let msg = count == 1 ? "Contact photo updated." : "Updated \(count) contact photo(s)."
                return finishTestApply(.success(msg), trackLabel: trackLabel)
            } catch {
                albumArtLog("save failed · \(SpectatorContactFetch.errorLogLabel(error)) · auth=\(contactsAuthorizationLabel())")
                if SpectatorContactFetch.isFullAccess {
                    albumArtLog("hint · Full Access but card not saved — suggest Limited Access + re-pick")
                }
                return finishTestApply(.failure(SpectatorContactFetch.saveFailureMessage(for: error)), trackLabel: trackLabel)
            }
        } catch let err as AlbumArtContactError {
            albumArtLog("failed · \(err.userMessage)")
            return finishTestApply(.failure(err.userMessage), trackLabel: trackLabel)
        } catch is CancellationError {
            albumArtLog("failed · cancelled")
            return finishTestApply(.failure("Apply was interrupted — try again."), trackLabel: trackLabel)
        } catch {
            let msg = SpectatorContactFetch.userFacingMessage(for: error)
            albumArtLog("failed · \(msg)")
            return finishTestApply(.failure(msg), trackLabel: trackLabel)
        }
    }

    private static func contactsAuthorizationLabel() -> String {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorized: return "full"
        case .limited: return "limited"
        @unknown default: return "unknown"
        }
    }

    private static func fetchSquareJPEGForTest(track: PreviewTrack) async throws -> Data {
        guard let url = track.artworkURL else { throw AlbumArtContactError.noArtworkURL }
        let fetchURL = upgradedArtworkURL(url)
        let (data, _) = try await session.data(from: fetchURL)
        albumArtLog("download · \(data.count) bytes")
        guard let image = UIImage(data: data) else { throw AlbumArtContactError.invalidImageData }
        guard let (jpeg, sidePx) = centerCroppedSquareJPEGWithSide(image) else {
            throw AlbumArtContactError.cropFailed
        }
        albumArtLog("crop · \(jpeg.count) bytes JPEG · \(sidePx)px")
        return jpeg
    }

    @MainActor
    private static func finishTestApply(_ outcome: AlbumArtContactApplyOutcome, trackLabel: String) -> AlbumArtContactApplyOutcome {
        switch outcome {
        case .success(let msg):
            albumArtLog("done · success · \(msg)")
            PerformUserLog.shared.log("Album art test · \(msg) · «\(WordApiInputPanel.truncated(trackLabel, max: 36))»")
        case .failure(let msg):
            albumArtLog("done · failure · \(msg)")
            PerformUserLog.shared.log("Album art test failed · \(msg)")
        }
        return outcome
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
    private static func processArtwork(for track: PreviewTrack, trackLabel: String, reason: String) async {
        do {
            let jpeg = try await fetchSquareJPEG(for: track, reason: reason)
            if AlbumArtContactSettings.saveToPhotosEnabled {
                await saveToPhotoLibrary(jpeg: jpeg, trackLabel: trackLabel, reason: reason)
            }
            if AlbumArtContactSettings.enabled {
                await applyContactArtwork(jpeg: jpeg, trackLabel: trackLabel, reason: reason)
            }
        } catch AlbumArtContactError.noArtworkURL {
            dlogDebug("[ALBUM-ART] skip (\(reason)): no artwork URL · \(trackLabel)")
        } catch AlbumArtContactError.invalidImageData {
            dlogDebug("[ALBUM-ART] skip (\(reason)): invalid image data")
        } catch AlbumArtContactError.cropFailed {
            dlogDebug("[ALBUM-ART] skip (\(reason)): crop failed")
        } catch {
            dlog("✗ [ALBUM-ART] download (\(reason)): \(SpectatorContactFetch.userFacingMessage(for: error))")
        }
    }

    private enum AlbumArtContactError: Error {
        case noArtworkURL
        case invalidImageData
        case cropFailed
        case noContactTarget

        var userMessage: String {
            switch self {
            case .noArtworkURL: return "No artwork for this track."
            case .invalidImageData: return "Downloaded artwork could not be read as an image."
            case .cropFailed: return "Could not crop artwork to a square."
            case .noContactTarget: return "No contact selected for test."
            }
        }
    }

    private static func fetchSquareJPEG(for track: PreviewTrack, reason: String) async throws -> Data {
        guard let url = track.artworkURL else { throw AlbumArtContactError.noArtworkURL }
        let fetchURL = upgradedArtworkURL(url)
        let (data, _) = try await session.data(from: fetchURL)
        guard let image = UIImage(data: data) else { throw AlbumArtContactError.invalidImageData }
        guard let (jpeg, _) = centerCroppedSquareJPEGWithSide(image) else { throw AlbumArtContactError.cropFailed }
        return jpeg
    }

    @MainActor
    private static func applyContactArtwork(jpeg: Data, trackLabel: String, reason: String) async {
        guard await ensureContactsAccess(reason: reason) else { return }
        do {
            let count: Int
            if WordApiSettings.contactMode == .known, let id = WordApiSettings.knownContactIdentifier {
                let phoneDigits = WordApiSettings.knownContactPhoneDigits
                let displayName = WordApiSettings.knownContactDisplayName
                let fallbackPhones = storedPhoneFallbacks(identifier: id, displayName: displayName)
                count = try await SpectatorContactFetch.run {
                    try applyImageData(
                        jpeg,
                        contactIdentifier: id,
                        phoneDigits: phoneDigits,
                        displayName: displayName,
                        fallbackPhoneDigits: fallbackPhones,
                        reason: reason
                    )
                }
            } else if let phone = WordApiSettings.spectatorContactPhoneE164String() {
                count = try await SpectatorContactFetch.run { try applyImageData(jpeg, phone: phone, reason: reason) }
            } else {
                dlogDebug("[ALBUM-ART] skip (\(reason)): no spectator phone — dial or pick contact first")
                PerformUserLog.shared.log("Album art · no phone yet · dial or choose contact on Album art card")
                return
            }
            dlogDebug("[ALBUM-ART] contact «\(trackLabel)» → \(count) card(s) (\(reason))")
            PerformUserLog.shared.log("Album art on contact · \(count) card(s) · «\(WordApiInputPanel.truncated(trackLabel, max: 36))»")
        } catch {
            albumArtLog("song-lock save failed (\(reason)) · \(SpectatorContactFetch.errorLogLabel(error)) · auth=\(contactsAuthorizationLabel())")
            let msg = SpectatorContactFetch.saveFailureMessage(for: error)
            dlog("✗ [ALBUM-ART] contact save (\(reason)): \(msg)")
            PerformUserLog.shared.log("Album art on contact failed · \(msg)")
        }
    }

    @MainActor
    private static func saveToPhotoLibrary(jpeg: Data, trackLabel: String, reason: String) async {
        guard await ensurePhotoLibraryAddAccess(reason: reason) else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: jpeg, options: nil)
            } completionHandler: { success, error in
                Task { @MainActor in
                    if success {
                        dlogDebug("[ALBUM-ART] saved to Photos «\(trackLabel)» (\(reason))")
                        PerformUserLog.shared.log(
                            "Album art saved to Photos · «\(WordApiInputPanel.truncated(trackLabel, max: 36))»"
                        )
                    } else {
                        let message = error.map { SpectatorContactFetch.userFacingMessage(for: $0) } ?? "Could not save to Photos."
                        dlog("✗ [ALBUM-ART] Photos save (\(reason)): \(message)")
                        PerformUserLog.shared.log("Album art not saved to Photos · \(message)")
                    }
                    continuation.resume()
                }
            }
        }
    }

    @MainActor
    private static func ensurePhotoLibraryAddAccess(reason: String) async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            if newStatus == .authorized || newStatus == .limited { return true }
            logPhotosDenied(reason: reason)
            return false
        case .denied, .restricted:
            logPhotosDenied(reason: reason)
            return false
        @unknown default:
            logPhotosDenied(reason: reason)
            return false
        }
    }

    @MainActor
    private static func logPhotosDenied(reason: String) {
        dlog("[ALBUM-ART] Photos add denied (\(reason))")
        PerformUserLog.shared.logConnectionIssue(
            "Save album art to Photos is on but Photo Library access is off — enable in Settings → MindtoneX → Photos."
        )
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

    private static func centerCroppedSquareJPEGWithSide(_ image: UIImage, maxSide: CGFloat = 600) -> (Data, Int)? {
        let image = normalizedUIImage(image)
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let cropSide = min(size.width, size.height)
        let originX = (size.width - cropSide) / 2
        let originY = (size.height - cropSide) / 2

        let cropRenderer = UIGraphicsImageRenderer(size: CGSize(width: cropSide, height: cropSide))
        let cropped = cropRenderer.image { _ in
            image.draw(in: CGRect(x: -originX, y: -originY, width: size.width, height: size.height))
        }

        let targetSide = min(maxSide, max(cropped.size.width, cropped.size.height))
        let scaled: UIImage
        if targetSide < max(cropped.size.width, cropped.size.height) {
            let scaleRenderer = UIGraphicsImageRenderer(size: CGSize(width: targetSide, height: targetSide))
            scaled = scaleRenderer.image { _ in
                cropped.draw(in: CGRect(origin: .zero, size: CGSize(width: targetSide, height: targetSide)))
            }
        } else {
            scaled = cropped
        }
        guard let jpeg = jpegDataForContact(scaled, maxBytes: 280_000) else { return nil }
        let sidePx = Int(max(scaled.size.width, scaled.size.height).rounded())
        return (jpeg, sidePx)
    }

    private static func normalizedUIImage(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    /// Contacts expects JPEG; keep under a practical size limit.
    private static func jpegDataForContact(_ image: UIImage, maxBytes: Int) -> Data? {
        var quality: CGFloat = 0.92
        var best: Data?
        while quality >= 0.45 {
            if let data = image.jpegData(compressionQuality: quality) {
                best = data
                if data.count <= maxBytes { return data }
            }
            quality -= 0.12
        }
        return best
    }

    /// Known / test-picker phones saved for this same card (matched by id or display name).
    @MainActor
    private static func storedPhoneFallbacks(identifier: String, displayName: String) -> [String] {
        func sameCard(id: String?, name: String?) -> Bool {
            if let id, id == identifier { return true }
            let wanted = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !wanted.isEmpty, let name else { return false }
            return name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(wanted) == .orderedSame
        }
        var phones: [String] = []
        if sameCard(id: WordApiSettings.knownContactIdentifier, name: WordApiSettings.knownContactDisplayName) {
            phones.append(WordApiSettings.knownContactPhoneDigits)
        }
        if sameCard(id: AlbumArtContactSettings.testContactIdentifier, name: AlbumArtContactSettings.testContactDisplayName) {
            phones.append(AlbumArtContactSettings.testContactPhoneDigits)
        }
        return phones.filter { $0.count >= 7 }
    }

    /// Runs on `SpectatorContactFetch.workQueue`.
    private static func applyImageData(
        _ jpeg: Data,
        contactIdentifier: String,
        phoneDigits: String,
        displayName: String,
        fallbackPhoneDigits: [String],
        reason: String
    ) throws -> Int {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactImageDataKey as CNKeyDescriptor,
            CNContactImageDataAvailableKey as CNKeyDescriptor,
        ]
        let resolution = try SpectatorContactFetch.resolveContact(
            store: store,
            identifier: contactIdentifier,
            phoneDigits: phoneDigits,
            displayName: displayName,
            fallbackPhoneDigits: fallbackPhoneDigits,
            keysToFetch: keys,
            log: { albumArtLog("resolve · \($0)") }
        )
        let existing = resolution.contact
        let resolvedLabel = "«\(WordApiInputPanel.truncated(SpectatorContactFetch.displayName(of: existing), max: 24))» · id=\(WordApiInputPanel.truncated(existing.identifier, max: 16))"
        if resolution.resolvedByPhone {
            albumArtLog(
                "re-resolved by phone · +\(resolution.matchedPhoneDigits) · \(resolution.phoneMatchCount) match(es) · \(resolvedLabel)"
            )
        } else if resolution.resolvedByName {
            albumArtLog("re-resolved by name · \(resolvedLabel)")
        }
        if existing.identifier != contactIdentifier {
            let phone = WordApiContactPhoneParsing.e164(from: existing)
            DispatchQueue.main.async {
                persistResolvedIdentifier(existing.identifier, replacing: contactIdentifier, phoneE164: phone)
            }
        }
        let had = existing.imageDataAvailable && existing.imageData != nil
        let restoreEntries = [
            AlbumArtContactRestoreEntry(
                identifier: existing.identifier,
                previousImageData: had ? existing.imageData : nil,
                hadImage: had,
                createdForShow: false
            ),
        ]
        let mutable = existing.mutableCopy() as! CNMutableContact
        mutable.imageData = jpeg
        let save = CNSaveRequest()
        save.update(mutable)
        try executeLogged(save, reason: reason)
        AlbumArtContactRestoreStore.replaceEntries(restoreEntries)
        return 1
    }

    private static func executeLogged(_ save: CNSaveRequest, reason: String) throws {
        do {
            try store.execute(save)
        } catch {
            albumArtLog("CNSaveRequest failed (\(reason)) · \(SpectatorContactFetch.errorLogLabel(error))")
            throw error
        }
    }

    @MainActor
    private static func persistResolvedIdentifier(_ identifier: String, replacing stale: String, phoneE164: String?) {
        if WordApiSettings.knownContactIdentifier == stale {
            WordApiSettings.updateKnownContactIdentifier(identifier)
            if let phoneE164, WordApiSettings.knownContactPhoneDigits.count < 7 {
                WordApiSettings.updateKnownContactPhoneDigits(phoneE164)
            }
        }
        if AlbumArtContactSettings.testContactIdentifier == stale {
            AlbumArtContactSettings.updateTestContactIdentifier(identifier)
            if let phoneE164, AlbumArtContactSettings.testContactPhoneDigits.count < 7 {
                AlbumArtContactSettings.updateTestContactPhoneDigits(phoneE164)
            }
        }
    }

    /// Runs on `SpectatorContactFetch.workQueue`.
    private static func applyImageData(_ jpeg: Data, phone: String, reason: String) throws -> Int {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactImageDataKey as CNKeyDescriptor,
            CNContactImageDataAvailableKey as CNKeyDescriptor,
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
            try executeLogged(save, reason: reason)
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
        try executeLogged(save, reason: reason)
        AlbumArtContactRestoreStore.replaceEntries(restoreEntries)
        return matches.count
    }

    @MainActor
    private static func runRestoreSnapshots(_ snapshots: [AlbumArtContactRestoreEntry], reason: String) async {
        guard await ensureContactsAccess(reason: reason) else { return }
        var restored = 0
        for entry in snapshots {
            do {
                try await SpectatorContactFetch.run {
                    if entry.createdForShow {
                        try deleteContact(identifier: entry.identifier)
                    } else {
                        try restoreImage(entry)
                    }
                }
                restored += 1
            } catch {
                dlog("✗ [ALBUM-ART] restore \(entry.identifier) (\(reason)): \(error.localizedDescription)")
            }
        }
        AlbumArtContactRestoreStore.clear()
        if restored > 0 {
            dlogDebug("[ALBUM-ART] restore (\(reason)) · \(restored) card(s)")
            PerformUserLog.shared.log("Album art restored · \(restored) contact photo(s)")
        }
    }

    private static func deleteContact(identifier: String) throws {
        let keys: [CNKeyDescriptor] = [CNContactIdentifierKey as CNKeyDescriptor]
        let contact = try SpectatorContactFetch.unifiedContact(
            store: store,
            identifier: identifier,
            keysToFetch: keys
        )
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
        let contact = try SpectatorContactFetch.unifiedContact(
            store: store,
            identifier: entry.identifier,
            keysToFetch: keys
        )
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
            let granted = await requestContactsAccess()
            if !granted { logContactsDenied(reason: reason) }
            return granted
        case .denied, .restricted:
            logContactsDenied(reason: reason)
            return false
        @unknown default:
            logContactsDenied(reason: reason)
            return false
        }
    }

    private static func requestContactsAccess() async -> Bool {
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
    private static func logContactsDenied(reason: String) {
        dlog("[ALBUM-ART] Contacts denied (\(reason))")
        guard reason != "test" else { return }
        PerformUserLog.shared.logConnectionIssue(
            "Album art on contact needs Contacts access — enable in Settings to show song artwork on the incoming call."
        )
    }
}
