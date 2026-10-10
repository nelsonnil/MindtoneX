import SwiftUI

// MARK: - Instructions annotated screenshots

enum InstructionScreenshotAsset {
    static let contactDetailFull = "InstructionContactDetailFull"
    static let contactDetailNotes = "InstructionContactDetailNotes"
    static let recentsIncoming = "InstructionRecentsIncoming"
}

struct InstructionScreenshotCallout: Identifiable {
    let id = UUID()
    let text: String
    /// Normalized point on the image (0…1, origin top-leading).
    let anchor: CGPoint
    var placement: InstructionCalloutPlacement = .below
}

enum InstructionCalloutPlacement {
    case above, below, leading, trailing
}

/// Real iPhone screenshot with gold Oracle-style callout pills (Instructions tabs only).
struct InstructionAnnotatedScreenshot: View {
    let imageName: String
    var caption: String?
    let callouts: [InstructionScreenshotCallout]
    var maxWidth: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            imageBlock
            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(OracleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let parts = callouts.map(\.text) + (caption.map { [$0] } ?? [])
        return parts.joined(separator: ". ")
    }

    private var imageBlock: some View {
        Image(imageName)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: maxWidth)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
            }
            .overlay {
                GeometryReader { geo in
                    let size = geo.size
                    ForEach(callouts) { callout in
                        InstructionCalloutMarker(callout: callout, containerSize: size)
                    }
                }
            }
            .shadow(color: Color.black.opacity(0.35), radius: 10, y: 5)
    }
}

private struct InstructionCalloutMarker: View {
    let callout: InstructionScreenshotCallout
    let containerSize: CGSize

    var body: some View {
        let anchor = CGPoint(
            x: callout.anchor.x * containerSize.width,
            y: callout.anchor.y * containerSize.height
        )
        let labelCenter = labelCenter(relativeTo: anchor)

        ZStack {
            CalloutConnector(from: labelCenter, to: anchor)
            InstructionCalloutPill(text: callout.text)
                .position(labelCenter)
            Circle()
                .fill(OracleTheme.gold)
                .frame(width: 8, height: 8)
                .overlay {
                    Circle().stroke(Color.white.opacity(0.85), lineWidth: 1.5)
                }
                .position(anchor)
        }
    }

    private func labelCenter(relativeTo anchor: CGPoint) -> CGPoint {
        let offset: CGFloat = 44
        switch callout.placement {
        case .above:
            return CGPoint(x: anchor.x, y: max(28, anchor.y - offset))
        case .below:
            return CGPoint(x: anchor.x, y: min(containerSize.height - 28, anchor.y + offset))
        case .leading:
            return CGPoint(x: max(60, anchor.x - offset * 1.35), y: anchor.y)
        case .trailing:
            return CGPoint(x: min(containerSize.width - 60, anchor.x + offset * 1.35), y: anchor.y)
        }
    }
}

private struct InstructionCalloutPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(OracleTheme.deepIndigo)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule(style: .continuous)
                    .fill(OracleTheme.goldGradient)
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
            }
            .shadow(color: OracleTheme.gold.opacity(0.35), radius: 6, y: 2)
            .frame(maxWidth: 168)
    }
}

private struct CalloutConnector: View {
    let from: CGPoint
    let to: CGPoint

    var body: some View {
        Path { path in
            path.move(to: from)
            path.addLine(to: to)
        }
        .stroke(
            OracleTheme.gold.opacity(0.85),
            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
        )
    }
}

/// Control Center–style silent mode hint (bell with strike).
struct SilentModeIllustration: View {
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(height: 120)
                HStack(spacing: 28) {
                    controlTile(icon: "bell.slash.fill", label: "Silent", tint: .red, emphasized: true)
                    controlTile(icon: "sun.max.fill", label: "Brightness", tint: .yellow, emphasized: false)
                    controlTile(icon: "wifi", label: "Wi‑Fi", tint: .blue, emphasized: false)
                }
                .padding(.horizontal, 20)
            }
            Label("Turn Silent ON before you perform", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Illustration: Control Center with Silent mode highlighted")
    }

    private func controlTile(icon: String, label: String, tint: Color, emphasized: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(emphasized ? tint.opacity(0.2) : Color.primary.opacity(0.08))
                .clipShape(Circle())
                .overlay {
                    if emphasized {
                        Circle().stroke(tint, lineWidth: 2)
                    }
                }
            Text(label)
                .font(.caption2)
                .foregroundStyle(emphasized ? .primary : .secondary)
        }
    }
}

/// Share sheet → Edit Actions → star on Use as Ringtone.
struct ShareRingtoneFavoritesIllustration: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Share sheet")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                shareRow("AirDrop", icon: "airdrop", favorite: false)
                shareRow("Use as Ringtone", icon: "bell.badge.fill", favorite: true)
                shareRow("Save to Files", icon: "folder", favorite: false)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
                Text("Tap More → Edit Actions → + on “Use as Ringtone” → Favorites")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func shareRow(_ title: String, icon: String, favorite: Bool) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 28)
                .foregroundStyle(.tint)
            Text(title)
                .font(.subheadline)
            Spacer()
            if favorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 42)
        }
    }
}

struct POCBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.tint)
            Text("Choose Card, Voice, Notes, or API on the home screen to load a song before Perform.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct ComingSoonInputRow: View {
    let title: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.tertiary)
                .frame(width: 28)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text("Coming soon")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.tertiarySystemFill))
                .clipShape(Capsule())
        }
        .font(.subheadline)
        .padding(.vertical, 4)
    }
}
