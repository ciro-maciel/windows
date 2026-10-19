import Foundation

/// The interface language follows the Mac: Brazilian Portuguese when the first preferred
/// language is Portuguese, English otherwise. No switch inside the app.
/// The text lives in Resources/<lang>.lproj/Localizable.strings; a key missing from the
/// Portuguese table falls back to the English one, never to the key itself.
enum Lang {
    static let isPortuguese: Bool = (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("pt")

    private static func table(_ name: String) -> Bundle? {
        Bundle.main.path(forResource: name, ofType: "lproj").flatMap(Bundle.init(path:))
    }

    private static let english = table("en")
    private static let chosen = isPortuguese ? (table("pt-BR") ?? english) : english

    /// Marks a missing key: no real string is a single NUL.
    private static let missing = "\u{0}"

    static func text(_ key: String) -> String {
        if let s = chosen?.localizedString(forKey: key, value: missing, table: nil), s != missing { return s }
        if let s = english?.localizedString(forKey: key, value: missing, table: nil), s != missing { return s }
        return key
    }
}

/// The interface text for `key`, in the app's language.
func L(_ key: String) -> String { Lang.text(key) }

/// The interface text for `key` with `String(format:)` arguments (%@, %d), in the app's language.
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: Lang.text(key), locale: Locale.current, arguments: args)
}
