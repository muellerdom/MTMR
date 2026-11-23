import Foundation

enum DisplayName {
    static let builtIn = "MacBook"

    /// Shortens a display name for a Touch Bar label: whole words, at most `maxLength` characters,
    /// but always at least the first word. "DELL U2720Q" stays, "Built-in Retina Display" becomes "Built-in".
    static func short(_ name: String, maxLength: Int = 12) -> String {
        var result = ""
        for word in name.split(separator: " ") {
            let candidate = result.isEmpty ? String(word) : result + " " + word
            if !result.isEmpty, candidate.count > maxLength { break }
            result = candidate
        }
        return result.isEmpty ? name : result
    }

    /// A few characters for the collapsed Touch Bar label: "P27h-30" becomes "P27h…".
    static func abbreviated(_ name: String, maxLength: Int = 4) -> String {
        name.count <= maxLength + 1 ? name : name.prefix(maxLength) + "…"
    }
}
