import SwiftUI

struct SongLibrarySection: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var library = SongLibraryStore.shared

    private enum LibraryTab: String, CaseIterable, Identifiable {
        case recent = "Recently used"
        case favorites = "My favorites"

        var id: String { rawValue }

        var emptyMessage: String {
            switch self {
            case .recent: return "No recent songs yet"
            case .favorites: return "No favorites yet"
            }
        }
    }

    @State private var selectedTab: LibraryTab = .recent
    @State private var showClearRecentAlert = false
    @State private var showImportPicker = false
    @State private var importErrorMessage: String?

    private var activeTracks: [PreviewTrack] {
        switch selectedTab {
        case .recent: return library.recentForUI
        case .favorites: return library.favorites
        }
    }

    private var rowInteractionDisabled: Bool {
        if case .downloading = model.loadState { return true }
        if case .searching = model.loadState { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeSectionTitle(
                title: "Library",
                subtitle: "Recently used songs and favorites",
                eyebrow: "Step 2b"
            )

            Text("Songs from Perform appear here. Star a row for My favorites. Remove one with the minus button or swipe left; Clear empties Recently used.")
                .font(.caption)
                .foregroundStyle(OracleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            importAudioBlock

            HStack(spacing: 10) {
                ForEach(LibraryTab.allCases) { tab in
                    libraryTabChip(tab)
                }
            }

            libraryToolbar

            if activeTracks.isEmpty {
                Text(selectedTab.emptyMessage)
                    .font(.caption)
                    .foregroundStyle(OracleTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(activeTracks) { track in
                        libraryRow(track)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            library.reloadFromDisk()
            library.refreshRecentForUI()
            library.logRecentDisplayMerge(context: "SongLibrarySection.onAppear")
        }
        .onChange(of: model.phase) { _, phase in
            guard phase == .setup else { return }
            library.refreshRecentForUI()
        }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: ImportedAudioStore.fileImporterTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await model.importAudioFromFiles(url) }
            case .failure(let error):
                importErrorMessage = error.localizedDescription
            }
        }
        .alert("Import failed", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { importErrorMessage = nil }
        } message: {
            Text(importErrorMessage ?? "")
        }
    }

    private var importAudioBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                showImportPicker = true
            } label: {
                Label("Import audio", systemImage: "square.and.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(OracleTheme.textPrimary)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .disabled(rowInteractionDisabled)
            .accessibilityHint("Pick an audio file from Files to use as a ringtone clip")

            Text("Use only audio you have the right to use.")
                .font(.caption2)
                .foregroundStyle(OracleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func libraryTabChip(_ tab: LibraryTab) -> some View {
        let selected = selectedTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
            library.reloadFromDisk()
            library.refreshRecentForUI()
            library.logRecentDisplayMerge(context: "tab:\(tab.rawValue)")
        } label: {
            Text(tab.rawValue)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(selected ? OracleTheme.textPrimary : OracleTheme.textSecondary)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [OracleTheme.indigo.opacity(0.38), OracleTheme.deepIndigo.opacity(0.22)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            selected
                                ? LinearGradient(
                                    colors: [OracleTheme.gold.opacity(0.85), OracleTheme.indigo.opacity(0.5)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(colors: [OracleTheme.cardBorder], startPoint: .top, endPoint: .bottom),
                            lineWidth: selected ? 1.5 : 1
                        )
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var libraryToolbar: some View {
        if selectedTab == .recent, !library.recentForUI.isEmpty {
            HStack {
                Spacer(minLength: 0)
                Button("Clear") { showClearRecentAlert = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OracleTheme.coral.opacity(0.95))
            }
            .alert("Clear recently used?", isPresented: $showClearRecentAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) { library.clearRecent() }
            } message: {
                Text("This removes every song from Recently used. Favorites are not affected.")
            }
        }
    }

    private func libraryRow(_ track: PreviewTrack) -> some View {
        let favorited = library.isFavorite(track)
        let canonical = library.canonicalTrackForLibrary(track)
        let isPlayingThis = model.isAudible && model.selected?.id == canonical.id
        return HStack(spacing: 8) {
            Button {
                loadAndPlay(track)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isPlayingThis ? "stop.circle.fill" : "play.circle.fill")
                        .font(.body)
                        .foregroundStyle(OracleTheme.gold.opacity(0.92))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(OracleTheme.textPrimary)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.caption)
                            .foregroundStyle(OracleTheme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(rowInteractionDisabled)
            .accessibilityLabel("\(track.title), \(track.artist)")
            .accessibilityHint("Load and play preview")

            Button {
                library.toggleFavorite(track)
            } label: {
                Image(systemName: favorited ? "star.fill" : "star")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(favorited ? OracleTheme.gold : OracleTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(favorited ? "Remove from favorites" : "Add to favorites")

            Button {
                Task { await model.shareRingtoneFromLibrary(track) }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(OracleTheme.gold)
            }
            .buttonStyle(.plain)
            .disabled(rowInteractionDisabled)
            .accessibilityLabel("Share as ringtone")
            .accessibilityHint("Load song, export clip, and open Share")

            Button {
                remove(track)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.body)
                    .foregroundStyle(OracleTheme.textSecondary.opacity(0.85))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(selectedTab == .recent ? "Remove from recently used" : "Remove from favorites")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                remove(track)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func remove(_ track: PreviewTrack) {
        switch selectedTab {
        case .recent:
            library.removeRecent(track)
        case .favorites:
            library.removeFavorite(track)
        }
    }

    private func loadAndPlay(_ track: PreviewTrack) {
        dlog("[LIBRARY] tap Recent row “\(track.title) — \(track.artist)”")
        let canonical = library.canonicalTrackForLibrary(track)
        if model.isAudible, model.selected?.id == canonical.id {
            model.stopAudition(reason: "libraryRow")
            return
        }
        if model.isAudible {
            model.stopAudition(reason: "libraryRowSwitch")
        }
        if let searchQuery = library.searchQuery(forDisplayTrack: track), !searchQuery.isEmpty {
            model.query = searchQuery
            Task {
                await model.search()
                guard model.loadState == .ready else {
                    dlog("[LIBRARY] loadAndPlay search failed loadState=\(model.loadState)")
                    return
                }
                dlog("[LIBRARY] loadAndPlay snapshot resolved → \(model.selected?.title ?? "?")")
                model.audition()
            }
            return
        }
        model.query = track.source == .imported ? track.title : "\(track.title) \(track.artist)"
        Task {
            await model.select(track)
            if model.loadState == .ready, model.selected?.id == track.id {
                dlog("[LIBRARY] loadAndPlay select ok → audition")
                model.audition()
                return
            }
            dlog("[LIBRARY] retry loadAndPlay state=\(model.loadState)")
            if track.source != .imported {
                await model.search()
                let match = model.results.first(where: { $0.id == track.id }) ?? model.results.first
                if let match { await model.select(match) }
            }
            guard model.loadState == .ready else {
                dlog("[LIBRARY] ✗ loadAndPlay failed")
                return
            }
            model.audition()
        }
    }
}
