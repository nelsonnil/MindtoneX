import Foundation

/// Live dial display formatting — aligned with the iOS Phone keypad for the device region.
enum CarphoneDialFormat {
    static func digitsOnly(_ raw: String) -> String {
        raw.filter { $0.isNumber || $0 == "+" || $0 == "*" || $0 == "#" }
    }

    /// Legacy `xxx` pattern for Carphone preload / reverse routines.
    static func patternForDeviceRegion() -> String {
        switch WordApiSettings.dialDisplayRegionISO.uppercased() {
        case "US", "CA", "PR", "DO":
            return "(xxx) xxx-xxxx"
        default:
            return "xxx xxx xxx"
        }
    }

    /// Formats digits while typing (national layout). Most regions use **spaces only** (ES, GB, …).
    static func liveDisplay(_ rawDigits: String) -> String {
        let digits = rawDigits.filter(\.isNumber)
        guard !digits.isEmpty else { return rawDigits.filter { $0 == "+" || $0 == "*" || $0 == "#" } }

        let formatted: String
        if usesNorthAmericanPunctuation(digits: digits) {
            formatted = formatNANP(digits)
        } else {
            formatted = groupedByThree(digits)
        }

        return preserveDialSymbols(rawDigits, formattedDigits: formatted)
    }

    /// US/CA-style `(415) 555-0123` only when region and digit count match NANP — not for 9-digit ES mobiles.
    private static func usesNorthAmericanPunctuation(digits: String) -> Bool {
        let region = WordApiSettings.dialDisplayRegionISO.uppercased()
        guard ["US", "CA", "PR", "DO"].contains(region) else { return false }
        if digits.count == 9, ["6", "7", "9"].contains(String(digits.prefix(1))) {
            return false
        }
        return digits.count >= 10 || digits.count == 7
    }

    // MARK: - Private

    private static func groupedByThree(_ digits: String) -> String {
        var parts: [String] = []
        var index = digits.startIndex
        while index < digits.endIndex {
            let end = digits.index(index, offsetBy: 3, limitedBy: digits.endIndex) ?? digits.endIndex
            parts.append(String(digits[index..<end]))
            index = end
        }
        return parts.joined(separator: " ")
    }

    /// North American `(415) 555-0123` while typing.
    private static func formatNANP(_ digits: String) -> String {
        let d = String(digits.prefix(10))
        var out = ""
        for (offset, character) in d.enumerated() {
            switch offset {
            case 0: out += "("
            case 3: out += ") "
            case 6: out += "-"
            default: break
            }
            out.append(character)
        }
        if digits.count > 10 {
            out += " " + String(digits.dropFirst(10))
        }
        return out
    }

    private static func preserveDialSymbols(_ raw: String, formattedDigits: String) -> String {
        guard raw.contains("+") || raw.contains("*") || raw.contains("#") else {
            return formattedDigits
        }
        var prefix = ""
        for character in raw {
            if character.isNumber { break }
            prefix.append(character)
        }
        return prefix + formattedDigits
    }
}
