import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    static let defaultsKey = "appLanguage"

    var id: String { rawValue }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    var selectionLabel: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }

    static func resolved(
        defaults: UserDefaults = .standard,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> AppLanguage {
        if let stored = defaults.string(forKey: defaultsKey),
           let language = AppLanguage(rawValue: stored) {
            return language
        }
        let preferred = preferredLanguages.first?.lowercased() ?? ""
        let usesSimplifiedChinese = preferred.hasPrefix("zh-hans") ||
            preferred.hasPrefix("zh-cn") || preferred.hasPrefix("zh-sg")
        return usesSimplifiedChinese ? .simplifiedChinese : .english
    }
}

struct AppStrings {
    let language: AppLanguage
    private let localizedBundle: Bundle

    init(language: AppLanguage, bundle: Bundle = .main) {
        self.language = language
        if let resourceURL = bundle.url(
            forResource: language.rawValue,
            withExtension: "lproj"
        ), let languageBundle = Bundle(url: resourceURL) {
            localizedBundle = languageBundle
        } else {
            localizedBundle = bundle
        }
    }

    func text(_ key: String) -> String {
        localizedBundle.localizedString(forKey: key, value: key, table: nil)
    }

    func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: text(key),
            locale: language.locale,
            arguments: arguments
        )
    }

    func captureError(_ error: Error) -> String {
        if let captureError = error as? ClipboardCaptureError {
            switch captureError {
            case let .tooLarge(bytes):
                let size = ByteCountFormatter.string(
                    fromByteCount: Int64(bytes),
                    countStyle: .file
                )
                return format("error.clipboard_too_large", size)
            case .noSupportedContent:
                return text("error.no_supported_content")
            }
        }
        return format("error.capture_failed", error.localizedDescription)
    }
}
