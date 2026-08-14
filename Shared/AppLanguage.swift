//
//  AppLanguage.swift
//  Goals
//

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case en, cs

    static let storageKey = "Goals.appLanguage"

    var id: String { rawValue }

    /// Written in the language itself, so it stays legible no matter what language is currently active.
    var localizedName: String {
        switch self {
        case .en: "English"
        case .cs: "Čeština"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }

    /// Used until the user picks a language: the device language when the app ships it, English otherwise.
    static var deviceDefault: AppLanguage {
        let code = Locale.preferredLanguages.first
            .flatMap { Locale(identifier: $0).language.languageCode?.identifier } ?? ""
        return AppLanguage(rawValue: code) ?? .en
    }

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .deviceDefault
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
