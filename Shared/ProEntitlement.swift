//
//  ProEntitlement.swift
//  Goals
//

import Foundation

/// The Pro flag, mirrored into the App Group so the widget extension can gate its Pro-only
/// widgets. The widget can't ask StoreKit itself — entitlement checks are async and a timeline
/// provider has to answer straight away — so the app writes the answer down after every
/// entitlement refresh and the widget reads it back.
enum ProEntitlement {
    private static let key = "Goals.isProUnlocked"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: SharedStore.appGroupID)
    }

    static var isUnlocked: Bool {
        get { defaults?.bool(forKey: key) ?? false }
        set { defaults?.set(newValue, forKey: key) }
    }
}
