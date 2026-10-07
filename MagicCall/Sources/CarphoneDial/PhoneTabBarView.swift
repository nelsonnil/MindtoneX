import UIKit

/// Programmatic copy of the Phone app bottom tab bar (Favorites · Recents · Contacts · Keypad · Voicemail)
/// with Keypad selected. Metrics and colors are measured from iOS 26 Phone screenshots (430 × 932 pt).
final class PhoneTabBarView: UIView {
    enum Metrics {
        static let height: CGFloat = 62
        static let sideInset: CGFloat = 21
        static let contentInset: CGFloat = 21
        static let pillHeight: CGFloat = 48
        static let pillMinWidth: CGFloat = 74
        static let iconPointSize: CGFloat = 23
        static let labelFontSize: CGFloat = 10
        static let iconCenterOffset: CGFloat = -7.5
        static let labelBaselineFromBottom: CGFloat = 13.7

        /// Distance from the screen bottom; devices without a home indicator get a tighter margin.
        static func bottomInset(safeAreaBottom: CGFloat) -> CGFloat {
            safeAreaBottom > 0 ? 21 : 8
        }
    }

    enum Tab: CaseIterable {
        case favorites, recents, contacts, keypad, voicemail

        var symbol: String {
            switch self {
            case .favorites: return "star.fill"
            case .recents: return "clock.fill"
            case .contacts: return "person.crop.circle.fill"
            case .keypad: return "circle.grid.3x3.fill"
            case .voicemail: return "recordingtape"
            }
        }
    }

    private let glassView = UIVisualEffectView()
    private let fallbackShadow = UIView()
    private let pill = UIView()
    private let itemsStack = UIStackView()
    private var items: [Tab: (icon: UIImageView, label: UILabel, container: UIView)] = [:]
    private let selected: Tab = .keypad

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        isUserInteractionEnabled = false
        backgroundColor = .clear

        fallbackShadow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fallbackShadow)
        glassView.translatesAutoresizingMaskIntoConstraints = false
        glassView.clipsToBounds = true
        addSubview(glassView)
        if #available(iOS 26.0, *) {
            glassView.effect = UIGlassEffect(style: .regular)
            glassView.cornerConfiguration = .capsule()
        } else {
            glassView.backgroundColor = Palette.bar
            glassView.layer.borderWidth = 1 / UIScreen.main.scale
            fallbackShadow.backgroundColor = Palette.bar
            fallbackShadow.layer.shadowColor = UIColor.black.cgColor
            fallbackShadow.layer.shadowOffset = .zero
            fallbackShadow.layer.shadowRadius = 8
        }

        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.backgroundColor = Palette.pill
        glassView.contentView.addSubview(pill)

        itemsStack.translatesAutoresizingMaskIntoConstraints = false
        itemsStack.axis = .horizontal
        itemsStack.alignment = .fill
        itemsStack.distribution = .equalSpacing
        glassView.contentView.addSubview(itemsStack)

        let strings = PhoneTabStrings.current
        for tab in Tab.allCases {
            let container = UIView()
            container.translatesAutoresizingMaskIntoConstraints = false
            let icon = UIImageView(image: UIImage(systemName: tab.symbol,
                                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: Metrics.iconPointSize,
                                                                                                 weight: .medium)))
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.contentMode = .center
            icon.tintColor = tab == selected ? Palette.selected : Palette.item
            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            label.text = strings.title(for: tab)
            label.font = .systemFont(ofSize: Metrics.labelFontSize, weight: .semibold)
            label.textColor = tab == selected ? Palette.selected : Palette.item
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.75
            label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
            container.addSubview(icon)
            container.addSubview(label)
            NSLayoutConstraint.activate([
                icon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                icon.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: Metrics.iconCenterOffset),
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                label.lastBaselineAnchor.constraint(equalTo: container.bottomAnchor, constant: -Metrics.labelBaselineFromBottom),
                container.widthAnchor.constraint(greaterThanOrEqualTo: icon.widthAnchor)
            ])
            itemsStack.addArrangedSubview(container)
            items[tab] = (icon, label, container)
        }

        NSLayoutConstraint.activate([
            fallbackShadow.leadingAnchor.constraint(equalTo: leadingAnchor),
            fallbackShadow.trailingAnchor.constraint(equalTo: trailingAnchor),
            fallbackShadow.topAnchor.constraint(equalTo: topAnchor),
            fallbackShadow.bottomAnchor.constraint(equalTo: bottomAnchor),
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),
            itemsStack.leadingAnchor.constraint(equalTo: glassView.contentView.leadingAnchor, constant: Metrics.contentInset),
            itemsStack.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor, constant: -Metrics.contentInset),
            itemsStack.topAnchor.constraint(equalTo: glassView.contentView.topAnchor),
            itemsStack.bottomAnchor.constraint(equalTo: glassView.contentView.bottomAnchor)
        ])

        if let selectedItem = items[selected] {
            NSLayoutConstraint.activate([
                pill.centerXAnchor.constraint(equalTo: selectedItem.container.centerXAnchor),
                pill.centerYAnchor.constraint(equalTo: glassView.contentView.centerYAnchor),
                pill.heightAnchor.constraint(equalToConstant: Metrics.pillHeight),
                pill.widthAnchor.constraint(greaterThanOrEqualToConstant: Metrics.pillMinWidth),
                pill.widthAnchor.constraint(greaterThanOrEqualTo: selectedItem.label.widthAnchor, constant: 24)
            ])
        }
        updateColors()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let radius = bounds.height / 2
        pill.layer.cornerRadius = Metrics.pillHeight / 2
        pill.layer.cornerCurve = .continuous
        if #unavailable(iOS 26.0) {
            glassView.layer.cornerRadius = radius
            glassView.layer.cornerCurve = .continuous
            fallbackShadow.layer.cornerRadius = radius
            fallbackShadow.layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: radius).cgPath
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
            updateColors()
        }
    }

    private func updateColors() {
        guard #unavailable(iOS 26.0) else {
            return
        }
        let dark = traitCollection.userInterfaceStyle == .dark
        glassView.layer.borderColor = (dark ? UIColor(white: 1, alpha: 0.16) : UIColor(white: 0, alpha: 0.04)).cgColor
        fallbackShadow.layer.shadowOpacity = dark ? 0 : 0.08
    }

    private enum Palette {
        static let item = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.953, alpha: 1) : UIColor(white: 0.098, alpha: 1) }
        static let selected = UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(red: 80 / 255, green: 168 / 255, blue: 249 / 255, alpha: 1)
            : UIColor(red: 54 / 255, green: 124 / 255, blue: 237 / 255, alpha: 1) }
        static let pill = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.204, alpha: 1) : UIColor(white: 0.922, alpha: 1) }
        static let bar = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.071, alpha: 1) : UIColor(white: 0.992, alpha: 1) }
    }
}

