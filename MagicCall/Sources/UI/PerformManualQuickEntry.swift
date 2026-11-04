import SwiftUI

/// Performer-only quick song lookup after switching to Manual from the stage input rail.
struct PerformManualQuickEntryOverlay: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var queryFocused: Bool
    @State private var showResultsSheet = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture { model.dismissPerformManualQuickEntry() }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Manual", systemImage: "keyboard")
                        .font(.headline.weight(.bold))
                    Spacer(minLength: 0)
                    Button {
                        model.dismissPerformManualQuickEntry()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }

                HStack(spacing: 10) {
                    TextField("Song title & artist", text: $model.query)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($queryFocused)
                        .submitLabel(.search)
                        .onSubmit { Task { await runSearch() } }

                    if isSearching {
                        ProgressView()
                            .controlSize(.regular)
                    } else {
                        Button("Search") {
                            Task { await runSearch() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(trimmedQuery.isEmpty)
                    }
                }

                if let failureMessage {
                    Text(failureMessage)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !model.results.isEmpty {
                    Button {
                        showResultsSheet = true
                    } label: {
                        HStack {
                            Text("\(model.results.count) match\(model.results.count == 1 ? "" : "es")")
                                .font(.subheadline.weight(.semibold))
                            Spacer(minLength: 0)
                            Text("View list")
                                .font(.caption.weight(.semibold))
                            Image(systemName: "chevron.up")
                                .font(.caption2.weight(.bold))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .onAppear {
            queryFocused = true
        }
        .sheet(isPresented: $showResultsSheet) {
            PerformManualSearchResultsSheet(
                onSelected: {
                    showResultsSheet = false
                    model.dismissPerformManualQuickEntry()
                }
            )
            .environmentObject(model)
        }
    }

    private var trimmedQuery: String {
        model.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        model.loadState == .searching
    }

    private var failureMessage: String? {
        if case .failed(let message) = model.loadState { return message }
        return nil
    }

    private func runSearch() async {
        guard !trimmedQuery.isEmpty else { return }
        queryFocused = false
        await model.searchForPicker()
        if !model.results.isEmpty {
            showResultsSheet = true
        }
    }
}

private struct PerformManualSearchResultsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let onSelected: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if model.results.isEmpty {
                    ContentUnavailableView(
                        "No matches",
                        systemImage: "magnifyingglass",
                        description: Text("Try different words for title or artist.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(model.results) { track in
                                resultRow(track)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Song matches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func resultRow(_ track: PreviewTrack) -> some View {
        let isSelected = model.selected?.id == track.id && model.loadState == .ready
        let isLoadingThis = model.selected?.id == track.id && model.loadState == .downloading

        return HStack(spacing: 10) {
            Button {
                Task { await select(track) }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("\(track.artist) · \(track.source.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if isLoadingThis {
                        ProgressView()
                            .scaleEffect(0.85)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.loadState == .downloading && model.selected?.id != track.id)

            Button {
                Task { await model.shareRingtoneFromLibrary(track) }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .disabled(model.loadState == .downloading)
            .accessibilityLabel("Share as ringtone")
            .accessibilityHint("Load song, export clip, and open Share")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.green.opacity(0.45) : Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private func select(_ track: PreviewTrack) async {
        await model.select(track)
        guard model.loadState == .ready else { return }
        onSelected()
    }
}
