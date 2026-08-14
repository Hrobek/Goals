//
//  AuthenticatedUser.swift
//  Goals
//

import Foundation
import CryptoKit

enum AuthProviderKind: String, Codable {
    case apple, email, google
}

struct AuthenticatedUser: Codable, Identifiable, Equatable {
    var id: UUID
    var displayName: String
    var email: String?
    var provider: AuthProviderKind
}

extension UUID {
    /// Derives a stable UUID from a provider's own account identifier, so signing in twice on the
    /// same device yields the same user instead of a fresh random id every time.
    static func stable(for identifier: String) -> UUID {
        var digest = Array(SHA256.hash(data: Data(identifier.utf8)).prefix(16))
        // Shape the bytes like a v5 (name-based) UUID.
        digest[6] = (digest[6] & 0x0F) | 0x50
        digest[8] = (digest[8] & 0x3F) | 0x80
        return UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        ))
    }
}