/// Phone app tab titles in the device language (falls back to English).
struct PhoneTabStrings {
    let favorites: String
    let recents: String
    let contacts: String
    let keypad: String
    let voicemail: String

    func title(for tab: PhoneTabBarView.Tab) -> String {
        switch tab {
        case .favorites: return favorites
        case .recents: return recents
        case .contacts: return contacts
        case .keypad: return keypad
        case .voicemail: return voicemail
        }
    }

    static var current: PhoneTabStrings {
        for identifier in Locale.preferredLanguages {
            if let strings = forLanguage(identifier) {
                return strings
            }
        }
        return english
    }

    static func forLanguage(_ identifier: String) -> PhoneTabStrings? {
        let normalized = identifier.replacingOccurrences(of: "_", with: "-")
        if let exact = table[normalized] {
            return exact
        }
        let parts = normalized.split(separator: "-").map(String.init)
        if parts.count > 1, let scriptOrRegion = table["\(parts[0])-\(parts[1])"] {
            return scriptOrRegion
        }
        if parts.first == "zh" {
            return normalized.contains("Hant") || normalized.hasSuffix("TW") || normalized.hasSuffix("HK") || normalized.hasSuffix("MO")
                ? table["zh-Hant"] : table["zh-Hans"]
        }
        return parts.first.flatMap { table[$0] }
    }

    private static let english = PhoneTabStrings(favorites: "Favorites", recents: "Recents", contacts: "Contacts",
                                                 keypad: "Keypad", voicemail: "Voicemail")

    private static let table: [String: PhoneTabStrings] = [
        "en": english,
        "en-GB": PhoneTabStrings(favorites: "Favourites", recents: "Recents", contacts: "Contacts", keypad: "Keypad", voicemail: "Voicemail"),
        "en-AU": PhoneTabStrings(favorites: "Favourites", recents: "Recents", contacts: "Contacts", keypad: "Keypad", voicemail: "Voicemail"),
        "es": PhoneTabStrings(favorites: "Favoritos", recents: "Recientes", contacts: "Contactos", keypad: "Teclado", voicemail: "Buzón de voz"),
        "ca": PhoneTabStrings(favorites: "Preferits", recents: "Recents", contacts: "Contactes", keypad: "Teclat", voicemail: "Bústia de veu"),
        "pt": PhoneTabStrings(favorites: "Favoritos", recents: "Recentes", contacts: "Contatos", keypad: "Teclado", voicemail: "Correio de Voz"),
        "pt-PT": PhoneTabStrings(favorites: "Favoritos", recents: "Recentes", contacts: "Contactos", keypad: "Teclado", voicemail: "Correio de voz"),
        "fr": PhoneTabStrings(favorites: "Favoris", recents: "Récents", contacts: "Contacts", keypad: "Clavier", voicemail: "Messagerie"),
        "it": PhoneTabStrings(favorites: "Preferiti", recents: "Recenti", contacts: "Contatti", keypad: "Tastierino", voicemail: "Segreteria"),
        "de": PhoneTabStrings(favorites: "Favoriten", recents: "Anrufliste", contacts: "Kontakte", keypad: "Ziffernblock", voicemail: "Voicemail"),
        "nl": PhoneTabStrings(favorites: "Favorieten", recents: "Recent", contacts: "Contacten", keypad: "Toetsen", voicemail: "Voicemail"),
        "ja": PhoneTabStrings(favorites: "よく使う項目", recents: "履歴", contacts: "連絡先", keypad: "キーパッド", voicemail: "留守番電話"),
        "ko": PhoneTabStrings(favorites: "즐겨찾기", recents: "최근 통화", contacts: "연락처", keypad: "키패드", voicemail: "음성 사서함"),
        "zh-Hans": PhoneTabStrings(favorites: "个人收藏", recents: "最近通话", contacts: "通讯录", keypad: "拨号键盘", voicemail: "语音留言"),
        "zh-Hant": PhoneTabStrings(favorites: "常用聯絡資訊", recents: "通話記錄", contacts: "聯絡人", keypad: "撥號鍵盤", voicemail: "語音信箱"),
        "ru": PhoneTabStrings(favorites: "Избранное", recents: "Недавние", contacts: "Контакты", keypad: "Клавиши", voicemail: "Автоответчик")
    ]
}
