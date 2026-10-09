import SwiftUI

/// API song input on home: inline connection + live watch test (Oracle styling).
struct ApiInputPanel: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var session = ApiSongSession.shared
    @AppStorage(ApiSettings.Key.provider) private var providerRaw = ApiSettings.Provider.inject.rawValue
    @AppStorage(ApiSettings.Key.injectID) private var injectID = ""

    @State private var showConnectionSheet = false

    private var provider: ApiSettings.Provider { ApiSettings.Provider(rawValue: providerRaw) ?? .inject }
    private var configured: Bool { ApiSettings.isConfigured }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            connectionBlock
            watchTestBlock
            if let line = statusLine {
                Label(line.text, systemImage: line.icon)
                    .font(.caption)
                    .foregroundStyle(line.warning ? OracleTheme.coral : OracleTheme.textSecondary)
                    .lineLimit(3)
            }
            lockedSongRow
        }
        .sheet(isPresented: $showConnectionSheet) {
            ApiSettingsSheet()
        }
    }

    // MARK: Connection

    private var connectionBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            OracleEyebrow(text: "Spectator search API")

            VStack(alignment: .leading, spacing: 12) {
                Picker("Integration", selection: $providerRaw) {
                    ForEach(ApiSettings.Provider.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)

                if provider == .inject {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Inject ID")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(OracleTheme.textSecondary)
                        TextField("Paste Inject API token", text: $injectID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.subheadline)
                            .padding(10)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: configured ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(configured ? OracleTheme.gold : OracleTheme.coral)
                        Text(configured ? "\(provider.title) connected" : ApiSettings.setupHint)
                            .font(.caption)
                            .foregroundStyle(configured ? OracleTheme.textSecondary : OracleTheme.coral)
                    }
                }

                Button {
                    showConnectionSheet = true
                } label: {
                    HStack {
                        Label(
                            provider == .inject && !injectID.isEmpty ? "Full setup & test connection" : "Enter connection details",
                            systemImage: "link.circle.fill"
                        )
                        .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(OracleTheme.gold)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)

                Text("On Perform, polls every \(Int(ApiSettings.pollInterval)) s — first reading is the old search, the **next change** is the spectator’s song.")
                    .font(.caption2)
                    .foregroundStyle(OracleTheme.textSecondary)
            }
            .padding(14)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
            }
        }
    }

    // MARK: Watch test

    private var watchTestBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            OracleEyebrow(text: "Live watch")
            Text("Simulate Perform polling: search a song in \(provider.title), then see when the app picks it up.")
                .font(.caption)
                .foregroundStyle(OracleTheme.textSecondary)

            if session.isActive && session.context == .test {
                Button { session.stopTest() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "stop.circle.fill")
                            .font(.title3)
                        Text("Stop watching")
                            .font(.subheadline.weight(.bold))
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.red.opacity(0.88)))
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    model.clearSongForNextPerformance()
                    session.start(context: .test)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.title3)
                        Text("Watch test")
                            .font(.subheadline.weight(.bold))
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: configured
                                        ? [OracleTheme.indigo, OracleTheme.indigo.opacity(0.72)]
                                        : [Color.gray.opacity(0.35), Color.gray.opacity(0.25)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
                .buttonStyle(.plain)
                .disabled(!configured)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var lockedSongRow: some View {
        if session.state == .locked, let track = model.selected, model.loadState == .ready {
            LoadedSongReadyRow(track: track, leadingSystemImage: "lock.fill")
        }
    }

    private var statusLine: (text: String, icon: String, warning: Bool)? {
        if session.isStruggling, session.isActive {
            return ("\(provider.title) not reachable: \(session.lastError ?? "network error") — retrying", "wifi.exclamationmark", true)
        }
        switch session.state {
        case .idle:
            if let last = session.lastReading, last.hasSong { return ("Last value: “\(last.label)”", "text.quote", false) }
            return configured ? ("Tap **Watch test**, then search a song in \(provider.title).", "info.circle", false) : nil
        case .connecting:
            return ("Connecting to \(provider.title)…", "antenna.radiowaves.left.and.right", false)
        case .watching:
            if let missed = session.notFound {
                return ("No preview found for “\(missed)” — waiting for another search", "exclamationmark.magnifyingglass", true)
            }
            var current = ""
            if let now = session.lastReading ?? session.baseline, now.hasSong { current = " · now “\(now.label)”" }
            return ("Waiting for a new search\(current)", "dot.radiowaves.left.and.right", false)
        case .loading(let label):
            return ("Found “\(label)” — loading preview…", "arrow.down.circle", false)
        case .locked:
            if session.watchingSecondSong {
                return ("Song 1 locked · waiting for spectator 2’s search in \(provider.title)", "dot.radiowaves.left.and.right", false)
            }
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
                            .foregroundStyle(OracleTheme.gold)
                    }
                }
        }
        .preferredColorScheme(.dark)
    }
}
