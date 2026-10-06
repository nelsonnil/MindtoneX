import SwiftUI

/// Word API on home — same integration picker pattern as API song input.
struct WordApiInputPanel: View {
    @ObservedObject private var session = WordApiSession.shared
    @AppStorage(WordApiSettings.Key.callerLabelEnabled) private var callerLabelEnabled = false
    @AppStorage(WordApiSettings.Key.provider) private var providerRaw = WordApiSettings.Provider.inject.rawValue
    @AppStorage(WordApiSettings.Key.injectID) private var injectID = ""
    @AppStorage(WordApiSettings.Key.saveWordAsContact) private var saveWordAsContact = true
    @AppStorage(WordApiSettings.Key.contactMode) private var contactModeRaw = WordApiSettings.ContactMode.unknown.rawValue
    @AppStorage(WordApiSettings.Key.restoreKnownNameOnSettingsExit) private var restoreKnownNameOnSettingsExit = true

    @State private var showConnectionSheet = false
    @State private var showHomeContactPicker = false
    @State private var showTestContactPicker = false
    @State private var testWordDraft = ""
    @State private var testContactFeedback: (ok: Bool, text: String)?
    @State private var testContactBusy = false

    private var provider: WordApiSettings.Provider { WordApiSettings.Provider(rawValue: providerRaw) ?? .inject }
    private var configured: Bool { WordApiSettings.hasWordEndpoint }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: $callerLabelEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Caller label (incoming call banner)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OracleTheme.textPrimary)
                    Text("Requires MindtoneX in iPhone Settings → Phone → Call Blocking & Identification")
                        .font(.caption2)
                        .foregroundStyle(OracleTheme.textSecondary)
                }
            }
            .tint(OracleTheme.gold)
            .onChange(of: callerLabelEnabled) { _, on in
                if !on { WordApiSession.shared.reset(reason: "caller label off") }
            }

            if callerLabelEnabled {
                wordContactCard
                connectionBlock
                contactTestModeBlock
                if let line = statusLine {
                    Label(line.text, systemImage: line.icon)
                        .font(.caption)
                        .foregroundStyle(line.warning ? OracleTheme.coral : OracleTheme.textSecondary)
                        .lineLimit(4)
                }
                if let poll = lastPollSummaryLine {
                    Text(poll)
                        .font(.caption2.monospaced())
                        .foregroundStyle(OracleTheme.textSecondary)
                        .lineLimit(2)
                }
                lockedWordRow
            }
        }
        .sheet(isPresented: $showConnectionSheet) {
            WordApiSettingsSheet()
        }
        .sheet(isPresented: $showHomeContactPicker) {
            WordApiKnownContactPicker(
                onPick: { contact in
                    showHomeContactPicker = false
                    if let e164 = WordApiContactPhoneParsing.e164(from: contact) {
                        SpectatorWordContactService.recordKnownContactPicked(contact, phoneE164: e164)
                    }
                },
                onCancel: { showHomeContactPicker = false }
            )
        }
        .sheet(isPresented: $showTestContactPicker) {
            WordApiKnownContactPicker(
                onPick: { contact in
                    showTestContactPicker = false
                    if let e164 = WordApiContactPhoneParsing.e164(from: contact) {
                        SpectatorWordContactService.recordKnownContactPicked(contact, phoneE164: e164)
                        testContactFeedback = (true, "Contacto de prueba · \(WordApiSettings.knownContactDisplayName)")
                    }
                },
                onCancel: { showTestContactPicker = false }
            )
        }
    }

    private var contactMode: WordApiSettings.ContactMode {
        WordApiSettings.ContactMode(rawValue: contactModeRaw) ?? .unknown
    }

    private var contactModeBinding: Binding<WordApiSettings.ContactMode> {
        Binding(
            get: { WordApiSettings.ContactMode(rawValue: contactModeRaw) ?? .unknown },
            set: { mode in
                contactModeRaw = mode.rawValue
                WordApiSettings.setContactMode(mode)
            }
        )
    }

    private var wordContactCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            OracleEyebrow(text: "Contact name (caller ID)")

            Text("When the spectator word locks, iOS can show that word on the incoming call screen instead of the phone number. MindtoneX writes it to Contacts (Call Directory is backup if Contacts is denied).")
                .font(.caption)
                .foregroundStyle(OracleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $saveWordAsContact) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Save locked word as contact name")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OracleTheme.textPrimary)
                    Text("Silent save at lock — no Contacts app popup during the show.")
                        .font(.caption2)
                        .foregroundStyle(OracleTheme.textSecondary)
                }
            }
            .tint(OracleTheme.gold)
            .onChange(of: saveWordAsContact) { _, on in
                WordApiSettings.setSaveWordAsContactEnabled(on)
            }

            if saveWordAsContact {
                Text("How to link the number")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OracleTheme.textPrimary)
                    .padding(.top, 2)

                WordContactModePicker(selection: contactModeBinding)

                Text(contactMode.detailLine)
                    .font(.caption2)
                    .foregroundStyle(OracleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(.easeInOut(duration: 0.2), value: contactModeRaw)

                if contactMode == .known {
                    knownContactBlock
                } else {
                    unknownContactBlock
                }
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

    private var knownContactBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            if WordApiSettings.hasKnownContactSelected {
                Label(WordApiSettings.knownContactDisplayName, systemImage: "person.crop.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OracleTheme.gold)
                Text("Phone · +\(WordApiSettings.knownContactPhoneDigits)")
                    .font(.caption.monospaced())
                    .foregroundStyle(OracleTheme.textSecondary)
            } else {
                Text("Pick the spectator contact before Perform.")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.coral)
            }

            Button {
                showHomeContactPicker = true
            } label: {
                Label(
                    WordApiSettings.hasKnownContactSelected ? "Change contact" : "Choose contact",
                    systemImage: "person.crop.circle.badge.plus"
                )
                .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(OracleTheme.gold)

            Toggle(isOn: $restoreKnownNameOnSettingsExit) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Restore original name when leaving Word API settings")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(OracleTheme.textPrimary)
                    Text("After lock, revert this contact’s given name when you close connection details (Known only).")
                        .font(.caption2)
                        .foregroundStyle(OracleTheme.textSecondary)
                }
            }
            .tint(OracleTheme.gold)
            .onChange(of: restoreKnownNameOnSettingsExit) { _, on in
                WordApiSettings.setRestoreKnownNameOnSettingsExit(on)
            }
        }
    }

    private var unknownContactBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("On Perform: dial the spectator, then arm when the outgoing call ends.")
                .font(.caption)
                .foregroundStyle(OracleTheme.textSecondary)
            if !WordApiSettings.lastDialedPhoneDigits.isEmpty {
                Text("Last dialed · +\(WordApiSettings.lastDialedPhoneDigits)")
                    .font(.caption.monospaced())
                    .foregroundStyle(OracleTheme.textSecondary)
            } else {
                Text("No number yet — Perform opens the dial sheet.")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.textSecondary)
            }
        }
    }

    private var connectionBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            OracleEyebrow(text: "Spectator word API")

            VStack(alignment: .leading, spacing: 12) {
                Picker("Integration", selection: $providerRaw) {
                    ForEach(WordApiSettings.Provider.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 8) {
                    Image(systemName: configured ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(configured ? OracleTheme.gold : OracleTheme.coral)
                    Text(configured ? "\(provider.title) active" : WordApiSettings.setupHint)
                        .font(.caption)
                        .foregroundStyle(configured ? OracleTheme.textSecondary : OracleTheme.coral)
                }

                if provider == .inject {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Inject ID")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(OracleTheme.textSecondary)
                        TextField("Paste Inject word API token", text: $injectID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.subheadline)
                            .padding(10)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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

                Text("On Perform, polls every \(Int(WordApiSettings.pollInterval)) s — first reading is the old word; the **next change** is the spectator’s word for the call banner.")
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

    private var contactTestModeBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            OracleEyebrow(text: "Modo prueba (contacto)")
            Text("Prueba renombrar un contacto **sin** Perform — útil si no eres desarrollador.")
                .font(.caption)
                .foregroundStyle(OracleTheme.textSecondary)

            TextField("Palabra de prueba", text: $testWordDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.subheadline)
                .padding(10)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(OracleTheme.textPrimary)

            if WordApiSettings.hasKnownContactSelected {
                Text("Contacto · \(WordApiSettings.knownContactDisplayName)")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.textSecondary)
            }

            HStack(spacing: 10) {
                Button {
                    showTestContactPicker = true
                } label: {
                    Label("Elegir contacto", systemImage: "person.crop.circle")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(OracleTheme.gold)

                Button {
                    Task { await runTestContactApply() }
                } label: {
                    HStack(spacing: 6) {
                        if testContactBusy { ProgressView().scaleEffect(0.85) }
                        Text("Aplicar nombre al contacto")
                            .font(.caption.weight(.semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(OracleTheme.sectionTeal)
                .disabled(testContactBusy || testWordDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if WordApiSettings.knownContactOriginalGivenName.isEmpty == false {
                Button {
                    Task { await runTestContactRestore() }
                } label: {
                    Label("Restaurar nombre original", systemImage: "arrow.uturn.backward")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(OracleTheme.textSecondary)
                .disabled(testContactBusy)
            }

            if let testContactFeedback {
                Text(testContactFeedback.text)
                    .font(.caption)
                    .foregroundStyle(testContactFeedback.ok ? OracleTheme.gold : OracleTheme.coral)
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

    private func runTestContactApply() async {
        testContactBusy = true
        defer { testContactBusy = false }
        let result = await SpectatorWordContactService.applyTestWordToKnownContact(word: testWordDraft)
        let ok = !result.contains("Error") && !result.contains("Elige") && !result.contains("Escribe") && !result.contains("Sin acceso")
        testContactFeedback = (ok, result)
        PerformUserLog.shared.log("[CONTACT] test · \(result)")
    }

    private func runTestContactRestore() async {
        testContactBusy = true
        defer { testContactBusy = false }
        let result = await SpectatorWordContactService.restoreTestKnownContact()
        let ok = !result.contains("Error") && !result.contains("No hay")
        testContactFeedback = (ok, result)
        PerformUserLog.shared.log("[CONTACT] test restore · \(result)")
    }

    @ViewBuilder
    private var lockedWordRow: some View {
        if session.state == .locked, let word = session.lockedReading?.label {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(OracleTheme.gold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Caller label locked")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(OracleTheme.textSecondary)
                    Text(word)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(OracleTheme.textPrimary)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(14)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(OracleTheme.gold.opacity(0.45), lineWidth: 1)
            }
        }
    }

    /// Last successful poll during Perform — helps spot frozen Inject counters.
    private var lastPollSummaryLine: String? {
        guard let reading = session.lastReading ?? session.baseline else { return nil }
        let count = reading.count.map(String.init) ?? "–"
        let rc = reading.receiveCount.map(String.init) ?? "–"
        let word = WordApiInputPanel.truncated(reading.label, max: 28)
        return "Last poll · count \(count) · rc \(rc) · «\(word)»"
    }

    private var statusLine: (text: String, icon: String, warning: Bool)? {
        if session.isStruggling, session.isActive {
            return ("\(provider.title) not reachable: \(session.lastError ?? "network error") — retrying", "wifi.exclamationmark", true)
        }
        switch session.state {
        case .idle:
            if let last = session.lastReading, last.hasWord { return ("Last value: “\(last.label)”", "text.quote", false) }
            return configured
                ? ("Polls every \(Int(WordApiSettings.pollInterval)) s during Perform — change the word in \(provider.title) to lock the caller label.", "info.circle", false)
                : nil
        case .connecting:
            return ("Connecting to \(provider.title)…", "antenna.radiowaves.left.and.right", false)
        case .watching:
            if session.context == .perform {
                let baselineLabel = session.baseline?.label ?? "…"
                return (
                    "Waiting for word change — baseline «\(baselineLabel)» · change in \(provider.title) to lock caller label",
                    "dot.radiowaves.left.and.right",
                    false
                )
            }
            var current = ""
            if let base = session.baseline, base.hasWord { current = " · now “\(base.label)”" }
            return ("Waiting for a new word\(current)", "dot.radiowaves.left.and.right", false)
        case .locked:
            return nil
        case .failed(let message):
            return (message, "exclamationmark.triangle.fill", true)
        }
    }

    static func truncated(_ text: String, max: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > max else { return trimmed.isEmpty ? "—" : trimmed }
        return String(trimmed.prefix(max - 1)) + "…"
    }
}

struct WordApiHomeCard: View {
    @ObservedObject private var session = WordApiSession.shared
    @AppStorage(WordApiSettings.Key.provider) private var providerRaw = WordApiSettings.Provider.inject.rawValue

    private var provider: WordApiSettings.Provider { WordApiSettings.Provider(rawValue: providerRaw) ?? .inject }

    private var subtitle: String {
        if session.state == .locked, let w = session.lockedReading?.label {
            return "Locked: “\(WordApiInputPanel.truncated(w, max: 32))” · \(provider.title)"
        }
        if let reading = session.lastReading ?? session.baseline {
            let count = reading.count.map(String.init) ?? "–"
            let rc = reading.receiveCount.map(String.init) ?? "–"
            let word = WordApiInputPanel.truncated(reading.label, max: 24)
            return "count \(count) · rc \(rc) · «\(word)» · \(provider.title)"
        }
        if !WordApiSettings.callerLabelEnabled {
            return "Off — Perform unchanged (no call banner)"
        }
        if WordApiSettings.hasWordEndpoint {
            return "\(provider.title) · polls during Perform"
        }
        return "Set Inject, Elips, or Custom API"
    }

    var body: some View {
        HomePanel(accent: OracleHomeSection.wordApi.accent) {
            VStack(alignment: .leading, spacing: 16) {
                HomeSectionTitle(
                    title: "Word API (caller label)",
                    subtitle: subtitle,
                    eyebrow: "Incoming call banner"
                )
                WordApiInputPanel()
            }
        }
    }
}

// MARK: - Contact mode picker

private struct WordContactModePicker: View {
    @Binding var selection: WordApiSettings.ContactMode
    @Namespace private var selectionNS

    var body: some View {
        HStack(spacing: 6) {
            ForEach(WordApiSettings.ContactMode.allCases) { mode in
                let selected = selection == mode
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        selection = mode
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: mode.pickerSymbol)
                            .font(.system(size: 20, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                        Text(mode.title)
                            .font(.subheadline.weight(.bold))
                        Text(mode.pickerHint)
                            .font(.caption2.weight(.medium))
                            .opacity(selected ? 0.9 : 0.55)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(selected ? OracleTheme.ink : OracleTheme.textSecondary)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(OracleTheme.goldGradient)
                                .matchedGeometryEffect(id: "wordContactModeFill", in: selectionNS)
                                .shadow(color: OracleTheme.gold.opacity(0.32), radius: 8, y: 3)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(5)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
        }
    }
}

struct WordApiSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WordApiSettingsView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .foregroundStyle(OracleTheme.gold)
                    }
                }
        }
        .preferredColorScheme(.dark)
        .onDisappear {
            SpectatorWordContactService.restoreKnownContactOriginalName(reason: "Word API settings dismissed")
        }
    }
}
