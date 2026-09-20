//
//  HealthSyncStatus.swift
//  Goals
//

import Foundation

/// When Health last synced, mirrored into the App Group the same way `ProEntitlement` mirrors the
/// Pro flag - so the Health settings screen has something to show without asking
/// `HealthKitSyncEngine` (which the settings screen, living in `Goals/`, could call directly, but
/// this keeps the read side as plain as `ProEntitlement`'s).
enum HealthSyncStatus {
    private static let key = "Goals.healthLastSyncedAt"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: SharedStore.appGroupID)
    }

    static var lastSyncDate: Date? {
        get { defaults?.object(forKey: key) as? Date }
        set { defaults?.set(newValue, forKey: key) }
    }
}
