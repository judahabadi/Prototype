import Foundation

enum Language: String, CaseIterable, Identifiable, Codable {
    case hebrew, arabic, mandarin, spanish, english,
         hindi, portuguese, bengali, russian, japanese,
         french, german

    var id: String { rawValue }

    var isoCode: String {
        switch self {
        case .hebrew: return "he"
        case .arabic: return "ar"
        case .mandarin: return "zh"
        case .spanish: return "es"
        case .english: return "en"
        case .hindi: return "hi"
        case .portuguese: return "pt"
        case .bengali: return "bn"
        case .russian: return "ru"
        case .japanese: return "ja"
        case .french: return "fr"
        case .german: return "de"
        }
    }

    // Apple Translation framework uses more specific BCP-47 tags for some languages
    var appleTranslationLocale: String {
        switch self {
        case .mandarin: return "zh-Hans"   // Apple ships Simplified; use zh-Hant for Traditional
        case .portuguese: return "pt-BR"   // Apple ships Brazilian Portuguese
        case .english: return "en-US"
        default: return isoCode
        }
    }

    var isRTL: Bool {
        switch self {
        case .hebrew, .arabic: return true
        default: return false
        }
    }

    var displayName: String {
        switch self {
        case .hebrew: return "Hebrew"
        case .arabic: return "Arabic"
        case .mandarin: return "Mandarin"
        case .spanish: return "Spanish"
        case .english: return "English"
        case .hindi: return "Hindi"
        case .portuguese: return "Portuguese"
        case .bengali: return "Bengali"
        case .russian: return "Russian"
        case .japanese: return "Japanese"
        case .french: return "French"
        case .german: return "German"
        }
    }

    var nativeName: String {
        switch self {
        case .hebrew: return "עברית"
        case .arabic: return "العربية"
        case .mandarin: return "中文"
        case .spanish: return "Español"
        case .english: return "English"
        case .hindi: return "हिन्दी"
        case .portuguese: return "Português"
        case .bengali: return "বাংলা"
        case .russian: return "Русский"
        case .japanese: return "日本語"
        case .french: return "Français"
        case .german: return "Deutsch"
        }
    }

    var flag: String {
        switch self {
        case .hebrew: return "🇮🇱"
        case .arabic: return "🇸🇦"
        case .mandarin: return "🇨🇳"
        case .spanish: return "🇪🇸"
        case .english: return "🇬🇧"
        case .hindi: return "🇮🇳"
        case .portuguese: return "🇵🇹"
        case .bengali: return "🇧🇩"
        case .russian: return "🇷🇺"
        case .japanese: return "🇯🇵"
        case .french: return "🇫🇷"
        case .german: return "🇩🇪"
        }
    }

    func jsonFileName(to target: Language) -> String {
        "translations_\(isoCode)_\(target.isoCode)"
    }
}

enum AppGroup {
    static let id = "group.harrykhizer.ProtoType"
    static let nativeKey = "nativeLanguage"
    static let targetKey = "targetLanguage"
    static let onboardingDismissedKey = "onboardingDismissed"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: id) ?? .standard
    }
}
