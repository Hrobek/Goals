//
//  GoogleAuthConfiguration.swift
//  Goals
//

import Foundation

/// Where the Google OAuth client ID comes from. Nothing is hardcoded — drop the OAuth client
/// plist from Google Cloud Console into the `Goals/` source folder (synchronized folders pick it
/// up automatically; the repo root does *not* work), or set `GIDClientID` in Info.plist.
struct GoogleAuthConfiguration {
    private static let clientIDSuffix = ".apps.googleusercontent.com"

    let clientID: String

    /// Google's convention for native redirect URIs: the client ID with its components reversed.
    var reversedClientID: String {
        "com.googleusercontent.apps." + clientID.replacingOccurrences(of: Self.clientIDSuffix, with: "")
    }

    var redirectURI: String {
        "\(reversedClientID):/oauth2redirect"
    }

    init?(clientID: String?) {
        guard let clientID, clientID.hasSuffix(Self.clientIDSuffix) else { return nil }
        self.clientID = clientID
    }

    static var current: GoogleAuthConfiguration? {
        // Google Cloud Console downloads the file as `client_<id>.apps.googleusercontent.com.plist`,
        // Firebase calls the same thing `GoogleService-Info.plist` — so take whichever bundled
        // plist carries a CLIENT_ID instead of insisting on one filename.
        let bundledPlists = Bundle.main.urls(forResourcesWithExtension: "plist", subdirectory: nil) ?? []
        for url in bundledPlists {
            guard let values = NSDictionary(contentsOf: url) as? [String: Any],
                  let configuration = GoogleAuthConfiguration(clientID: values["CLIENT_ID"] as? String) else { continue }
            return configuration
        }
        return GoogleAuthConfiguration(clientID: Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String)
    }
}
