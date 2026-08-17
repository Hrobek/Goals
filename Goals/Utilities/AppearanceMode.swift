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

    #if canImport(UIKit)
    /// The same choice in UIKit's terms. `preferredColorScheme` only reaches what SwiftUI draws
    /// itself — anything UIKit renders on its own (the text a password field shows after AutoFill
    /// fills it, the keyboard, the AutoFill accessory) reads the window's style instead, and a
    /// window left in light mode paints that text near-black on the app's dark ground.
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    /// Pushes the choice onto every window of the app.
    @MainActor
    static func applyToWindows(_ mode: AppearanceMode) {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = mode.interfaceStyle
            }
        }
    }
    #endif
}
