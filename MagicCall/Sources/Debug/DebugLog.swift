import Foundation
import QuartzCore
import UIKit

func dlog(_ message: String, sync: Bool = false) {
    DebugLog.shared.log(message, sync: sync)
}

final class DebugLog: ObservableObject {
    static let shared = DebugLog()

    struct Entry: Identifiable {
        let id = UUID()
        let text: String
    }

    @Published private(set) var entries: [Entry] = []

    let fileURL: URL
    private let queue = DispatchQueue(label: "magiccall.debuglog")
    private let launchTime = CACurrentMediaTime()
    private let clock: DateFormatter

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("magic-call-log.txt")
        clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.dateFormat = "HH:mm:ss.SSS"
    }

    /// `sync: true` fuerza la escritura a disco antes de volver: úsalo antes de llamadas
    /// a APIs privadas que podrían matar el proceso, para que la última línea quede guardada.
    func log(_ message: String, sync: Bool = false) {
        let uptime = String(format: "%8.3f", CACurrentMediaTime() - launchTime)
        let line = "\(clock.string(from: Date())) [\(uptime)s] \(message)"
        let url = fileURL
        let write = {
            guard let data = (line + "\n").data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
        if sync { queue.sync(execute: write) } else { queue.async(execute: write) }
        print(line)
        DispatchQueue.main.async {
            self.entries.append(Entry(text: line))
            if self.entries.count > 3000 { self.entries.removeFirst(1000) }
        }
    }

    var fullText: String {
        queue.sync { (try? String(contentsOf: fileURL, encoding: .utf8)) ?? "" }
    }

    func clear() {
        queue.sync { try? FileManager.default.removeItem(at: fileURL) }
        DispatchQueue.main.async { self.entries.removeAll() }
        logDeviceHeader()
    }

    func logDeviceHeader() {
        let device = UIDevice.current
        log("=== Ringtone Oracle \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] ?? "?")) ===")
        log("Dispositivo: \(DebugLog.hardwareModel()) · \(device.systemName) \(device.systemVersion) · región \(Locale.current.region?.identifier ?? "?")")
        #if MAGIC_PRIVATE_PROBES
        log("Compilado CON experimentos privados (MAGIC_PRIVATE_PROBES)")
        #else
        log("Compilado SIN experimentos privados")
        #endif
    }

    static func hardwareModel() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }
}
