import SwiftUI

/// Ready track row with audition and favorite star (manual, API lock, etc.).
struct LoadedSongReadyRow: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var library = SongLibraryStore.shared

    let track: PreviewTrack
    var leadingSystemImage: String = "checkmark.circle.fill"

    private var isFavorite: Bool { library.isFavorite(track) }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: leadingSystemImage)
                .foregroundStyle(OracleTheme.gold)
            Text("\(track.title) — \(track.artist)")
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                library.toggleFavorite(track)
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(isFavorite ? OracleTheme.gold : OracleTheme.textSecondary)
            .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
            Button {
                model.audition()
            } label: {
                Image(systemName: model.isAudible ? "speaker.wave.2.fill" : "play.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(OracleTheme.gold)
            .disabled(model.isAudible)
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
