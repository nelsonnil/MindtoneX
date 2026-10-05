import SwiftUI

/// Home **Library** card (Option B) — separate `HomePanel` below Song input.
struct SongLibraryPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HomeSectionTitle(
                title: "Library",
                subtitle: "Reload a recent track or pick a favorite",
                eyebrow: "Quick access"
            )
            SongLibrarySection()
        }
    }
}
