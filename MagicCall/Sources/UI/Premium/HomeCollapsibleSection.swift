import SwiftUI

/// UserDefaults keys for home section expand/collapse (default **collapsed** on first launch).
enum HomeSectionExpandKey {
    static let performance = "ui.performanceExpanded"
    static let songInput = "ui.songInputExpanded"
    static let wordApi = "ui.wordApiExpanded"
    static let notesContact = "ui.notesContactExpanded"
    static let feedback = "ui.feedbackExpanded"
    static let library = "ui.libraryExpanded"
    static let performLog = "ui.performLogExpanded"
}

/// Home card with tappable header (chevron) — matches Feedback / Library pattern.
struct CollapsibleHomeSection<Content: View>: View {
    @AppStorage private var expanded: Bool
    let accent: Color
    let icon: String
    let title: String
    let summary: String
    /// Yellow star on revelation cards (Song, Caller name, Notes contact).
    let showsRevelationStar: Bool
    @ViewBuilder let content: () -> Content

    init(
        expandedKey: String,
        accent: Color,
        icon: String,
        title: String,
        summary: String,
        showsRevelationStar: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        _expanded = AppStorage(wrappedValue: false, expandedKey)
        self.accent = accent
        self.icon = icon
        self.title = title
        self.summary = summary
        self.showsRevelationStar = showsRevelationStar
        self.content = content
    }

    var body: some View {
        HomePanel(accent: accent) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: icon)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(accent)
                            .frame(width: 40, height: 40)
                            .background(accent.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(title)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(OracleTheme.textPrimary)
                                if showsRevelationStar {
                                    Image(systemName: "star.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.yellow)
                                        .accessibilityLabel("Revelation input")
                                }
                            }
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(OracleTheme.textSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(OracleTheme.textSecondary)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Collapse \(title)" : "Expand \(title)")

                if expanded {
                    content()
                        .padding(.top, 16)
                        .contentShape(Rectangle())
                }
            }
        }
    }
}
