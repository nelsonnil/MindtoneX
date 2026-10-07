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
    @AppStorage(VoiceSettings.Key.inputMode) private var songInputModeRaw = VoiceSettings.InputMode.manual.rawValue

    @State private var showConnectionSheet = false
    @State private var showHomeContactPicker = false

    private var provider: WordApiSettings.Provider { WordApiSettings.Provider(rawValue: providerRaw) ?? .inject }
    private var configured: Bool { WordApiSettings.hasWordEndpoint }
    private var songInputIsCard: Bool {
        (VoiceSettings.InputMode(rawValue: songInputModeRaw) ?? .manual) == .card
    }
    private var songInputIsVoice: Bool {
        (VoiceSettings.InputMode(rawValue: songInputModeRaw) ?? .manual) == .aiVoice
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: $callerLabelEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show word on incoming call")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OracleTheme.textPrimary)
                    Text("One-time: turn on MindtoneX in Settings → Phone → Call Blocking & Identification")
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
    }

    private var callerPreviewPhoneDigits: String {
        if WordApiSettings.hasKnownContactSelected {
            return WordApiSettings.knownContactPhoneDigits
        }
        if !WordApiSettings.lastDialedPhoneDigits.isEmpty {
            return WordApiSettings.lastDialedPhoneDigits
        }
        let fallback = WordApiSettings.identificationPhoneDigitsRaw()
        return fallback.count >= 7 ? fallback : "34612345678"
    }

    private var callerPreviewPredictionWord: String {
        if let locked = session.lockedReading?.label, !locked.isEmpty { return locked }
        if let last = session.lastReading?.label, !last.isEmpty { return last }
        return "ECLIPSE"
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
            OracleEyebrow(text: "Preview")

            WordApiIncomingCallBannerPreview(
                phoneDigits: callerPreviewPhoneDigits,
                predictionWord: callerPreviewPredictionWord
            )
            .padding(.vertical, 4)

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
                    Text("Restore original name when leaving Caller name connection")
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
            Text("On Perform: use the in-app Phone-style dial, place a real outgoing call, then arm when that call ends.")
                .font(.caption)
                .foregroundStyle(OracleTheme.textSecondary)
            if !WordApiSettings.lastDialedPhoneDigits.isEmpty {
                Text("Last dialed · +\(WordApiSettings.lastDialedPhoneDigits)")
                    .font(.caption.monospaced())
                    .foregroundStyle(OracleTheme.textSecondary)
            } else {
                Text("No number yet — Perform opens the Phone-style dial first.")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.textSecondary)
            }
        }
    }

    private var connectionBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            OracleEyebrow(text: "Spectator word API")

            VStack(alignment: .leading, spacing: 12) {
                WordApiProviderPicker(selectionRaw: $providerRaw)

                HStack(spacing: 8) {
                    Image(systemName: configured ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(configured ? OracleTheme.gold : OracleTheme.coral)
                    Text(configured ? "\(provider.title) active" : WordApiSettings.setupHint)
                        .font(.caption)
                        .foregroundStyle(configured ? OracleTheme.textSecondary : OracleTheme.coral)
                }

                if provider == .card {
                    Text(provider.detail)
                        .font(.caption)
                        .foregroundStyle(OracleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !songInputIsCard {
                        Label("Set **Song input** to Camera — caller word is **line 2** on the same volume scan.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(OracleTheme.coral)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if provider == .voice {
                    voiceScriptBlock(channel: .callerName)
                } else if provider == .inject {
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

                if provider != .card && provider != .voice {
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
                } else if provider == .card {
                    Text("On Perform, press **volume** once — **line 1** loads the song; **line 2** locks caller name when this card uses Camera OCR. No network poll.")
                        .font(.caption2)
                        .foregroundStyle(OracleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if provider == .voice {
                    Text("On Perform, the **same Voice mic** as song input runs a **separate AI prompt** for the contact word — no Inject poll.")
                        .font(.caption2)
                        .foregroundStyle(OracleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
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
    }

    @ViewBuilder
    private var lockedWordRow: some View {
        if session.state == .locked, let word = session.lockedReading?.label {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(OracleTheme.gold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Caller name locked")
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
        let word = WordApiInputPanel.truncated(reading.label, max: 28)
        if provider == .card {
            return session.state == .locked ? "Camera scan · locked «\(word)»" : "Camera scan · last «\(word)»"
        }
        if provider == .voice {
            return session.state == .locked ? "Voice AI · locked «\(word)»" : "Voice AI · last «\(word)»"
        }
        let count = reading.count.map(String.init) ?? "–"
        let rc = reading.receiveCount.map(String.init) ?? "–"
        return "Last poll · count \(count) · rc \(rc) · «\(word)»"
    }

    private var statusLine: (text: String, icon: String, warning: Bool)? {
        if session.isStruggling, session.isActive {
            return ("\(provider.title) not reachable: \(session.lastError ?? "network error") — retrying", "wifi.exclamationmark", true)
        }
        switch session.state {
        case .idle:
            if let last = session.lastReading, last.hasWord { return ("Last value: “\(last.label)”", "text.quote", false) }
            if provider == .card {
                return configured
                    ? ("Camera OCR — caller word on **line 2** (see Instructions for line 3 Notes).", "doc.viewfinder", false)
                    : nil
            }
            if provider == .voice {
                return configured
                    ? ("Voice AI listens on the shared mic — ask the contact-word script.", "mic.fill", false)
                    : nil
            }
            return configured
                ? ("Polls every \(Int(WordApiSettings.pollInterval)) s during Perform — change the word in \(provider.title) to lock the caller name.", "info.circle", false)
                : nil
        case .connecting:
            return ("Connecting to \(provider.title)…", "antenna.radiowaves.left.and.right", false)
        case .watching:
            if provider == .card {
                return (
                    "Waiting for volume scan — caller word on **line 2** (or WORD:/CALLER: label).",
                    "camera.viewfinder",
                    false
                )
            }
            if provider == .voice {
                return (
                    "Listening — use the contact-word script; AI locks when the spectator commits to one word.",
                    "mic.fill",
                    false
                )
            }
            if session.context == .perform {
                let baselineLabel = session.baseline?.label ?? "…"
                return (
                    "Waiting for word change — baseline «\(baselineLabel)» · change in \(provider.title) to lock caller name",
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
            return "Off — incoming call shows the number only"
        }
        if WordApiSettings.hasWordEndpoint {
            if provider == .card { return "Camera (OCR) · line 2 caller · line 3 Notes" }
            if provider == .voice { return "Voice (AI) · contact-word prompt on shared mic" }
            return "\(provider.title) · polls during Perform"
        }
        if provider == .card { return "Camera word needs Song input = Camera" }
        if provider == .voice { return "Voice word needs Song input = Voice + OpenAI key" }
        return "Set Inject, Elips, Custom, Camera OCR, or Voice"
    }

    var body: some View {
        CollapsibleHomeSection(
            expandedKey: HomeSectionExpandKey.wordApi,
            accent: OracleHomeSection.wordApi.accent,
            icon: "phone.arrow.down.left.fill",
            title: "Caller name",
            summary: subtitle,
            showsRevelationStar: true
        ) {
            WordApiInputPanel()
        }
    }
}

// MARK: - Word API provider grid

struct WordApiProviderPicker: View {
    @Binding var selectionRaw: String
    @Namespace private var selectionNS

    private var selection: WordApiSettings.Provider {
        WordApiSettings.Provider(rawValue: selectionRaw) ?? .inject
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(WordApiSettings.Provider.allCases) { provider in
                providerCell(provider)
            }
        }
        .padding(6)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Spectator word integration")
    }

    private func providerCell(_ provider: WordApiSettings.Provider) -> some View {
        let selected = selection == provider
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                selectionRaw = provider.rawValue
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: provider.pickerSymbol)
                        .font(.system(size: 18, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                    Spacer(minLength: 0)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(OracleTheme.ink.opacity(0.85))
                    }
                }
                Text(provider.gridTitle)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(provider.pickerHint)
                    .font(.caption2.weight(.medium))
                    .opacity(selected ? 0.88 : 0.55)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .foregroundStyle(selected ? OracleTheme.ink : OracleTheme.textSecondary)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(OracleTheme.goldGradient)
                        .matchedGeometryEffect(id: "wordApiProviderFill", in: selectionNS)
                        .shadow(color: OracleTheme.gold.opacity(0.28), radius: 8, y: 3)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(provider.title)
        .accessibilityHint(provider.pickerHint)
        .accessibilityAddTraits(selected ? .isSelected : [])
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

// MARK: - Voice script hint (shared mic, separate AI prompt)

struct VoiceMagicianScriptBlock: View {
    let channel: SpectatorListenChannel
    var accent: Color = OracleTheme.gold

    private var songInputIsVoice: Bool { VoiceSettings.inputMode == .aiVoice }
    private var voiceConfigured: Bool { VoiceSettings.isConfigured }
    private var channelReady: Bool {
        switch channel {
        case .callerName: return VoiceListenPlan.current.callerName
        case .notesContact: return VoiceListenPlan.current.notesContact
        case .song: return VoiceListenPlan.current.song
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Magician script", systemImage: "text.quote")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
            Text(channel.magicianScriptHint)
                .font(.caption)
                .foregroundStyle(OracleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !songInputIsVoice {
                Label("Set **Song input** to **Voice** on the home screen.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.coral)
            } else if !voiceConfigured {
                Label("Add your OpenAI key under **Voice → Speech**.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.coral)
            } else if channelReady {
                Label("Ready — \(VoiceListenPlan.current.activeChannels.count) AI listener(s) on one mic.", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(accent)
            }
        }
    }
}

private extension WordApiInputPanel {
    func voiceScriptBlock(channel: SpectatorListenChannel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(provider.detail)
                .font(.caption)
                .foregroundStyle(OracleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VoiceMagicianScriptBlock(channel: channel)
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
