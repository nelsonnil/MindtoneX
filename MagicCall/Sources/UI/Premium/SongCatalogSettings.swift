import SwiftUI

/// Song card › **Catalog & ringtone** — iTunes storefront and ringtone mode (Normal vs Interference).
struct SongCatalogAndRingtoneSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SongCatalogStorefrontBlock()
            SongRingtoneModeBlock()
        }
    }
}

/// Apple iTunes catalog country for song search (Voice, Camera, Notes, API, Library).
struct SongCatalogStorefrontBlock: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(Prefs.Key.storeCountry) private var storeCountry = ""
    @State private var showSongStorefrontPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Song search catalog")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OracleTheme.textPrimary)
            Text("Apple iTunes catalog country — not MindtoneX app language.")
                .font(.caption)
                .foregroundStyle(OracleTheme.textSecondary)

            Button {
                showSongStorefrontPicker = true
            } label: {
                HStack {
                    Text(SongStorefront.pickerRowTitle(stored: storeCountry))
                        .foregroundStyle(OracleTheme.textPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(OracleTheme.textSecondary)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(OracleTheme.cardFill.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Song search catalog")
            .accessibilityHint("Opens searchable list of iTunes storefront countries")

            Text(
                "iTunes preview catalog for Voice, Camera, Notes, API, and Library. "
                + "Trying **\(SongStorefront.effectiveCode(stored: storeCountry))** first"
                + (SongStorefront.isAutomatic(stored: storeCountry)
                    ? " (iPhone region)."
                    : ".")
                + " If empty, falls back to **US**, then **Deezer**."
            )
            .font(.caption)
            .foregroundStyle(OracleTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
        }
        .sheet(isPresented: $showSongStorefrontPicker) {
            SongStorefrontPickerView(storeCountry: $storeCountry)
        }
        .onChange(of: storeCountry) { _, _ in
            Task { await model.previews.clearCaches() }
        }
    }
}
