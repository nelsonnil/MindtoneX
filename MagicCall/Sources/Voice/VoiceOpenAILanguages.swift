import Foundation

/// OpenAI Realtime / transcription ISO-639-1 options for the Language picker.
enum VoiceOpenAILanguages {
    struct Option: Identifiable, Hashable {
        let id: String
        let title: String
        let openAICodes: [String]
    }

    /// Popular picks first, then alphabetical by title.
    static let options: [Option] = {
        var list: [Option] = [
            Option(id: "auto", title: "Automatic (detect)", openAICodes: []),
            Option(id: "es-en", title: "Spanish & English", openAICodes: ["es", "en"]),
        ]
        let singles: [(String, String)] = [
            ("af", "Afrikaans"), ("ar", "Arabic"), ("hy", "Armenian"), ("az", "Azerbaijani"),
            ("be", "Belarusian"), ("bs", "Bosnian"), ("bg", "Bulgarian"), ("ca", "Catalan"),
            ("zh", "Chinese"), ("hr", "Croatian"), ("cs", "Czech"), ("da", "Danish"),
            ("nl", "Dutch"), ("en", "English"), ("et", "Estonian"), ("fi", "Finnish"),
            ("fr", "French"), ("gl", "Galician"), ("de", "German"), ("el", "Greek"),
            ("he", "Hebrew"), ("hi", "Hindi"), ("hu", "Hungarian"), ("is", "Icelandic"),
            ("id", "Indonesian"), ("it", "Italian"), ("ja", "Japanese"), ("kn", "Kannada"),
            ("kk", "Kazakh"), ("ko", "Korean"), ("lv", "Latvian"), ("lt", "Lithuanian"),
            ("mk", "Macedonian"), ("ms", "Malay"), ("mr", "Marathi"), ("mi", "Maori"),
            ("ne", "Nepali"), ("no", "Norwegian"), ("fa", "Persian"), ("pl", "Polish"),
            ("pt", "Portuguese"), ("ro", "Romanian"), ("ru", "Russian"), ("sr", "Serbian"),
            ("sk", "Slovak"), ("sl", "Slovenian"), ("es", "Spanish"), ("sw", "Swahili"),
            ("sv", "Swedish"), ("tl", "Tagalog"), ("ta", "Tamil"), ("th", "Thai"),
            ("tr", "Turkish"), ("uk", "Ukrainian"), ("ur", "Urdu"), ("vi", "Vietnamese"),
            ("cy", "Welsh"),
        ]
        for (code, title) in singles.sorted(by: { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }) {
            list.append(Option(id: code, title: title, openAICodes: [code]))
        }
        return list
    }()

    /// Shown on home Voice connection row (menu, not segmented tabs).
    static let homeMenuOptions: [Option] = {
        let preferred = ["auto", "es-en", "es", "en", "fr", "de", "it", "pt"]
        var ordered: [Option] = []
        for id in preferred {
            if let o = options.first(where: { $0.id == id }) { ordered.append(o) }
        }
        let rest = options.filter { o in !preferred.contains(o.id) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return ordered + rest
    }()

    static func resolve(stored raw: String?) -> Option {
        let key = raw ?? ""
        if let legacy = migrateLegacy(key) { return legacy }
        return options.first { $0.id == key } ?? options.first { $0.id == "es-en" }!
    }

    private static func migrateLegacy(_ raw: String) -> Option? {
        switch raw {
        case "spanishEnglish": return options.first { $0.id == "es-en" }
        case "spanish": return options.first { $0.id == "es" }
        case "english": return options.first { $0.id == "en" }
        case "auto": return options.first { $0.id == "auto" }
        default: return nil
        }
    }
}
