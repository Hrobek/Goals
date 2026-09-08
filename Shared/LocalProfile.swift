//
//  LocalProfile.swift
//  Goals
//

import Foundation

/// The single local identity every stored row is scoped to. There are no accounts and no sign-in
/// any more, just a device-generated id (so the existing `ownerId == ...` queries keep working
/// unchanged) and a nickname the user can edit in Settings.
///
/// Lives in the App Group so the widget extension resolves the same id the app does. The id is
/// created once, by the app, on first launch; the widget only ever reads it.
enum LocalProfile {
    private static let idKey = "Goals.localProfile.id"
    private static let nicknameKey = "Goals.localProfile.nickname"

    /// Pre-nickname identity blob (`{ id, displayName, email, provider }`) written by the retired
    /// account system, under this exact key. Read once by `resolveId()` so a user who already had
    /// data keeps it instead of starting empty under a fresh id.
    private static let legacyAccountKey = "Goals.currentUser"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: SharedStore.appGroupID) }

    /// The stored id, or `nil` if the app has never run since this shipped. The widget treats
    /// `nil` as "open the app once" rather than "no goals".
    static var currentUserId: UUID? {
        guard let string = defaults?.string(forKey: idKey) else { return nil }
        return UUID(uuidString: string)
    }

    /// Empty until the user sets one. Trimmed on the way in.
    static var nickname: String {
        defaults?.string(forKey: nicknameKey) ?? ""
    }

    static func setNickname(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults?.set(trimmed, forKey: nicknameKey)
    }

    /// Called once at launch, before any `@Query` runs. Returns the existing id; failing that,
    /// adopts the id (and name) from the retired account blob so a signed-in user's data stays
    /// visible; failing that, mints a fresh one.
    @discardableResult
    static func resolveId() -> UUID {
        if let existing = currentUserId { return existing }

        let legacy = legacyAccount()
        let id = legacy?.id ?? UUID()
        defaults?.set(id.uuidString, forKey: idKey)

        if nickname.isEmpty, let name = legacy?.displayName, !name.isEmpty {
            setNickname(name)
        }
        return id
    }

    private struct LegacyAccount: Decodable {
        var id: UUID
        var displayName: String?
    }

    /// Reads the retired blob from the App Group, then from `UserDefaults.standard` where an even
    /// older build kept it before the App Group existed.
    private static func legacyAccount() -> LegacyAccount? {
        let data = defaults?.data(forKey: legacyAccountKey)
            ?? UserDefaults.standard.data(forKey: legacyAccountKey)
        guard let data else { return nil }
        return try? JSONDecoder().decode(LegacyAccount.self, from: data)
    }
}
