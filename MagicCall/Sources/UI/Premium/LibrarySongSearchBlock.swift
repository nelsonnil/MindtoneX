import SwiftUI

/// Manual-style song lookup inside Library — search, pick a match, preview, favorite.
struct LibrarySongSearchBlock: View {
    enum ResultsPresentation {
        /// Matches grow inline (Library and other home sections).
        case inline
        /// Matches open in a sheet so the parent layout stays compact (interference test lab).
        case sheet
    }

    @EnvironmentObject private var model: AppModel
    @ObservedObject private var library = SongLibraryStore.shared
    @FocusState private var queryFocused: Bool
    @State private var showResultsSheet = false

    /// When set, matches scroll inside this fixed height instead of growing the parent.
    private let resultsHeight: CGFloat?
    /// When set, tapping a match hands it to the caller instead of loading it as the Home song.
    private let onPick: ((PreviewTrack) -> Void)?
    /// Checkmark for `onPick` mode (the caller's current pick).
    private let pickedTrackID: String?
    private let resultsPresentation: ResultsPresentation

    init(
        resultsHeight: CGFloat? = nil,
        pickedTrackID: String? = nil,
        onPick: ((PreviewTrack) -> Void)? = nil,
        resultsPresentation: ResultsPresentation = .inline
    ) {
        self.resultsHeight = resultsHeight
        self.pickedTrackID = pickedTrackID
        self.onPick = onPick
        self.resultsPresentation = resultsPresentation
    }

    private var searchDisabled: Bool {
        model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || model.loadState == .searching
            || model.loadState == .downloading
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            searchFieldRow

            if case .failed(let message) = model.loadState {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.coral)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if resultsPresentation == .inline, !model.results.isEmpty {
                matchesList
            }

            if resultsPresentation == .sheet, !model.results.isEmpty {
                Button {
                    showResultsSheet = true
                } label: {
                    HStack {
                        Text("\(model.results.count) match\(model.results.count == 1 ? "" : "es")")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("View")
                            .font(.caption.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(OracleTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens song matches in a sheet")
            }

            if onPick == nil, let track = model.selected, model.loadState == .ready {
                LoadedSongReadyRow(track: track)
            }
        }
        .sheet(isPresented: $showResultsSheet) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        searchFieldRow
                        if case .failed(let message) = model.loadState {
                            Label(message, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(OracleTheme.coral)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if model.results.isEmpty, model.loadState != .searching {
                            Text("No matches yet — search by title and artist.")
                                .font(.caption)
                                .foregroundStyle(OracleTheme.textSecondary)
                        } else {
                            matchesList
                        }
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(OracleTheme.screenGradient.ignoresSafeArea())
                .navigationTitle("Song search")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showResultsSheet = false }
                    }
                }
            }
            .environmentObject(model)
            .preferredColorScheme(.dark)
        }
    }

    private var searchFieldRow: some View {
        HStack(spacing: 8) {
            TextField("Song title & artist", text: $model.query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($queryFocused)
                .onSubmit { runSearch() }
                .padding(14)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button(action: runSearch) {
                Group {
                    if model.loadState == .searching {
                        ProgressView()
                            .tint(Color(red: 0.12, green: 0.10, blue: 0.05))
                    } else {
                        Image(systemName: "magnifyingglass")
                            .font(.body.weight(.semibold))
                    }
                }
                .frame(width: 48, height: 48)
                .background(OracleTheme.goldGradient)
                .foregroundStyle(Color(red: 0.12, green: 0.10, blue: 0.05))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(searchDisabled)
            .accessibilityLabel("Search songs")
        }
    }

    private var matchesList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Matches")
                .font(.caption.weight(.semibold))
                .foregroundStyle(OracleTheme.textSecondary)
            VStack(spacing: 8) {
                ForEach(Array(model.results.prefix(8))) { track in
                    searchResultRow(track)
                }
            }
        }
    }

    private func runSearch() {
        queryFocused = false
        if resultsPresentation == .sheet {
            showResultsSheet = true
        }
        Task { await model.searchForPicker() }
    }

    private func searchResultRow(_ track: PreviewTrack) -> some View {
        let favorited = library.isFavorite(track)
        let picking = onPick != nil
        let isSelected = picking
            ? pickedTrackID == track.id
            : model.selected?.id == track.id && model.loadState == .ready
        return HStack(spacing: 8) {
            Button {
                if let onPick {
                    onPick(track)
                } else {
                    Task { await model.select(track) }
                }
                if resultsPresentation == .sheet {
                    showResultsSheet = false
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(OracleTheme.textPrimary)
                            .lineLimit(1)
                        Text("\(track.artist) · \(track.source.rawValue)")
                            .font(.caption)
                            .foregroundStyle(OracleTheme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(OracleTheme.gold)
                    } else if !picking, model.loadState == .downloading, model.selected?.id == track.id {
                        ProgressView()
                            .scaleEffect(0.85)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!picking && model.loadState == .downloading && model.selected?.id != track.id)

            Button {
                library.toggleFavorite(library.canonicalTrackForLibrary(track))
            } label: {
                Image(systemName: favorited ? "star.fill" : "star")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(favorited ? OracleTheme.gold : OracleTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(favorited ? "Remove from favorites" : "Add to favorites")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? OracleTheme.gold.opacity(0.55) : OracleTheme.cardBorder, lineWidth: 1)
        }
    }
}
