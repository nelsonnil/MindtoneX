import SwiftUI
import UIKit

/// iOS 26 Spotlight over the stage screenshot. Sizes are measured on an iPhone 16 Pro screen recording.
struct SpotlightPerformView: View {
    @ObservedObject private var session = SpotlightSession.shared
    @ObservedObject private var icons = SpotlightAppIconStore.shared
    @AppStorage(SpotlightSettings.Key.suggestedApps) private var suggestedAppsRaw = ""
    @AppStorage(SpotlightSettings.Key.browser) private var browserRaw = SpotlightSettings.Browser.safari.rawValue

    private let strings = SpotlightStrings.current

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        if session.visibleText.isEmpty {
                            emptyState
                        } else {
                            results
                        }
                        Color.clear
                            .frame(height: 320)
                            .contentShape(Rectangle())
                            .onTapGesture { session.close() }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 3)
                }
                .scrollDismissesKeyboard(.never)
                .opacity(Double(session.reveal))
                .scaleEffect(0.94 + 0.06 * session.reveal, anchor: .top)

                searchBar
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .opacity(Double(min(1, session.reveal * 1.6)))
            }

            SpotlightKeyField(
                text: session.secret,
                focused: session.isOpen && !session.contactCardShown,
                returnKey: session.topHit == nil ? .search : .go,
                onChange: { session.secretChanged($0) },
                onReturn: { session.returnPressed() }
            )
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
        }
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(session.isOpen)
    }

    // MARK: Background

    private var backdrop: some View {
        Color.clear
            .overlay {
                if let image = session.backdrop {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 46 * session.reveal, opaque: true)
                }
            }
            .clipped()
            .overlay { Color.black.opacity(0.32 * Double(session.reveal)) }
        .opacity(Double(min(1, session.reveal * 2)))
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { session.close() }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(strings.siriSuggestions, trailing: strings.showLess, divider: false)
            appGrid
            if !session.recents.isEmpty {
                sectionHeader(strings.recentSearches, trailing: strings.clear)
                    .padding(.top, 22)
                ForEach(session.recents) { entry in
                    HStack(spacing: 15) {
                        SpotlightAvatar(entry: entry, size: 24)
                        Text(entry.name)
                            .font(.system(size: 17, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 50)
                    rowDivider(inset: 0)
                }
            }
        }
    }

    private var appGrid: some View {
        let ids = Array(SpotlightSettings.decodeApps(suggestedAppsRaw).prefix(SpotlightSettings.suggestedAppCount))
        let columns = Array(repeating: GridItem(.fixed(62), spacing: 24), count: 4)
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(ids, id: \.self) { id in
                VStack(spacing: 6) {
                    SpotlightAppIcon(bundleId: id, size: 62)
                    Text(icons.name(for: id))
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: 84)
                }
            }
        }
        .padding(.vertical, 17)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.17), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.top, 8)
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        if let hit = session.topHit {
            sectionHeader(strings.topHit, divider: false)
            topHitCard(hit)
                .padding(.top, 8)
                .padding(.bottom, 22)
        }

        sectionHeader(strings.suggestions)
        HStack(spacing: 15) {
            SpotlightAppIcon(bundleId: browserBundleId, size: 23)
            Text(session.visibleText)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(height: 52)

        let others = session.otherMatches
        if !others.isEmpty {
            sectionHeader(strings.contacts)
                .padding(.top, 14)
            ForEach(Array(others.enumerated()), id: \.element.id) { index, entry in
                HStack(spacing: 14) {
                    SpotlightAvatar(entry: entry, size: 40)
                    Text(entry.name)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(height: 60)
                if index < others.count - 1 { rowDivider(inset: 54) }
            }
        }
    }

    private var browserBundleId: String {
        (SpotlightSettings.Browser(rawValue: browserRaw) ?? .safari).bundleId
    }

    private func topHitCard(_ hit: SpotlightSession.ContactEntry) -> some View {
        HStack(spacing: 12) {
            SpotlightAvatar(entry: hit, size: 58)
            Text(hit.name)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                actionCircle("video.fill")
                actionCircle("message.fill")
                actionCircle("phone.fill")
            }
        }
        .padding(.leading, 19)
        .padding(.trailing, 15)
        .frame(height: 97)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white.opacity(0.1))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .onTapGesture { session.openTopHit() }
    }

    private func actionCircle(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 33, height: 33)
            .background(Color.white.opacity(0.2), in: Circle())
    }

    // MARK: Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            fieldText
            Spacer(minLength: 0)
            if session.visibleText.isEmpty {
                Image(systemName: "mic")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
            } else {
                Button { session.clearPressed() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 19))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.black.opacity(0.8), Color.white.opacity(0.9))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .frame(height: 44)
        .background {
            Capsule().fill(.ultraThinMaterial)
            Capsule().fill(Color.black.opacity(0.22))
        }
        .overlay { Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75) }
    }

    @ViewBuilder
    private var fieldText: some View {
        let visible = session.visibleText
        if visible.isEmpty {
            HStack(spacing: 1) {
                SpotlightCaret(visible: session.isOpen)
                Text(strings.searchPlaceholder)
                    .foregroundStyle(.white.opacity(0.45))
            }
            .font(.system(size: 17))
        } else {
            HStack(spacing: 1) {
                Text(visible)
                    .foregroundStyle(.white)
                SpotlightCaret(visible: true)
            }
            .font(.system(size: 17))
            .lineLimit(1)
        }
    }

    // MARK: Pieces

    private func sectionHeader(_ title: String, trailing: String? = nil, divider: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white.opacity(0.88))
                }
            }
            if divider { rowDivider(inset: 0) }
        }
    }

    private func rowDivider(inset: CGFloat) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.22))
            .frame(height: 0.5)
            .padding(.leading, inset)
    }
}

