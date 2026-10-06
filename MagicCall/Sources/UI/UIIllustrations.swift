import SwiftUI

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
