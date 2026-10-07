import Foundation

/// Live dial display formatting — aligned with the iOS Phone keypad for the device region.
enum CarphoneDialFormat {
    static func digitsOnly(_ raw: String) -> String {
        raw.filter { $0.isNumber || $0 == "+" || $0 == "*" || $0 == "#" }
    }

    /// Legacy `xxx` pattern for Carphone preload / reverse routines.
    static func patternForDeviceRegion() -> String {
        switch WordApiSettings.deviceRegionISO.uppercased() {
        case "ES":
            return "xxx xxx xxx"
        case "US", "CA", "PR", "DO":
            return "(xxx) xxx-xxxx"
        case "GB", "UK":
            return "xxxx xxx xxxx"
        case "FR":
            return "xx xx xx xx xx"
        case "DE":
            return "xxxx xxxxxxx"
        case "IT":
            return "xxx xxx xxxx"
        case "PT":
            return "xxx xxx xxx"
        case "MX":
            return "xx xx xx xx xx"
        default:
            return "xxx xxx xxxx"
        }
    }

    /// Formats digits while typing (national layout, no country code).
    static func liveDisplay(_ rawDigits: String) -> String {
        let digits = rawDigits.filter(\.isNumber)
        guard !digits.isEmpty else { return rawDigits.filter { $0 == "+" || $0 == "*" || $0 == "#" } }

        let region = WordApiSettings.deviceRegionISO.uppercased()
        let formatted: String
        switch region {
        case "ES", "PT":
            formatted = grouped(digits, sizes: [3, 3, 3])
        case "US", "CA", "PR", "DO":
            formatted = formatNANP(digits)
        case "GB", "UK":
            formatted = grouped(digits, sizes: [4, 3, 4])
        case "FR", "MX":
            formatted = grouped(digits, sizes: [2, 2, 2, 2, 2])
        case "DE":
            formatted = grouped(digits, sizes: [4, 7])
        case "IT":
            formatted = grouped(digits, sizes: [3, 3, 4])
        default:
            formatted = groupedByThree(digits)
        }

        return preserveDialSymbols(rawDigits, formattedDigits: formatted)
    }

    // MARK: - Private

    private static func grouped(_ digits: String, sizes: [Int]) -> String {
        var parts: [String] = []
        var index = digits.startIndex
        for size in sizes {
            guard index < digits.endIndex else { break }
            let end = digits.index(index, offsetBy: size, limitedBy: digits.endIndex) ?? digits.endIndex
            parts.append(String(digits[index..<end]))
            index = end
        }
        if index < digits.endIndex {
            parts.append(String(digits[index...]))
        }
        return parts.joined(separator: " ")
    }

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
