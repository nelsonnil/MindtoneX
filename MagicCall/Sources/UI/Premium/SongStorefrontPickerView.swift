import SwiftUI

/// Searchable storefront list (~180 iTunes catalogs). Menu-style pickers are unusable at this size.
struct SongStorefrontPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var storeCountry: String
    @State private var searchText = ""

    private var filteredEntries: [(code: String, name: String)] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return SongStorefront.catalogEntries }
        let upper = q.uppercased()
        return SongStorefront.catalogEntries.filter { entry in
            entry.name.localizedCaseInsensitiveContains(q) || entry.code.contains(upper)
        }
    }

    private var groupedEntries: [(letter: String, rows: [(code: String, name: String)])] {
        let dict = Dictionary(grouping: filteredEntries) { entry -> String in
            let first = entry.name.first.map { String($0).uppercased() } ?? "#"
            return first
        }
        return dict.keys.sorted().map { letter in
            (letter: letter, rows: dict[letter]!.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    storefrontRow(code: "", name: SongStorefront.automaticTitle, subtitle: "Uses Settings → General → Language & Region")
                }

                if searchText.isEmpty {
                    ForEach(groupedEntries, id: \.letter) { group in
                        Section(group.letter) {
                            ForEach(group.rows, id: \.code) { entry in
                                storefrontRow(code: entry.code, name: entry.name, subtitle: entry.code)
                            }
                        }
                    }
                } else {
                    Section("Results") {
                        ForEach(filteredEntries, id: \.code) { entry in
                            storefrontRow(code: entry.code, name: entry.name, subtitle: entry.code)
                        }
                    }
                }

                let custom = SongStorefront.normalizedCode(stored: storeCountry)
                if !custom.isEmpty, !SongStorefront.isKnownStorefront(code: custom) {
                    Section("Current selection") {
                        storefrontRow(code: custom, name: "Custom (\(custom))", subtitle: "Not in catalog list")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "Country or ISO code (e.g. SA, Egypt)")
            .navigationTitle("iTunes storefront")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func isSelected(code: String) -> Bool {
        if code.isEmpty { return SongStorefront.isAutomatic(stored: storeCountry) }
        return SongStorefront.normalizedCode(stored: storeCountry) == code
    }

    @ViewBuilder
    private func storefrontRow(code: String, name: String, subtitle: String) -> some View {
        let selected = isSelected(code: code)
        Button {
            storeCountry = code
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .foregroundStyle(OracleTheme.textPrimary)
                    if !code.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(OracleTheme.textSecondary)
                    } else {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(OracleTheme.textSecondary)
                    }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(OracleTheme.gold)
                }
            }
        }
    }
}
