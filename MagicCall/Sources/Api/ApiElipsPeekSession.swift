import Foundation
import QuartzCore
import UIKit

/// Polls the optional Elips “peek” custom API alongside `ApiSongSession` during Perform / watch test.
@MainActor
final class ApiElipsPeekSession: ObservableObject {
    static let shared = ApiElipsPeekSession()

    @Published private(set) var lastText: String?
    @Published private(set) var lastError: String?

    private var timer: Timer?
    private var isRefreshing = false
    private var generation = 0

    private init() {}

    var displayText: String? {
        let t = lastText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }

    func startIfNeeded(context: ApiSongSession.Context) {
        stop()
        guard ApiSettings.elipsPeekIsActive else { return }
        generation += 1
        lastText = nil
        lastError = nil
        dlog("[API peek] ▶︎ start (\(context == .perform ? "perform" : "test")) · \(ApiSettings.elipsPeekURL) field=\(ApiSettings.elipsPeekField)")
        let timer = Timer(timeInterval: ApiSettings.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRefreshing = false
        generation += 1
    }

    func resetStoredReading() {
        stop()
        lastText = nil
        lastError = nil
    }

    func kickPerformPollIfNeeded() {
        guard timer != nil else { return }
        tick()
    }

    private func tick() {
        guard timer != nil, !isRefreshing else { return }
        if UIApplication.shared.applicationState == .background { return }
        isRefreshing = true
        let gen = generation
        let t0 = CACurrentMediaTime()
        Task { [weak self] in
            let result: Result<String, Error>
            do {
                result = .success(try await ApiSongClient.fetchElipsPeekText())
            } catch {
                result = .failure(error)
            }
            guard let self else { return }
            self.isRefreshing = false
            guard gen == self.generation else { return }
            switch result {
            case .success(let text):
                self.lastError = nil
                if self.lastText != text {
                    self.lastText = text
                    dlog("[API peek] «\(text.prefix(48))» (\(PreviewService.ms(since: t0)) ms)")
                }
            case .failure(let error):
                self.lastError = error.localizedDescription
                dlog("✗ [API peek] \(error.localizedDescription)")
            }
        }
    }
}
