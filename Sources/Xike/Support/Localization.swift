import Foundation

enum XikeText {
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        let localized = NSLocalizedString(key, bundle: .main, comment: "")
        return String(format: localized, arguments: arguments)
    }
}

extension String {
    var xikeLocalized: String {
        String(localized: String.LocalizationValue(self))
    }
}
