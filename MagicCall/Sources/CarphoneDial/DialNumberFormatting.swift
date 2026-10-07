import Foundation

/// Mirrors `PhoneKeyboard.configureFormat` for settings previews (full sample length).
enum DialNumberFormatting {
    /// Long sample for format / preload previews (US-length numbers).
    static let sampleDigits = "5551234567"
    /// Short sample so entry-order previews read as 1→2→3… vs 6→5→4…
    static let orderPreviewDigits = "123456"

    static let formatPatternExamples: [(pattern: String, note: String)] = [
        ("xxx-xxx-xxxx", "555-123-4567"),
        ("(xxx) xxx-xxxx", "(555) 123-4567"),
        ("xxx xxx xxxx", "555 123 4567"),
        ("xxx xxx xx xx", "555 123 45 67"),
    ]

    static func formatted(phone: String, pattern: String, isReverse: Bool) -> String {
        guard !pattern.isEmpty else {
            return phone
        }
        var phoneAux = phone
        if isReverse {
            for (i, char) in pattern.reversed().enumerated() {
                if char.lowercased() != "x", phoneAux.count > i {
                    let index = phoneAux.index(phoneAux.startIndex, offsetBy: phoneAux.count - i)
                    phoneAux.insert(char, at: index)
                }
            }
            return balanceParentheses(phoneAux)
        }
        for (i, char) in pattern.enumerated() {
            if char.lowercased() != "x", phoneAux.count > i {
                let index = phoneAux.index(phoneAux.startIndex, offsetBy: i)
                phoneAux.insert(char, at: index)
            }
        }
        return balanceParentheses(phoneAux)
    }

    /// Digits visible on the dial after `entryCount` finger cues (matches `digitPressed` / sendFirst|Last).
    static func partialEntry(digits: String, entryCount: Int, isReverse: Bool) -> String {
        guard entryCount > 0 else {
            return ""
        }
        let chars = Array(digits)
        let n = min(entryCount, chars.count)
        if isReverse {
            var result = ""
            for i in 0..<n {
                result = String(chars[chars.count - 1 - i]) + result
            }
            return result
        }
        return String(chars.prefix(n))
    }

    /// First `count` digits auto-typed when the dial appears (`preloadDigits`), formatted.
    static func preloadedDisplay(digits: String, count: Int, pattern: String, isReverse: Bool) -> String {
        guard count >= 2 else {
            return ""
        }
        let raw = partialEntry(digits: digits, entryCount: count, isReverse: isReverse)
        return formatted(phone: raw, pattern: pattern, isReverse: isReverse)
    }

    private static func balanceParentheses(_ string: String) -> String {
        var value = string
        let open = value.contains("(")
        let close = value.contains(")")
        switch (open, close) {
        case (true, false):
            value.insert(")", at: value.endIndex)
        case (false, true):
            value.insert("(", at: value.startIndex)
        default:
            break
        }
        return value
    }
}
