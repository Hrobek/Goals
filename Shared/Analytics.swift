//
//  Analytics.swift
//  Goals
//

import Foundation

/// The events the app reports. The question analytics is here to answer is where people drop off
/// before buying Pro — not what they track — so the list stays short and deliberate.
enum AnalyticsEvent: String {
    case goalCreated = "goal_created"
    case goalCompleted = "goal_completed"
    case checkInLogged = "checkin_logged"
    case limitAlertShown = "limit_alert_shown"
    case paywallOpened = "paywall_opened"
    case purchaseAttempted = "purchase_attempted"
    case purchaseCompleted = "purchase_completed"
    case feedbackSent = "feedback_sent"
}

/// The keys an event may carry, as a closed set. The app promises that nothing a user typed leaves
/// the device — goal titles, notes, category and unit names, feedback text — and a fixed key list
/// makes that something the compiler helps hold up, instead of a rule to remember at every call.
enum AnalyticsParameter: String {
    case trackingMode = "Goal.trackingMode"
    case priority = "Goal.priority"
    case hasDeadline = "Goal.hasDeadline"
    case source = "Signal.source"
    case feedbackKind = "Feedback.kind"
}

/// Anonymous product analytics, sent straight to TelemetryDeck's ingest API.
///
/// No SDK on purpose — it's one POST with a small JSON body, and the same reason Google Sign-In is
/// hand-rolled here applies: fewer dependencies, and every byte that leaves the device is visible
/// in this file. Everything goes through `send`, so switching to the official SDK later means
/// rewriting one function.
enum Analytics {
    private static let appID = "BCAC6291-5AD3-4386-BC95-515CEF2ED557"

    /// The organization's TelemetryDeck namespace (Dashboard → organization settings). The v2
    /// ingest endpoint is namespaced and there is no default, so an empty value here means nothing
    /// is sent — the app works, the dashboard just stays empty.
    private static let namespace = "com.hrobek"

    /// Simulator and debug runs would otherwise show up as real users. TelemetryDeck keeps test
    /// signals out of production queries.
    private static var isTestMode: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private static let optOutKey = "Goals.analyticsOptOut"
    private static let installIDKey = "Goals.analyticsInstallID"

    /// The App Group, so the widget extension reports under the same install and honours the same
    /// opt-out as the app.
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: SharedStore.appGroupID)
    }

    /// Stored inverted — as an opt-*out* — so a fresh install is enabled without having to seed
    /// anything, and `bool(forKey:)`'s default of `false` means the right thing.
    static var isEnabled: Bool {
        get { !(defaults?.bool(forKey: optOutKey) ?? false) }
        set { defaults?.set(!newValue, forKey: optOutKey) }
    }

    /// A random per-install identifier, not derived from the signed-in account. TelemetryDeck wants
    /// something stable to count returning users with; anything tied to identity would say more
    /// than counting needs.
    private static var installID: String {
        if let existing = defaults?.string(forKey: installIDKey) { return existing }
        let created = UUID().uuidString
        defaults?.set(created, forKey: installIDKey)
        return created
    }

    /// One per launch, which is what a "session" means for a goal tracker — the app is opened,
    /// something is ticked off, it's closed again.
    private static let sessionID = UUID().uuidString

    static func send(_ event: AnalyticsEvent, _ parameters: [AnalyticsParameter: String] = [:]) {
        guard isEnabled, !namespace.isEmpty,
              let url = URL(string: "https://nom.telemetrydeck.com/v2/namespace/\(namespace)/")
        else { return }

        let signal = Signal(
            appID: appID,
            clientUser: installID,
            sessionID: sessionID,
            type: event.rawValue,
            isTestMode: isTestMode,
            payload: Dictionary(uniqueKeysWithValues: parameters.map { ($0.key.rawValue, $0.value) })
        )
        guard let body = try? JSONEncoder().encode([signal]) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        // Fire and forget: a check-in must never wait on — or fail because of — analytics, and a
        // dropped signal isn't worth a retry queue.
        URLSession.shared.dataTask(with: request).resume()
    }

    private struct Signal: Encodable {
        let appID: String
        let clientUser: String
        let sessionID: String
        let type: String
        let isTestMode: Bool
        let payload: [String: String]
    }
}
