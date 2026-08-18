//
//  FeedbackReport.swift
//  Goals
//

import Foundation
import UIKit

enum FeedbackKind: String, CaseIterable, Identifiable {
    case bug, idea, other

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .bug: String(localized: "feedback.kind.bug", defaultValue: "Bug", bundle: AppLanguage.currentBundle)
        case .idea: String(localized: "feedback.kind.idea", defaultValue: "Idea", bundle: AppLanguage.currentBundle)
        case .other: String(localized: "feedback.kind.other", defaultValue: "Other", bundle: AppLanguage.currentBundle)
        }
    }

    /// Kept out of the String Catalog on purpose: this lands in the mail subject, which the
    /// developer reads — it shouldn't change language with the sender's app settings.
    var subjectTag: String {
        switch self {
        case .bug: "Bug"
        case .idea: "Idea"
        case .other: "Feedback"
        }
    }
}

enum SupportContact {
    /// The app's own address, kept out of anyone's personal inbox: it shows in the "To" field of the
    /// mail the user sends, and on screen in the support page when Mail isn't set up.
    static let email = "goals.app.support@gmail.com"
}

struct FeedbackAttachment: Identifiable, Equatable {
    let id = UUID()
    let data: Data
    let filename: String
    let mimeType: String
    let isVideo: Bool
    let preview: UIImage?

    var byteCount: Int { data.count }
}

struct FeedbackReport {
    var kind: FeedbackKind
    var message: String

    var subject: String {
        "[Goals] \(kind.subjectTag) – v\(Diagnostics.appVersion) (\(Diagnostics.build))"
    }

    var body: String {
        """
        \(message.trimmingCharacters(in: .whitespacesAndNewlines))

        ---
        \(Diagnostics.summary)
        """
    }
}

/// Device and build facts attached to every report so a bug can be reproduced. Deliberately
/// impersonal — no goals, no account, nothing the user didn't type.
enum Diagnostics {
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return Mirror(reflecting: info.machine).children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
    }

    static var summary: String {
        """
        App: \(appVersion) (\(build))
        iOS: \(UIDevice.current.systemVersion)
        Device: \(deviceModel)
        App language: \(AppLanguage.current.rawValue)
        System locale: \(Locale.current.identifier)
        """
    }
}
