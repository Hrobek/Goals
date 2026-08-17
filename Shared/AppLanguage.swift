//
//  AppLanguage.swift
//  Goals
//

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    // Raw values are `.lproj` folder names, which is what `currentBundle` looks up.
    case en, cs, de, es, fr
    case ptBR = "pt-BR"

    static let storageKey = "Goals.appLanguage"

    var id: String { rawValue }

    /// Written in the language itself, so it stays legible no matter what language is currently active.
    var localizedName: String {
        switch self {
        case .en: "English"
        case .cs: "Čeština"
        case .de: "Deutsch"
        case .es: "Español"
        case .fr: "Français"
        case .ptBR: "Português (Brasil)"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }

    /// Used until the user picks a language: the device language when the app ships it, English otherwise.
    static var deviceDefault: AppLanguage {
        let code = Locale.preferredLanguages.first
            .flatMap { Locale(identifier: $0).language.languageCode?.identifier } ?? ""
        // Matched on the language code alone, so a device set to European Portuguese or Swiss German
        // still lands on the closest shipped translation rather than falling back to English.
        return allCases.first { $0.rawValue.hasPrefix(code) && !code.isEmpty } ?? .en
    }

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: SharedStore.appGroupID)
    }

    /// The picker writes to `UserDefaults.standard`, and the widget extension has its own copy of
    /// that — which is why widgets used to ignore the in-app language and follow the system. The
    /// app's own domain is still read first: it's updated the instant the picker moves, while the
    /// shared copy is mirrored a beat later.
    static var current: AppLanguage {
        let raw = UserDefaults.standard.string(forKey: storageKey)
            ?? sharedDefaults?.string(forKey: storageKey)
            ?? ""
        return AppLanguage(rawValue: raw) ?? .deviceDefault
    }

    /// Copies the language the app is actually running in into the App Group. It mirrors the
    /// device default too, not just an explicit pick: otherwise a reinstall leaves the app back on
    /// the device language while the shared copy still names the old choice, and the widgets end up
    /// speaking a different language than the app. Returns whether anything changed, so the caller
    /// only redraws widgets when there's a reason to.
    @discardableResult
    static func syncSharedCopy() -> Bool {
        let value = UserDefaults.standard.string(forKey: storageKey) ?? deviceDefault.rawValue
        guard sharedDefaults?.string(forKey: storageKey) != value else { return false }
        sharedDefaults?.set(value, forKey: storageKey)
        return true
    }

    /// The `.lproj` bundle for the selected language. SwiftUI `Text` picks its localization from the
    /// environment locale, but `String(localized:)` outside a view does not — those call sites pass
    /// this bundle explicitly so both paths follow the in-app language override.
    static var currentBundle: Bundle {
        guard let path = Bundle.main.path(forResource: current.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}
