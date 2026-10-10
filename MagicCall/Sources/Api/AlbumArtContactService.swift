import Contacts
import Foundation
import Photos
import QuartzCore
import UIKit

/// Album artwork on song lock — contact photo and/or Photo Library (shared download + crop).
enum AlbumArtContactService {
    private static let store = CNContactStore()
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        return URLSession(configuration: config)
    }()

    // MARK: - Perform session

    private struct PerformLock {
        let track: PreviewTrack
        let reason: String
        let lockedAt: CFTimeInterval
    }

    @MainActor private static var performGeneration = 0
    @MainActor private static var performTrackID: String?
    @MainActor private static var performLockedAt: CFTimeInterval?
    @MainActor private static var performSavedAt: CFTimeInterval?
    @MainActor private static var performRingAt: CFTimeInterval?
    /// Unknown lock that arrived before the dialed number was saved; applied by `spectatorNumberSaved()`.
    @MainActor private static var pendingUnknownLock: PerformLock?
    @MainActor private static var spectatorNumberSavedAt: CFTimeInterval?

    @MainActor
    static func performStarted() {
        performGeneration += 1
        performTrackID = nil
        performLockedAt = nil
        performSavedAt = nil
        performRingAt = nil
        pendingUnknownLock = nil
    }

    /// Perform disarm: a download still running is cancelled; a save already on the Contacts queue restores itself.
    @MainActor
    static func performEnded(reason: String) {
        if AlbumArtContactSettings.enabled, performLockedAt != nil, performSavedAt == nil {
            albumArtLog("perform end · \(reason) · apply still in flight → cancelled")
        }
        performStarted()
        AppModel.shared.cancelAlbumArtContactWork()
    }

    /// Unknown: the Perform dial saved the spectator number.
    @MainActor
    static func spectatorNumberSaved() {
        spectatorNumberSavedAt = CACurrentMediaTime()
        guard let pending = pendingUnknownLock else { return }
        pendingUnknownLock = nil
        guard AppModel.shared.isArmed else { return }
        albumArtLog("perform order · number saved \(ms(since: pending.lockedAt))ms after lock → applying now")
        startPerformApply(pending)
    }

    /// Every Perform song-lock input (Voice, Notes, API, Camera, Manual at arm) lands here; in 2-song mode only song 1
    /// (the Home slot the call plays first) reaches this.
    @MainActor
    static func processOnSongLock(track: PreviewTrack, reason: String) {
        guard AlbumArtContactSettings.anyOutputEnabled else { return }
        let label = WordApiInputPanel.truncated("\(track.title) — \(track.artist)", max: 40)
        guard track.artworkURL != nil else {
            albumArtLog("perform skip · \(reason) · no artwork URL · «\(label)»")
            return
        }
        if performTrackID == track.id {
            albumArtLog("perform skip · \(reason) · «\(label)» already applied this Perform")
            return
        }
        let lock = PerformLock(track: track, reason: reason, lockedAt: CACurrentMediaTime())
        performTrackID = track.id
        performLockedAt = lock.lockedAt
        performSavedAt = nil
        let outputs = "contact=\(AlbumArtContactSettings.enabled ? "on" : "off") photos=\(AlbumArtContactSettings.saveToPhotosEnabled ? "on" : "off")"
        albumArtLog("perform lock · «\(label)» · via \(reason) · \(performTargetLabel()) · \(outputs)")
        if AlbumArtContactSettings.enabled, WordApiSettings.contactMode == .unknown {
            guard WordApiSettings.spectatorContactPhoneE164String() != nil else {
                pendingUnknownLock = lock
                albumArtLog("perform wait · Unknown has no dialed number yet → applies once the dial saves it")
                return
            }
            if let savedAt = spectatorNumberSavedAt {
                albumArtLog("perform order · dial saved \(ms(since: savedAt))ms before lock ✓")
            }
        }
        startPerformApply(lock)
    }

    /// Incoming call while armed: did the photo land before iOS read the card for this ring?
    @MainActor
    static func notePerformIncomingCall(source: String) {
        guard AlbumArtContactSettings.enabled else { return }
        let now = CACurrentMediaTime()
        if let ringAt = performRingAt, now - ringAt < 5 { return }
        performRingAt = now
        if let savedAt = performSavedAt {
            albumArtLog("perform call · \(source) · art saved \(ms(from: savedAt, to: now))ms before ring ✓")
        } else if let lockedAt = performLockedAt {
            albumArtLog("perform call · \(source) · ⚠ ring before art saved (lock \(ms(from: lockedAt, to: now))ms ago) → this ring may show the old photo")
        } else if pendingUnknownLock != nil {
            albumArtLog("perform call · \(source) · ⚠ ring while waiting for the dialed number → no art on this ring")
        } else {
            albumArtLog("perform call · \(source) · no song locked yet → no art on this ring")
        }
    }

    @MainActor
    private static func performTargetLabel() -> String {
        switch WordApiSettings.contactMode {
        case .known:
            guard WordApiSettings.hasKnownContactSelected else { return "Known · no contact picked" }
            let phone = WordApiSettings.knownContactPhoneDigits
            return "Known «\(WordApiInputPanel.truncated(WordApiSettings.knownContactDisplayName, max: 24))» · phone=\(phone.isEmpty ? "none" : "+\(phone)")"
        case .unknown:
            let digits = WordApiSettings.spectatorContactPhoneDigitsRaw()
            return digits.isEmpty ? "Unknown · no number" : "Unknown +\(digits)"
        }
    }

    @MainActor
    private static func startPerformApply(_ lock: PerformLock) {
        let generation = performGeneration
        AppModel.shared.runAlbumArtContactWork {
            await processPerformArtwork(lock, generation: generation)
        }
    }

    private static func ms(since start: CFTimeInterval) -> Int {
        ms(from: start, to: CACurrentMediaTime())
    }

    private static func ms(from start: CFTimeInterval, to end: CFTimeInterval) -> Int {
        Int(((end - start) * 1000).rounded())
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

    /// Reverts every card album art touched during Perform to its first recorded photo. Cards created from a Recents
    /// pick stay (photo cleared); only Unknown show-only cards are deleted. Runs as one block on the Contacts queue so
    /// a newer apply cannot interleave or have its snapshots wiped.
    @MainActor
    static func restoreContactsAfterPerform(reason: String) {
        guard !AppModel.shared.isArmed else { return }
        let snapshots = AlbumArtContactRestoreStore.entries
        guard !snapshots.isEmpty else { return }
        AlbumArtContactRestoreStore.clear()

        guard WordApiSettings.restoreKnownNameOnSettingsExit else {
            albumArtLog("perform restore off · \(snapshots.count) card(s) keep album art (\(reason))")
            return
        }
        let canWrite: Bool
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited: canWrite = true
        default: canWrite = false
        }
        guard canWrite else {
            albumArtLog("perform restore skipped · Contacts \(contactsAuthorizationLabel()) (\(reason))")
            return
        }
        SpectatorContactFetch.workQueue.async {
            var restored = 0
            var deleted = 0
            var failed = 0
            for entry in snapshots {
                do {
                    if entry.createdForShow {
                        try deleteContact(identifier: entry.identifier)
                        deleted += 1
                    } else {
                        try restoreImage(entry)
                        restored += 1
                    }
                } catch {
                    failed += 1
                    albumArtLog("perform restore · id=\(WordApiInputPanel.truncated(entry.identifier, max: 16)) failed · \(SpectatorContactFetch.errorLogLabel(error))")
                }
            }
            albumArtLog("perform restore · \(reason) · \(restored) photo(s) restored · \(deleted) show card(s) deleted · \(failed) failed")
            guard restored + deleted > 0 else { return }
            DispatchQueue.main.async {
                PerformUserLog.shared.log("Album art restored · \(restored + deleted) contact photo(s)")
            }
        }
    }

    // MARK: - Private

    /// Contact photo first (the incoming call reads it), then Photos.
    @MainActor
    private static func processPerformArtwork(_ lock: PerformLock, generation: Int) async {
        let jpeg: Data
        do {
            jpeg = try await fetchSquareJPEG(for: lock.track, reason: lock.reason)
        } catch let err as URLError where err.code == .cancelled {
            albumArtLog("perform abort · download cancelled (newer lock or Perform ended)")
            return
        } catch is CancellationError {
            albumArtLog("perform abort · download cancelled (newer lock or Perform ended)")
            return
        } catch let err as AlbumArtContactError {
            albumArtLog("perform failed · \(err.userMessage)")
            PerformUserLog.shared.log("Album art · \(err.userMessage)")
            allowRetry(lock, generation: generation)
            return
        } catch {
            let msg = SpectatorContactFetch.userFacingMessage(for: error)
            albumArtLog("perform failed · download · \(msg)")
            PerformUserLog.shared.log("Album art download failed · \(msg)")
            allowRetry(lock, generation: generation)
            return
        }
        guard !Task.isCancelled, generation == performGeneration else {
            albumArtLog("perform abort · superseded before save")
            return
        }
        if AlbumArtContactSettings.enabled {
            await applyPerformContactArtwork(jpeg: jpeg, lock: lock, generation: generation)
        }
        if AlbumArtContactSettings.saveToPhotosEnabled {
            await saveToPhotoLibrary(jpeg: jpeg, trackLabel: "\(lock.track.title) — \(lock.track.artist)", reason: lock.reason)
        }
    }

    /// A failed apply must not block the same song locking again in this Perform.
    @MainActor
    private static func allowRetry(_ lock: PerformLock, generation: Int) {
        guard generation == performGeneration, performTrackID == lock.track.id else { return }
        performTrackID = nil
        performLockedAt = nil
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
            case .noContactTarget: return "No contact selected."
            }
        }
    }

    /// 1000px artwork → center-cropped square JPEG.
    private static func fetchSquareJPEG(for track: PreviewTrack, reason: String) async throws -> Data {
        guard let url = track.artworkURL else { throw AlbumArtContactError.noArtworkURL }
        let fetchURL = upgradedArtworkURL(url)
        let t0 = CACurrentMediaTime()
        let (data, _) = try await session.data(from: fetchURL)
        stepLog(reason, "download · \(data.count) bytes · \(ms(since: t0))ms")
        guard let image = UIImage(data: data) else { throw AlbumArtContactError.invalidImageData }
        guard let (jpeg, sidePx) = centerCroppedSquareJPEGWithSide(image) else {
            throw AlbumArtContactError.cropFailed
        }
        stepLog(reason, "crop · \(jpeg.count) bytes JPEG · \(sidePx)px")
        return jpeg
    }

    /// Known: resolve → linked cards → verify. Unknown: cards carrying the dialed number.
    @MainActor
    private static func applyPerformContactArtwork(jpeg: Data, lock: PerformLock, generation: Int) async {
        let reason = lock.reason
        guard await ensureContactsAccess(reason: reason) else {
            albumArtLog("perform failed · Contacts access \(contactsAuthorizationLabel())")
            return
        }
        let trackLabel = "\(lock.track.title) — \(lock.track.artist)"
        do {
            let applied: ApplyResult
            if WordApiSettings.contactMode == .known, let id = WordApiSettings.knownContactIdentifier {
                let displayName = WordApiSettings.knownContactDisplayName
                let fallbackPhones = storedPhoneFallbacks(identifier: id, displayName: displayName)
                let phoneDigits = healedPhoneDigits(WordApiSettings.knownContactPhoneDigits, identifier: id, fallbacks: fallbackPhones, reason: reason)
                applied = try await SpectatorContactFetch.run {
                    try applyImageData(
                        jpeg,
                        contactIdentifier: id,
                        phoneDigits: phoneDigits,
                        displayName: displayName,
                        fallbackPhoneDigits: fallbackPhones,
                        reason: reason
                    )
                }
                if let created = applied.createdFromRecentsName {
                    PerformUserLog.shared.log(SpectatorContactFetch.RecentsNotice.message(name: created))
                }
            } else if let phone = WordApiSettings.spectatorContactPhoneE164String() {
                applied = try await SpectatorContactFetch.run { try applyImageData(jpeg, phone: phone, reason: reason) }
            } else {
                albumArtLog("perform skip · no spectator phone — dial (Unknown) or pick a contact (Known)")
                PerformUserLog.shared.log("Album art · no phone yet · dial or choose contact on Album art card")
                return
            }
            let savedAt = CACurrentMediaTime()
            let current = generation == performGeneration
            if current { performSavedAt = savedAt }
            let check = applied.unverifiedCount > 0 ? "⚠ \(applied.unverifiedCount) unverified" : "verified"
            let lateNote = current && performRingAt.map { $0 < savedAt } == true ? " · ⚠ after ring started" : ""
            albumArtLog("perform apply · lock→saved \(ms(from: lock.lockedAt, to: savedAt))ms · \(applied.count) card(s) · \(check)\(lateNote)")
            PerformUserLog.shared.log("Album art on contact · \(applied.count) card(s) · «\(WordApiInputPanel.truncated(trackLabel, max: 36))»")
            if !AppModel.shared.isArmed {
                albumArtLog("perform end · saved after disarm → restoring now")
                restoreContactsAfterPerform(reason: "save finished after disarm")
            }
        } catch {
            allowRetry(lock, generation: generation)
            albumArtLog("perform failed · save · \(SpectatorContactFetch.errorLogLabel(error)) · auth=\(contactsAuthorizationLabel())")
            PerformUserLog.shared.log("Album art on contact failed · \(SpectatorContactFetch.saveFailureMessage(for: error))")
        }
    }

    /// Perform steps carry the `perform` prefix so one show reads as one block in the log.
    private static func stepLog(_ reason: String, _ message: String) {
        albumArtLog("perform \(message)")
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

    /// Known contact phone saved for this same card (matched by id or display name).
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
        return phones.filter { $0.count >= 7 }
    }

    /// Picks made before phones were persisted have an empty phone; reuse the matching Known phone and save it
    /// on the stored pick so later launches start with it.
    @MainActor
    private static func healedPhoneDigits(_ phoneDigits: String, identifier: String, fallbacks: [String], reason: String) -> String {
        guard phoneDigits.count < 7, let healed = fallbacks.first else { return phoneDigits }
        if WordApiSettings.knownContactIdentifier == identifier, WordApiSettings.knownContactPhoneDigits.count < 7 {
            WordApiSettings.updateKnownContactPhoneDigits(healed)
        }
        stepLog(reason, "phone healed from stored pick · +\(healed)")
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
            log: { stepLog(reason, "resolve · \($0)") }
        )
        let existing = resolution.contact
        let existingName = SpectatorContactFetch.displayName(of: existing)
        let resolvedLabel = "«\(WordApiInputPanel.truncated(existingName, max: 24))» · id=\(WordApiInputPanel.truncated(existing.identifier, max: 16))"
        if resolution.createdFromRecents {
            stepLog(reason, "created real card from Recents · «\(existingName)» · +\(resolution.matchedPhoneDigits)")
        } else if resolution.resolvedByPhone {
            stepLog(
                reason,
                "re-resolved by phone · +\(resolution.matchedPhoneDigits) · \(resolution.phoneMatchCount) match(es) · \(resolvedLabel)"
            )
        } else if resolution.resolvedByName {
            stepLog(reason, "re-resolved by name · \(resolvedLabel)")
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
        stepLog(reason, "targets · \(targets.count) raw card(s) for unified id=\(WordApiInputPanel.truncated(existing.identifier, max: 16)) · phones=\(phones.map { "+\($0)" }.joined(separator: ","))")
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
        AlbumArtContactRestoreStore.mergeEntries(restoreEntries)
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
        var failed = verifyPass(identifiers, unifiedIdentifiers: unifiedIdentifiers, phones: phones, reason: reason)
        guard !failed.isEmpty else { return 0 }
        stepLog(reason, "verify · retry \(failed.count) card(s) without photo")
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
        failed = verifyPass(identifiers, unifiedIdentifiers: unifiedIdentifiers, phones: phones, reason: reason)
        if !failed.isEmpty {
            stepLog(reason, "verify · FAILED · \(failed.count) card(s) still without photo after retry")
        }
        return failed.count
    }

    private static func verifyPass(_ identifiers: [String], unifiedIdentifiers: [String], phones: [String], reason: String) -> [String] {
        let concise = true
        let fresh = CNContactStore()
        let keys = imageKeys + [CNContactThumbnailImageDataKey as CNKeyDescriptor]
        let defaultContainer = fresh.defaultContainerIdentifier()
        var failed: [String] = []
        var unifiedMarks: [String] = []
        func hasPhoto(_ card: CNContact) -> Bool { card.imageDataAvailable && !(card.imageData?.isEmpty ?? true) }
        for id in identifiers {
            let card = rawCards(matching: CNContact.predicateForContacts(withIdentifiers: [id]), keys: keys, in: fresh).first
                ?? (try? SpectatorContactFetch.unifiedContact(store: fresh, identifier: id, keysToFetch: keys))
            guard let card else {
                stepLog(reason, "verify · id=\(WordApiInputPanel.truncated(id, max: 16)) · not found on re-fetch")
                failed.append(id)
                continue
            }
            if !hasPhoto(card) { failed.append(id) }
            guard !concise else { continue }
            let container = containerLabel(forContact: id, defaultIdentifier: defaultContainer, in: fresh)
            albumArtLog("verify · id=\(WordApiInputPanel.truncated(id, max: 16)) · container=\(container) · \(photoLabel(card))")
        }
        for id in unifiedIdentifiers {
            guard let unified = try? SpectatorContactFetch.unifiedContact(store: fresh, identifier: id, keysToFetch: keys) else { continue }
            if concise {
                unifiedMarks.append(hasPhoto(unified) ? "✓" : "✗")
                continue
            }
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
        if concise {
            let ok = identifiers.count - failed.count
            stepLog(reason, "verify · \(ok)/\(identifiers.count) card(s) with photo · unified photo=\(unifiedMarks.isEmpty ? "?" : unifiedMarks.joined(separator: ","))")
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
            stepLog(reason, "CNSaveRequest failed (\(reason)) · \(SpectatorContactFetch.errorLogLabel(error))")
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
    }

    /// Unknown (dialed number) or Known without a stored id. Runs on `SpectatorContactFetch.workQueue`, the same serial
    /// queue as the caller-name upsert, so whichever runs second sees the other's card instead of adding a duplicate.
    private static func applyImageData(_ jpeg: Data, phone: String, reason: String) throws -> ApplyResult {
        let matches = try cards(withPhone: phone, keysToFetch: rawCardKeys)
        let digits = WordApiContactPhoneParsing.canonicalDigits(fromContactNumber: phone)
        let phones = digits.count >= 7 ? [digits] : []
        let linked = linkedRawCards(of: matches, phones: phones)
        let targets = linked.isEmpty ? matches : linked

        if targets.isEmpty {
            let contact = CNMutableContact()
            contact.givenName = "MindtoneX"
            contact.phoneNumbers = [
                CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: phone)),
            ]
            contact.imageData = jpeg
            let save = CNSaveRequest()
            save.add(contact, toContainerWithIdentifier: store.defaultContainerIdentifier())
            try executeLogged(save, reason: reason)
            stepLog(reason, "card · none had \(phone) → created show card id=\(WordApiInputPanel.truncated(contact.identifier, max: 16))")
            AlbumArtContactRestoreStore.mergeEntries([
                AlbumArtContactRestoreEntry(
                    identifier: contact.identifier,
                    previousImageData: nil,
                    hadImage: false,
                    createdForShow: true
                ),
            ])
            let failed = verifyPhotos([contact.identifier], unifiedIdentifiers: [contact.identifier], phones: phones, jpeg: jpeg, reason: reason)
            return ApplyResult(count: 1, createdFromRecentsName: nil, unverifiedCount: failed)
        }

        stepLog(reason, "card · \(targets.count) raw card(s) already carry \(phone) (\(matches.count) unified)")
        let written = try writePhoto(jpeg, to: targets, createdIdentifier: nil, reason: reason)
        let failed = verifyPhotos(written, unifiedIdentifiers: matches.map(\.identifier), phones: phones, jpeg: jpeg, reason: reason)
        return ApplyResult(count: written.count, createdFromRecentsName: nil, unverifiedCount: failed)
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
        PerformUserLog.shared.logConnectionIssue(
            "Album art on contact needs Contacts access — enable in Settings to show song artwork on the incoming call."
        )
    }
}
