import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case russian = "ru"
    case english = "en"

    var id: Self { self }

    /// Each language is shown in its own name so it is recognisable from either UI.
    var title: String {
        switch self {
        case .russian: return "Русский"
        case .english: return "English"
        }
    }

    static var systemDefault: AppLanguage {
        Locale.preferredLanguages.first?.hasPrefix("ru") == true ? .russian : .english
    }
}

/// Two-language string picker used across the UI: `t("Обзор", "Overview")`.
struct Localizer: Sendable {
    let language: AppLanguage

    func callAsFunction(_ russian: String, _ english: String) -> String {
        language == .russian ? russian : english
    }
}
