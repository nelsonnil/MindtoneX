import SwiftUI

struct SongLibrarySection: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var library = SongLibraryStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HomeSectionTitle(
                title: "Library",
                subtitle: "Recently used songs and favorites",
                eyebrow: "Step 2b"
            )

            librarySubsection(
                title: "Recently used",
                emptyMessage: "No recent songs yet",
                tracks: library.recent
            )
            librarySubsection(
                title: "My favorites",
                emptyMessage: "No favorites yet",
                tracks: library.favorites
            )
        }
    }

    @ViewBuilder
    private func librarySubsection(title: String, emptyMessage: String, tracks: [PreviewTrack]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OracleTheme.textPrimary)

            if tracks.isEmpty {
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundStyle(OracleTheme.textSecondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tracks) { track in
                            libraryChip(track)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func libraryChip(_ track: PreviewTrack) -> some View {
        let favorited = library.isFavorite(track)
        return Button {
            reload(track)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(track.artist)
                    .font(.caption2)
                    .foregroundStyle(OracleTheme.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 148, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
            }
            .overlay(alignment: .topTrailing) {
                if favorited {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(OracleTheme.gold)
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(model.loadState == .downloading || model.loadState == .searching)
        .accessibilityLabel("\(track.title), \(track.artist)")
        .accessibilityHint("Load this song again")
    }

    private func reload(_ track: PreviewTrack) {
        model.query = "\(track.title) \(track.artist)"
        Task { await model.select(track) }
    }
}
