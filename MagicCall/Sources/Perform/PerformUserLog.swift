import Foundation

/// User-facing Perform history for the home screen (plain English, magician-friendly).
@MainActor
final class PerformUserLog: ObservableObject {
    static let shared = PerformUserLog()

    private enum Keys {
        static let sessions = "performUserLog.sessions.v1"
    }

    static let maxSessions = 15

    struct Entry: Identifiable, Codable, Equatable {
        let id: UUID
        let at: Date
        let message: String

        init(at: Date = Date(), message: String) {
            id = UUID()
            self.at = at
            self.message = message
        }
    }

    struct Session: Identifiable, Codable, Equatable {
        let id: UUID
        let startedAt: Date
        var endedAt: Date?
        var title: String
        var entries: [Entry]

        init(startedAt: Date = Date(), title: String) {
            id = UUID()
            self.startedAt = startedAt
            endedAt = nil
            self.title = title
            entries = []
        }
    }

    @Published private(set) var sessions: [Session] = []
    private var activeSessionID: UUID?
    private var lastConnectionWarningAt: Date?
    private var oncePerSessionKeys: Set<String> = []

    private init() {
        reloadFromDisk()
    }

    var activeSession: Session? {
        guard let id = activeSessionID else { return nil }
        return sessions.first { $0.id == id }
    }

    func beginSession(inputLabel: String) {
        lastConnectionWarningAt = nil
        oncePerSessionKeys = []
        if activeSessionID != nil { endSession(reason: "New perform") }
        var session = Session(title: inputLabel)
        session.entries.append(Entry(message: "Perform started · \(inputLabel) · log shows inputs + recognized values"))
        sessions.insert(session, at: 0)
        activeSessionID = session.id
        trimAndPersist()
    }

    func endSession(reason: String = "Perform ended") {
        guard let id = activeSessionID, let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].entries.append(Entry(message: reason))
        sessions[index].endedAt = Date()
        activeSessionID = nil
        trimAndPersist()
    }

    func log(_ message: String) {
        guard let id = activeSessionID, let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].entries.append(Entry(message: message))
        trimAndPersist()
    }

    /// Throttle repeated API/voice connection warnings during one session.
    func logConnectionIssue(_ message: String, minGap: TimeInterval = 12) {
        let now = Date()
        if let last = lastConnectionWarningAt, now.timeIntervalSince(last) < minGap { return }
        lastConnectionWarningAt = now
        log(message)
    }

    /// Log at most once per active Perform session (e.g. App Group / Call Directory hints).
    func logOncePerSession(_ key: String, _ message: String) {
        guard !oncePerSessionKeys.contains(key) else { return }
        oncePerSessionKeys.insert(key)
        log(message)
    }

    func clearAll() {
        sessions = []
        activeSessionID = nil
        persist()
    }

    private func trimAndPersist() {
        if sessions.count > Self.maxSessions {
            sessions = Array(sessions.prefix(Self.maxSessions))
        }
        if let active = activeSessionID, !sessions.contains(where: { $0.id == active }) {
            activeSessionID = nil
        }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        UserDefaults.standard.set(data, forKey: Keys.sessions)
    }

    private func reloadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: Keys.sessions),
              let decoded = try? JSONDecoder().decode([Session].self, from: data) else { return }
        sessions = decoded
        activeSessionID = decoded.first(where: { $0.endedAt == nil })?.id
    }
}