struct SpotlightAvatar: View {
    let entry: SpotlightSession.ContactEntry
    let size: CGFloat

    var body: some View {
        Group {
            if let thumbnail = entry.thumbnail {
                Image(uiImage: thumbnail).resizable().scaledToFill()
            } else {
                LinearGradient(
                    colors: [Color(red: 0.58, green: 0.62, blue: 0.88), Color(red: 0.37, green: 0.41, blue: 0.71)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .overlay {
                    Text(entry.initials)
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.5)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// Blinking text cursor drawn next to the disguise text (the real text field is hidden).
private struct SpotlightCaret: View {
    let visible: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let on = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.white)
                .frame(width: 2, height: 22)
                .opacity(visible && on ? 1 : 0)
        }
        .frame(width: 2, height: 22)
    }
}

/// Invisible text field that owns the real keyboard. Its text is the secret song query.
struct SpotlightKeyField: UIViewRepresentable {
    let text: String
    let focused: Bool
    let returnKey: UIReturnKeyType
    let onChange: (String) -> Void
    let onReturn: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.keyboardAppearance = .dark
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.autocapitalizationType = .none
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.smartInsertDeleteType = .no
        field.inlinePredictionType = .no
        field.enablesReturnKeyAutomatically = true
        field.returnKeyType = returnKey
        field.textColor = .clear
        field.tintColor = .clear
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        if field.returnKeyType != returnKey {
            field.returnKeyType = returnKey
            if field.isFirstResponder { field.reloadInputViews() }
        }
        if focused, !field.isFirstResponder {
            DispatchQueue.main.async { if field.window != nil { field.becomeFirstResponder() } }
        } else if !focused, field.isFirstResponder {
            DispatchQueue.main.async { field.resignFirstResponder() }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SpotlightKeyField?

        @objc func changed(_ field: UITextField) {
            parent?.onChange(field.text ?? "")
        }

        /// The iOS “double space = period” shortcut would turn the 2-song gap into “. ”; keep both spaces instead.
        func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            guard string == ". ", let current = field.text, let swapped = Range(range, in: current), current[swapped] == " " else {
                return true
            }
            field.text = current.replacingCharacters(in: swapped, with: "  ")
            changed(field)
            return false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent?.onReturn()
            return false
        }
    }
}
