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
            let phoneDigits = healedPhoneDigits(contactPhoneDigits, identifier: contactIdentifier, fallbacks: fallbackPhones)
            do {
                let applied = try await SpectatorContactFetch.run {
                    try applyImageData(
                        jpeg,
                        contactIdentifier: contactIdentifier,
                        phoneDigits: phoneDigits,
                        displayName: contactDisplayName,
                        fallbackPhoneDigits: fallbackPhones,
                        reason: "test"
                    )
                }
                albumArtLog("save ok · updated \(applied.count) contact(s)")
                if applied.unverifiedCount > 0 {
                    return finishTestApply(
                        .failure("Saved, but iOS did not keep the photo on \(applied.unverifiedCount) card(s) — send the log."),
                        trackLabel: trackLabel
                    )
                }
                var msg = applied.count == 1 ? "Contact photo updated." : "Updated \(applied.count) linked contact photo(s)."
                if let created = applied.createdFromRecentsName {
                    msg = "\(SpectatorContactFetch.RecentsNotice.message(name: created)) \(msg)"
                }
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
                let displayName = WordApiSettings.knownContactDisplayName
                let fallbackPhones = storedPhoneFallbacks(identifier: id, displayName: displayName)
                let phoneDigits = healedPhoneDigits(WordApiSettings.knownContactPhoneDigits, identifier: id, fallbacks: fallbackPhones)
                let applied = try await SpectatorContactFetch.run {
                    try applyImageData(
                        jpeg,
                        contactIdentifier: id,
                        phoneDigits: phoneDigits,
                        displayName: displayName,
                        fallbackPhoneDigits: fallbackPhones,
                        reason: reason
                    )
                }
                count = applied.count
                if let created = applied.createdFromRecentsName {
                    PerformUserLog.shared.log(SpectatorContactFetch.RecentsNotice.message(name: created))
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

    /// iTunes (`…/100x100bb.jpg`) and Deezer (`…/250x250-000000-80-0-0.jpg`) serve any size from the same path.
    private static func upgradedArtworkURL(_ url: URL) -> URL {
        let raw = url.absoluteString
        let upgraded = raw.replacingOccurrences(
            of: #"(?<=/)\d{2,4}x\d{2,4}(?=bb|-\d)"#,
            with: "1000x1000",
            options: .regularExpression
        )
        return URL(string: upgraded) ?? url
    }

    /// Square JPEG in pixels (renderer scale 1): the full-screen contact card needs a full image ≥ 600px, not just a thumbnail.
    private static func centerCroppedSquareJPEGWithSide(
        _ image: UIImage,
        minSide: CGFloat = 600,
        maxSide: CGFloat = 800
    ) -> (Data, Int)? {
        guard let cgImage = normalizedUIImage(image).cgImage else { return nil }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        guard width > 0, height > 0 else { return nil }
        let cropSide = min(width, height)
        let cropRect = CGRect(x: ((width - cropSide) / 2).rounded(.down), y: ((height - cropSide) / 2).rounded(.down), width: cropSide, height: cropSide)
        guard let croppedCG = cgImage.cropping(to: cropRect) else { return nil }

        let targetSide = min(maxSide, max(minSide, cropSide)).rounded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: targetSide, height: targetSide), format: format)
        let scaled = renderer.image { _ in
            UIImage(cgImage: croppedCG).draw(in: CGRect(x: 0, y: 0, width: targetSide, height: targetSide))
        }
        guard let jpeg = jpegDataForContact(scaled, maxBytes: 200_000) else { return nil }
        return (jpeg, Int(targetSide))
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
            guard let name else { return false }
            return SpectatorContactFetch.namesMatch(name, displayName)
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

    /// Picks made before phones were persisted have an empty phone; reuse the matching Known/test phone and save it
    /// on the stored pick so later launches start with it.
    @MainActor
    private static func healedPhoneDigits(_ phoneDigits: String, identifier: String, fallbacks: [String]) -> String {
        guard phoneDigits.count < 7, let healed = fallbacks.first else { return phoneDigits }
        if WordApiSettings.knownContactIdentifier == identifier, WordApiSettings.knownContactPhoneDigits.count < 7 {
            WordApiSettings.updateKnownContactPhoneDigits(healed)
        }
        if AlbumArtContactSettings.testContactIdentifier == identifier, AlbumArtContactSettings.testContactPhoneDigits.count < 7 {
            AlbumArtContactSettings.updateTestContactPhoneDigits(healed)
        }
        albumArtLog("phone healed from stored pick · +\(healed)")
        return healed
    }

    private struct ApplyResult {
        let count: Int
        let createdFromRecentsName: String?
        /// Cards whose photo was still missing after save + one retry.
        var unverifiedCount = 0
    }

    private static let imageKeys: [CNKeyDescriptor] = [
        CNContactIdentifierKey as CNKeyDescriptor,
        CNContactImageDataKey as CNKeyDescriptor,
        CNContactImageDataAvailableKey as CNKeyDescriptor,
    ]

    private static let rawCardKeys: [CNKeyDescriptor] = imageKeys + [
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
    ]

    /// Runs on `SpectatorContactFetch.workQueue`.
    private static func applyImageData(
        _ jpeg: Data,
        contactIdentifier: String,
        phoneDigits: String,
        displayName: String,
        fallbackPhoneDigits: [String],
        reason: String
    ) throws -> ApplyResult {
        let resolution = try SpectatorContactFetch.resolveContact(
            store: store,
            identifier: contactIdentifier,
            phoneDigits: phoneDigits,
            displayName: displayName,
            fallbackPhoneDigits: fallbackPhoneDigits,
            keysToFetch: imageKeys,
            createFromRecents: SpectatorContactFetch.RecentsCardSeed(imageData: jpeg),
            log: { albumArtLog("resolve · \($0)") }
        )
        let existing = resolution.contact
        let existingName = SpectatorContactFetch.displayName(of: existing)
        let resolvedLabel = "«\(WordApiInputPanel.truncated(existingName, max: 24))» · id=\(WordApiInputPanel.truncated(existing.identifier, max: 16))"
        if resolution.createdFromRecents {
            albumArtLog("created real card from Recents · «\(existingName)» · +\(resolution.matchedPhoneDigits)")
        } else if resolution.resolvedByPhone {
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
        var phones: [String] = []
        let cardPhones = existing.isKeyAvailable(CNContactPhoneNumbersKey) ? existing.phoneNumbers.map(\.value.stringValue) : []
        for raw in [resolution.matchedPhoneDigits, phoneDigits] + fallbackPhoneDigits + cardPhones {
            let digits = WordApiContactPhoneParsing.canonicalDigits(fromContactNumber: raw)
            if digits.count >= 7, !phones.contains(digits) { phones.append(digits) }
        }
        let linked = linkedRawCards(of: [existing], phones: phones)
        let targets = linked.isEmpty ? [existing] : linked
        albumArtLog("targets · \(targets.count) raw card(s) for unified id=\(WordApiInputPanel.truncated(existing.identifier, max: 16)) · phones=\(phones.map { "+\($0)" }.joined(separator: ","))")
        let written = try writePhoto(
            jpeg,
            to: targets,
            createdIdentifier: resolution.createdFromRecents ? existing.identifier : nil,
            reason: reason
        )
        let failed = verifyPhotos(written, unifiedIdentifiers: [existing.identifier], phones: phones, jpeg: jpeg, reason: reason)
        return ApplyResult(
            count: written.count,
            createdFromRecentsName: resolution.createdFromRecents ? existingName : nil,
            unverifiedCount: failed
        )
    }

    /// Sets `jpeg` on every target card in one save; a card created this run with the photo already in its add request
    /// is not rewritten but is recorded as photo-less for restore. Returns the identifiers that should now carry the photo.
    private static func writePhoto(
        _ jpeg: Data,
        to targets: [CNContact],
        createdIdentifier: String?,
        reason: String
    ) throws -> [String] {
        let save = CNSaveRequest()
        var pending = 0
        var restoreEntries: [AlbumArtContactRestoreEntry] = []
        for card in targets {
            let isCreated = card.identifier == createdIdentifier
            let had = !isCreated && card.imageDataAvailable && card.imageData != nil
            restoreEntries.append(
                AlbumArtContactRestoreEntry(
                    identifier: card.identifier,
                    previousImageData: had ? card.imageData : nil,
                    hadImage: had,
                    createdForShow: false
                )
            )
            if isCreated, card.imageDataAvailable, card.imageData != nil { continue }
            let mutable = card.mutableCopy() as! CNMutableContact
            mutable.imageData = jpeg
            save.update(mutable)
            pending += 1
        }
        if pending > 0 {
            try executeLogged(save, reason: reason)
        }
        AlbumArtContactRestoreStore.replaceEntries(restoreEntries)
        return targets.map(\.identifier)
    }

    /// Non-unified cards behind `unified` plus every card carrying one of `phones`: Phone → Recents matches one linked
    /// card for its avatar, but (i) Info opens the unified card, which can show another linked card's (empty) photo.
    private static func linkedRawCards(of unified: [CNContact], phones: [String]) -> [CNContact] {
        var seen = Set<String>()
        var out: [CNContact] = []
        func add(_ cards: [CNContact]) {
            for card in cards where seen.insert(card.identifier).inserted { out.append(card) }
        }
        add(rawCards(matching: CNContact.predicateForContacts(withIdentifiers: unified.map(\.identifier)), in: store))
        for digits in phones {
            add(rawCards(withCanonicalDigits: digits, in: store))
        }
        return out
    }

    private static func rawCards(withCanonicalDigits digits: String, in store: CNContactStore) -> [CNContact] {
        var candidates = ["+\(digits)", WordApiSettings.nationalNumber(fromCanonical: digits)]
        if digits.count > 9 { candidates.append(String(digits.suffix(9))) }
        var seen = Set<String>()
        var out: [CNContact] = []
        for candidate in Set(candidates) where candidate.filter(\.isNumber).count >= 7 {
            let predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: candidate))
            for card in rawCards(matching: predicate, in: store)
            where seen.insert(card.identifier).inserted
                && card.phoneNumbers.contains(where: { WordApiContactPhoneParsing.number($0.value.stringValue, matchesCanonical: digits) }) {
                out.append(card)
            }
        }
        return out
    }

    private static func rawCards(
        matching predicate: NSPredicate,
        keys: [CNKeyDescriptor] = rawCardKeys,
        in store: CNContactStore
    ) -> [CNContact] {
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.predicate = predicate
        request.unifyResults = false
        var out: [CNContact] = []
        do {
            try store.enumerateContacts(with: request) { contact, _ in out.append(contact) }
        } catch {
            albumArtLog("raw fetch · \(SpectatorContactFetch.errorLogLabel(error))")
        }
        return out
    }

    /// Re-reads each saved card from a fresh store and logs what iOS kept; rewrites missing photos once.
    /// Returns how many cards still lack a full-size photo.
    private static func verifyPhotos(
        _ identifiers: [String],
        unifiedIdentifiers: [String],
        phones: [String],
        jpeg: Data,
        reason: String
    ) -> Int {
        var failed = verifyPass(identifiers, unifiedIdentifiers: unifiedIdentifiers, phones: phones)
        guard !failed.isEmpty else { return 0 }
        albumArtLog("verify · retry \(failed.count) card(s) without photo")
        let stale = rawCards(matching: CNContact.predicateForContacts(withIdentifiers: failed), in: store)
        let retry = stale.isEmpty
            ? ((try? store.unifiedContacts(matching: CNContact.predicateForContacts(withIdentifiers: failed), keysToFetch: rawCardKeys)) ?? [])
            : stale
        if !retry.isEmpty {
            let save = CNSaveRequest()
            for card in retry {
                let mutable = card.mutableCopy() as! CNMutableContact
                mutable.imageData = jpeg
                save.update(mutable)
            }
            try? executeLogged(save, reason: "\(reason)-retry")
        }
        failed = verifyPass(identifiers, unifiedIdentifiers: unifiedIdentifiers, phones: phones)
        if !failed.isEmpty {
            albumArtLog("verify · FAILED · \(failed.count) card(s) still without photo after retry")
        }
        return failed.count
    }

    private static func verifyPass(_ identifiers: [String], unifiedIdentifiers: [String], phones: [String]) -> [String] {
        let fresh = CNContactStore()
        let keys = imageKeys + [CNContactThumbnailImageDataKey as CNKeyDescriptor]
        let defaultContainer = fresh.defaultContainerIdentifier()
        var failed: [String] = []
        for id in identifiers {
            let card = rawCards(matching: CNContact.predicateForContacts(withIdentifiers: [id]), keys: keys, in: fresh).first
                ?? (try? SpectatorContactFetch.unifiedContact(store: fresh, identifier: id, keysToFetch: keys))
            guard let card else {
                albumArtLog("verify · id=\(WordApiInputPanel.truncated(id, max: 16)) · not found on re-fetch")
                failed.append(id)
                continue
            }
            let container = containerLabel(forContact: id, defaultIdentifier: defaultContainer, in: fresh)
            albumArtLog("verify · id=\(WordApiInputPanel.truncated(id, max: 16)) · container=\(container) · \(photoLabel(card))")
            if !card.imageDataAvailable || (card.imageData?.isEmpty ?? true) { failed.append(id) }
        }
        for id in unifiedIdentifiers {
            guard let unified = try? SpectatorContactFetch.unifiedContact(store: fresh, identifier: id, keysToFetch: keys) else { continue }
            var phoneCounts: [String] = []
            for digits in phones {
                let raw = rawCards(withCanonicalDigits: digits, in: fresh).count
                let predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: "+\(digits)"))
                let unifiedCount = (try? fresh.unifiedContacts(matching: predicate, keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor]).count) ?? 0
                phoneCounts.append("+\(digits) raw=\(raw) unified=\(unifiedCount)")
            }
            albumArtLog(
                "verify unified · id=\(WordApiInputPanel.truncated(id, max: 16)) · \(photoLabel(unified)) · linked=\(identifiers.count) · \(phoneCounts.joined(separator: " · "))"
            )
        }
        return failed
    }

    private static func photoLabel(_ card: CNContact) -> String {
        let thumb = card.isKeyAvailable(CNContactThumbnailImageDataKey) ? (card.thumbnailImageData?.count ?? 0) : -1
        let full = card.imageData?.count ?? 0
        let px = card.imageData.flatMap(UIImage.init(data:)).map { " · \(Int($0.size.width * $0.scale))x\(Int($0.size.height * $0.scale))px" } ?? ""
        return "imageDataAvailable=\(card.imageDataAvailable) thumb=\(thumb)B full=\(full)B\(px)"
    }

    private static func containerLabel(forContact identifier: String, defaultIdentifier: String, in store: CNContactStore) -> String {
        let predicate = CNContainer.predicateForContainerOfContact(withIdentifier: identifier)
        guard let container = (try? store.containers(matching: predicate))?.first else { return "unknown" }
        let type: String
        switch container.type {
        case .local: type = "local"
        case .exchange: type = "exchange"
        case .cardDAV: type = "cardDAV"
        case .unassigned: type = "unassigned"
        @unknown default: type = "other"
        }
        let isDefault = container.identifier == defaultIdentifier ? " default" : ""
        return "\(WordApiInputPanel.truncated(container.identifier, max: 12)) \(type)\(isDefault)"
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
        let matches = try cards(withPhone: phone, keysToFetch: rawCardKeys)
        let digits = WordApiContactPhoneParsing.canonicalDigits(fromContactNumber: phone)
        let phones = digits.count >= 7 ? [digits] : []

        if matches.isEmpty {
            let contact = CNMutableContact()
            contact.givenName = "MindtoneX"
            contact.phoneNumbers = [
                CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: phone)),
            ]
            contact.imageData = jpeg
            let save = CNSaveRequest()
            save.add(contact, toContainerWithIdentifier: store.defaultContainerIdentifier())
            try executeLogged(save, reason: reason)
            AlbumArtContactRestoreStore.replaceEntries([
                AlbumArtContactRestoreEntry(
                    identifier: contact.identifier,
                    previousImageData: nil,
                    hadImage: false,
                    createdForShow: true
                ),
            ])
            _ = verifyPhotos([contact.identifier], unifiedIdentifiers: [contact.identifier], phones: phones, jpeg: jpeg, reason: reason)
            return 1
        }

        let linked = linkedRawCards(of: matches, phones: phones)
        let written = try writePhoto(jpeg, to: linked.isEmpty ? matches : linked, createdIdentifier: nil, reason: reason)
        _ = verifyPhotos(written, unifiedIdentifiers: matches.map(\.identifier), phones: phones, jpeg: jpeg, reason: reason)
        return written.count
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
        let raw = rawCards(matching: CNContact.predicateForContacts(withIdentifiers: [entry.identifier]), keys: keys, in: store).first
        let contact = try raw ?? SpectatorContactFetch.unifiedContact(
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
