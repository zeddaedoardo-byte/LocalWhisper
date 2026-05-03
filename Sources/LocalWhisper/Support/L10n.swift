import Foundation

enum L10n {
    static let languageCode: String = {
        let primary = Locale.preferredLanguages.first?
            .replacingOccurrences(of: "_", with: "-")
            .lowercased() ?? "en"
        return primary == "it" || primary.hasPrefix("it-") ? "it" : "en"
    }()

    static var locale: Locale {
        Locale(identifier: languageCode)
    }

    private static var localizedBundle: Bundle {
        guard let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }

    static func string(_ key: String) -> String {
        localizedBundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: locale, arguments: arguments)
    }
}
