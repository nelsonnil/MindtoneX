import CallKit
import Contacts
import SwiftUI
import UIKit

/// Home → Caller name setup: Call Directory extension + Contacts permission at a glance.
struct CallerNameSetupStatusView: View {
    var saveWordAsContact: Bool

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @State private var callDirectoryStatus: CXCallDirectoryManager.EnabledStatus = .unknown
    @State private var callDirectoryLoading = true
    @State private var contactsStatus = CNContactStore.authorizationStatus(for: .contacts)

    private static let extensionToggleName = "MindtoneX"
    private static let phoneSettingsPath = "Settings → Phone → Call Blocking & Identification"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            OracleEyebrow(text: "Setup")

            callIdentificationBlock

            appGroupSharingRow

            if saveWordAsContact {
                contactsAccessRow
            } else {
                Text("Call Directory (**Call identification** above) still backs up the word if Contacts save is off.")
                    .font(.caption2)
                    .foregroundStyle(OracleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { refreshStatus() }
        .onChange(of: saveWordAsContact) { _, _ in refreshStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshStatus() }
        }
    }

    // MARK: - Call identification

    private var callIdentificationBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: callIdentificationTapped) {
                HStack(alignment: .top, spacing: 10) {
                    callIdentificationStatusIcon
                        .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Call identification")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(OracleTheme.textPrimary)
                            Spacer(minLength: 8)
                            if callIdentificationNeedsSettings {
                                HStack(spacing: 4) {
                                    Text("Open Settings")
                                        .font(.caption.weight(.bold))
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.bold))
                                }
                                .foregroundStyle(OracleTheme.gold)
                            }
                        }

                        Text(callIdentificationStatusLine)
                            .font(.caption)
                            .foregroundStyle(callIdentificationStatusColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(!callIdentificationNeedsSettings && !callDirectoryLoading)

            if callDirectoryFullyReady {
                Label("On — incoming calls can show your word", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.green)
            } else if callDirectoryEnabled && !appGroupAvailable {
                extensionOnButAppGroupMissingBanner
            } else {
                callIdentificationMiniGuide
            }
        }
    }

    private var callIdentificationMiniGuide: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Without this, peek can show the word but incoming calls will not.")
                .font(.caption.weight(.bold))
                .foregroundStyle(OracleTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                miniGuideStep(1, "Open **Settings**")
                miniGuideStep(2, "**Phone**")
                miniGuideStep(3, "**Call Blocking & Identification**")
                miniGuideStepNumber(4) {
                    Text("Turn ") + Text(Self.extensionToggleName).bold() + Text(" ON").bold()
                }
            }

            Text("Opens MindtoneX in Settings — then go to \(Self.phoneSettingsPath). iOS has no direct link to the Phone menu.")
                .font(.caption2)
                .foregroundStyle(OracleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(OracleTheme.coral.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(OracleTheme.coral.opacity(0.25), lineWidth: 1)
        }
    }

    private func miniGuideStep(_ number: Int, _ markdown: LocalizedStringKey) -> some View {
        miniGuideStepNumber(number) {
            Text(markdown)
                .font(.caption)
                .foregroundStyle(OracleTheme.textSecondary)
        }
    }

    private func miniGuideStepNumber<Content: View>(_ number: Int, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(OracleTheme.gold)
                .frame(width: 16, alignment: .trailing)
            content()
                .font(.caption)
                .foregroundStyle(OracleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var callIdentificationStatusIcon: some View {
        if callDirectoryLoading {
            ProgressView()
                .controlSize(.small)
                .tint(OracleTheme.textSecondary)
        } else if callDirectoryFullyReady {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.green)
        } else if callDirectoryEnabled && !appGroupAvailable {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(OracleTheme.coral)
        } else {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(OracleTheme.coral)
        }
    }

    private var appGroupAvailable: Bool {
        CallerLabelStore.isAppGroupAvailable
    }

    private var callDirectoryEnabled: Bool {
        !callDirectoryLoading && callDirectoryStatus == .enabled
    }

    /// Extension toggle ON is not enough — App Group must be signed for Call Directory to read the word.
    private var callDirectoryFullyReady: Bool {
        callDirectoryEnabled && appGroupAvailable
    }

    private var callIdentificationNeedsSettings: Bool {
        callDirectoryLoading || callDirectoryStatus != .enabled
    }

    private var callIdentificationStatusLine: String {
        if callDirectoryLoading { return "Checking Call Directory…" }
        switch callDirectoryStatus {
        case .enabled:
            if appGroupAvailable {
                return "Enabled — MindtoneX can label incoming calls."
            }
            return "Enabled in Settings, but App Group sharing is missing from this build."
        case .disabled:
            return "Disabled — turn MindtoneX on under \(Self.phoneSettingsPath)."
        case .unknown:
            return "Unknown — confirm MindtoneX under \(Self.phoneSettingsPath)."
        @unknown default:
            return "Unknown — confirm MindtoneX under \(Self.phoneSettingsPath)."
        }
    }

    private var callIdentificationStatusColor: Color {
        if callDirectoryLoading { return OracleTheme.textSecondary }
        if callDirectoryFullyReady { return Color.green }
        if callDirectoryEnabled && !appGroupAvailable { return OracleTheme.coral }
        return callDirectoryEnabled ? Color.green : OracleTheme.coral
    }

    private var extensionOnButAppGroupMissingBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Call identification is ON in Settings, but this install cannot share data with the extension.")
                .font(.caption.weight(.bold))
                .foregroundStyle(OracleTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Delete MindtoneX and install a recent TestFlight build signed with App Group \(CallerLabelStore.appGroupID). Peek may still work; incoming caller name will not.")
                .font(.caption2)
                .foregroundStyle(OracleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(OracleTheme.coral.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(OracleTheme.coral.opacity(0.25), lineWidth: 1)
        }
    }

    // MARK: - App Group

    private var appGroupSharingRow: some View {
        HStack(alignment: .top, spacing: 10) {
            appGroupStatusIcon
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text("App Group data sharing")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OracleTheme.textPrimary)

                Text(appGroupStatusLine)
                    .font(.caption)
                    .foregroundStyle(appGroupStatusColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var appGroupStatusIcon: some View {
        if appGroupAvailable {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.green)
        } else {
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(OracleTheme.coral)
        }
    }

    private var appGroupStatusLine: String {
        if appGroupAvailable {
            return "Available — app and Call Directory can share the locked word."
        }
        return "Not available — reinstall a TestFlight build with App Group signing (app + extension)."
    }

    private var appGroupStatusColor: Color {
        appGroupAvailable ? Color.green : OracleTheme.coral
    }

    private func callIdentificationTapped() {
        guard callIdentificationNeedsSettings else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }
        openAppSettings()
    }

    // MARK: - Contacts

    private var contactsAccessRow: some View {
        Button(action: contactsRowTapped) {
            HStack(alignment: .top, spacing: 10) {
                contactsStatusIcon
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Contacts access")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(OracleTheme.textPrimary)
                        Spacer(minLength: 8)
                        if contactsNeedsSettings || contactsStatus == .notDetermined {
                            HStack(spacing: 4) {
                                Text(contactsActionTitle)
                                    .font(.caption.weight(.bold))
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.bold))
                            }
                            .foregroundStyle(OracleTheme.gold)
                        }
                    }

                    Text(contactsStatusLine)
                        .font(.caption)
                        .foregroundStyle(contactsStatusColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var contactsStatusIcon: some View {
        switch contactsStatus {
        case .authorized, .limited:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.green)
        case .denied, .restricted:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(OracleTheme.coral)
        case .notDetermined:
            Image(systemName: "questionmark.circle.fill")
                .font(.title3)
                .foregroundStyle(OracleTheme.textSecondary)
        @unknown default:
            Image(systemName: "questionmark.circle.fill")
                .font(.title3)
                .foregroundStyle(OracleTheme.textSecondary)
        }
    }

    private var contactsNeedsSettings: Bool {
        contactsStatus == .denied || contactsStatus == .restricted
    }

    private var contactsActionTitle: String {
        switch contactsStatus {
        case .notDetermined: return "Allow"
        case .denied, .restricted: return "Open Settings"
        default: return ""
        }
    }

    private var contactsStatusLine: String {
        switch contactsStatus {
        case .authorized:
            return "Authorized — MindtoneX can save the locked word to Contacts."
        case .limited:
            return "Limited — selected contacts only; verify your spectator is allowed."
        case .denied:
            return "Denied — enable Contacts for MindtoneX in Settings."
        case .restricted:
            return "Restricted — Contacts access blocked on this device."
        case .notDetermined:
            return "Not determined — tap to allow Contacts for silent save at lock."
        @unknown default:
            return "Unknown Contacts status."
        }
    }

    private var contactsStatusColor: Color {
        switch contactsStatus {
        case .authorized, .limited:
            return Color.green
        case .denied, .restricted:
            return OracleTheme.coral
        case .notDetermined:
            return OracleTheme.textSecondary
        @unknown default:
            return OracleTheme.textSecondary
        }
    }

    private func contactsRowTapped() {
        switch contactsStatus {
        case .notDetermined:
            CNContactStore().requestAccess(for: .contacts) { _, _ in
                DispatchQueue.main.async { refreshStatus() }
            }
        case .denied, .restricted:
            openAppSettings()
        case .authorized, .limited:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        @unknown default:
            break
        }
    }

    // MARK: - Refresh

    private func refreshStatus() {
        contactsStatus = CNContactStore.authorizationStatus(for: .contacts)
        callDirectoryLoading = true
        CXCallDirectoryManager.sharedInstance.getEnabledStatusForExtension(
            withIdentifier: CallerLabelStore.extensionBundleID
        ) { status, _ in
            DispatchQueue.main.async {
                callDirectoryStatus = status
                callDirectoryLoading = false
            }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}
