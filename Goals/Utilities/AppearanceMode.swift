//
//  AppearanceMode.swift
//  Goals
//

import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "Goals.appearanceMode"

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
