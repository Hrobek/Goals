//
//  Profile.swift
//  Goals
//

import Foundation
import Observation

/// The app-side view of `LocalProfile`: a stable owner id for every query, and the editable
/// nickname shown at the top of Settings. No accounts, no sign-in; the id is minted on first
/// launch and never changes.
@MainActor
@Observable
final class Profile {
    let id: UUID

    var nickname: String {
        didSet {
            guard nickname != oldValue else { return }
            LocalProfile.setNickname(nickname)
        }
    }

    init() {
        id = LocalProfile.resolveId()
        nickname = LocalProfile.nickname
    }
}
