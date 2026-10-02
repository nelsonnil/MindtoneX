import SwiftUI

/// Compact API panel under the song-input chips: active integration, live test and status.
struct ApiInputPanel: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var session = ApiSongSession.shared
    @AppStorage(ApiSettings.Key.provider) private var providerRaw = ApiSettings.Provider.inject.rawValue
    @AppStorage(ApiSettings.Key.injectID) private var injectID = ""
    @AppStorage(ApiSettings.Key.elipsURL) private var elipsURL = ""
    @AppStorage(ApiSettings.Key.customURL) private var customURL = ""
    @AppStorage(ApiSettings.Key.customField) private var customField = ApiSettings.defaultCustomField

    @State private var showSettings = false

    private var provider: ApiSettings.Provider { ApiSettings.Provider(rawValue: providerRaw) ?? .inject }
    private var configured: Bool { ApiSettings.isConfigured }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(provider.title, systemImage: "link")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(OracleTheme.indigo.opacity(0.3))
                    .clipShape(Capsule())
                Text("checks every \(Int(ApiSettings.pollInterval)) s on Perform")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.textSecondary)
                Spacer(minLength: 0)
                Button("Settings") { showSettings = true }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OracleTheme.gold)
            }

            if !configured {
                Button { showSettings = true } label: {
                    Label(ApiSettings.setupHint, systemImage: "key.fill")
                        .font(.caption)
                        .foregroundStyle(OracleTheme.coral)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                if session.isActive && session.context == .test {
                    Button(role: .destructive) { session.stopTest() } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        model.clearSongForNextPerformance()
                        session.start(context: .test)
                    } label: {
                        Label("Watch test", systemImage: "dot.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(OracleTheme.indigo)
                    .disabled(!configured)
                }
            }

            if let line = statusLine {
                Label(line.text, systemImage: line.icon)
                    .font(.caption)
                    .foregroundStyle(line.warning ? OracleTheme.coral : OracleTheme.textSecondary)
                    .lineLimit(2)
            }

            if session.state == .locked, let track = model.selected, model.loadState == .ready {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(OracleTheme.gold)
                    Text("\(track.title) — \(track.artist)")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button { model.audition() } label: {
                        Image(systemName: model.isAudible ? "speaker.wave.2.fill" : "play.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(OracleTheme.gold)
                    .disabled(model.isAudible)
                }
                .padding(10)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .sheet(isPresented: $showSettings) { ApiSettingsSheet() }
    }

    private var statusLine: (text: String, icon: String, warning: Bool)? {
        if session.isStruggling, session.isActive {
            return ("\(provider.title) not reachable: \(session.lastError ?? "network error") — retrying", "wifi.exclamationmark", true)
        }
        switch session.state {
        case .idle:
            if let last = session.lastReading, last.hasSong { return ("Last value: “\(last.label)”", "text.quote", false) }
            return configured ? ("Test: tap Watch test, then search a song in \(provider.title).", "info.circle", false) : nil
        case .connecting:
            return ("Connecting to \(provider.title)…", "antenna.radiowaves.left.and.right", false)
        case .watching:
            if let missed = session.notFound {
                return ("No preview found for “\(missed)” — waiting for another search", "exclamationmark.magnifyingglass", true)
            }
            var current = ""
            if let base = session.baseline, base.hasSong { current = " · now “\(base.label)”" }
            return ("Waiting for a new search\(current)", "dot.radiowaves.left.and.right", false)
        case .loading(let label):
            return ("Found “\(label)” — loading preview…", "arrow.down.circle", false)
        case .locked:
            return nil
        case .failed(let message):
            return (message, "exclamationmark.triangle.fill", true)
        }
    }
}

struct ApiSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ApiSettingsView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
