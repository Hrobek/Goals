//
//  LocalProfile.swift
//  Goals
//

import Foundation
import Security

/// The single local identity every stored row is scoped to. There are no accounts and no sign-in
/// any more, just a device-generated id (so the existing `ownerId == ...` queries keep working
/// unchanged) and a nickname the user can edit in Settings.
///
/// Lives in the App Group so the widget extension resolves the same id the app does. The id is
/// created once, by the app, on first launch; the widget only ever reads it.
///
/// The id is *also* mirrored into the Keychain, which — unlike the App Group's `UserDefaults` —
/// survives deleting and reinstalling the app. Without that, every `Habit`/`Goal` row still comes
/// back down from iCloud sync after a reinstall (CloudKit mirrors the whole private database, not
/// per-owner), but a freshly-minted random id would never match their `ownerId`, so they'd sit in
/// the local store invisible to every `ownerId == ...` query forever. Keychain items are included
/// in an encrypted device backup/restore too, since `.afterFirstUnlock` isn't a "this device only"
/// accessibility class.
///
/// `nonisolated`: it's all UserDefaults/Keychain reads, no main-actor state — so the nonisolated
/// `WatchConnectivityBridge` can resolve the id without an isolation mismatch.
nonisolated enum LocalProfile {
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

    #if os(watchOS)
    /// The watch has no launch flow that mints an id — it's pushed from the iPhone over
    /// WatchConnectivity (see `WatchConnectivityBridge`) and cached here so every `ownerId == …`
    /// query resolves the same identity the phone uses.
    static func applyPushedIdentity(id: UUID, nickname: String) {
        defaults?.set(id.uuidString, forKey: idKey)
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            defaults?.set(trimmed, forKey: nicknameKey)
        }
    }
    #endif

    /// Called once at launch, before any `@Query` runs. Returns the existing id; failing that,
    /// restores it from the Keychain (a reinstall after deleting the app - the App Group's
    /// `UserDefaults` is gone, but the Keychain entry isn't); failing that, adopts the id (and
    /// name) from the retired account blob so a signed-in user's data stays visible; failing all
    /// of that, mints a fresh one.
    @discardableResult
    static func resolveId() -> UUID {
        if let existing = currentUserId { return existing }

        if let restored = keychainReadId() {
            defaults?.set(restored.uuidString, forKey: idKey)
            return restored
        }

        let legacy = legacyAccount()
        let id = legacy?.id ?? UUID()
        defaults?.set(id.uuidString, forKey: idKey)
        keychainWriteId(id)

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

    // MARK: - Keychain

    private static let keychainService = "com.hrobek.goals.identity"
    private static let keychainAccount = "localProfileId"

    private static func keychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
    }

    private static func keychainReadId() -> UUID? {
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return UUID(uuidString: string)
    }

    /// Upserts rather than assuming the item doesn't exist yet - a device restore from an
    /// encrypted backup can bring an old entry back before this code ever runs `SecItemAdd` again.
    private static func keychainWriteId(_ id: UUID) {
        let data = Data(id.uuidString.utf8)
        let updateStatus = SecItemUpdate(keychainQuery() as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard updateStatus == errSecItemNotFound else { return }

        var addQuery = keychainQuery()
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(addQuery as CFDictionary, nil)
    }
}
