//
//  AppearanceMode.swift
//  Goals
//

import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "Goals.appearanceMode"

    /// What the app looks like until someone says otherwise. Dark rather than `.system`: the whole
    /// design — the card-on-black lists, the goal colours, the activity grids — was drawn against a
    /// dark background, and it's what the app should introduce itself in.
    static let `default` = AppearanceMode.dark

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .system: String(localized: "appearance.system", defaultValue: "System", bundle: AppLanguage.currentBundle)
        case .light: String(localized: "appearance.light", defaultValue: "Light", bundle: AppLanguage.currentBundle)
        case .dark: String(localized: "appearance.dark", defaultValue: "Dark", bundle: AppLanguage.currentBundle)
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
