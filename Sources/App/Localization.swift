// In-app language switch: strings come from en.lproj / vi.lproj Localizable.strings
// of the chosen language, so changing the language redraws the UI immediately.

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case en, vi
    var id: String { rawValue }
    var displayName: String { self == .en ? "English" : "Tiếng Việt" }
    var locale: Locale { Locale(identifier: self == .en ? "en_US" : "vi_VN") }
}

struct Strings {
    let language: AppLanguage
    private let bundle: Bundle

    init(_ language: AppLanguage) {
        self.language = language
        bundle = Bundle.main.path(forResource: language.rawValue, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }

    func callAsFunction(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    func callAsFunction(_ key: String, _ args: CVarArg...) -> String {
        String(format: callAsFunction(key), locale: language.locale, arguments: args)
    }
}
