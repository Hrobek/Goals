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
    /// Which Pro plan a purchase was for — monthly, yearly or lifetime.
    case plan = "Purchase.plan"
    /// Which first-run template a goal was started from (`run`, `weight`, …), or "custom" for a
    /// goal built from the blank form. Never carries anything the user typed.
    case template = "Goal.template"
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

    // Persisted retention counters, all in the App Group so the app and the widget share one history.
    private static let firstSessionDateKey = "Goals.analytics.firstSessionDate"
    private static let totalSessionsKey = "Goals.analytics.totalSessions"
    private static let distinctDaysKey = "Goals.analytics.distinctDaysUsed"
    private static let lastDayUsedKey = "Goals.analytics.lastDayUsed"
    private static let recentDaysKey = "Goals.analytics.recentDays"
    private static let completedSessionsKey = "Goals.analytics.completedSessions"
    private static let sessionSecondsTotalKey = "Goals.analytics.sessionSecondsTotal"
    private static let previousSessionSecondsKey = "Goals.analytics.previousSessionSeconds"
    private static let currentSessionStartKey = "Goals.analytics.currentSessionStart"
    private static let countedSessionIDKey = "Goals.analytics.countedSessionID"
    private static let completedSessionIDKey = "Goals.analytics.completedSessionID"

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

    // MARK: - Session lifecycle

    /// Called when the app becomes active. Records the launch against the retention counters once
    /// per process — returning from the background a second time doesn't count as a new session —
    /// and starts the clock for `averageSessionSeconds`.
    static func beginSession() {
        guard isEnabled, let defaults else { return }
        let now = Date()
        defaults.set(now.timeIntervalSinceReferenceDate, forKey: currentSessionStartKey)

        guard defaults.string(forKey: countedSessionIDKey) != sessionID else { return }
        defaults.set(sessionID, forKey: countedSessionIDKey)

        let today = dayString(now)
        if defaults.string(forKey: firstSessionDateKey) == nil {
            defaults.set(today, forKey: firstSessionDateKey)
        }
        defaults.set(defaults.integer(forKey: totalSessionsKey) + 1, forKey: totalSessionsKey)

        if defaults.string(forKey: lastDayUsedKey) != today {
            defaults.set(today, forKey: lastDayUsedKey)
            defaults.set(defaults.integer(forKey: distinctDaysKey) + 1, forKey: distinctDaysKey)
        }

        // A rolling window of the days the app was opened, kept only long enough to answer
        // "distinct days in the last month". ISO date strings sort as dates, so the cut-off is a
        // string comparison — no parsing.
        var recent = defaults.stringArray(forKey: recentDaysKey) ?? []
        if !recent.contains(today) { recent.append(today) }
        let windowStart = dayString(now.addingTimeInterval(-35 * 86_400))
        defaults.set(recent.filter { $0 >= windowStart }.sorted(), forKey: recentDaysKey)
    }

    /// Called when the app leaves the foreground. Closes the session that `beginSession` opened and
    /// folds its length into the running average.
    static func endSession() {
        guard isEnabled, let defaults,
              let startedAt = defaults.object(forKey: currentSessionStartKey) as? Double
        else { return }
        defaults.removeObject(forKey: currentSessionStartKey)

        let duration = Date().timeIntervalSinceReferenceDate - startedAt
        guard duration > 1, duration < 86_400 else { return }

        defaults.set(duration, forKey: previousSessionSecondsKey)
        defaults.set(defaults.double(forKey: sessionSecondsTotalKey) + duration, forKey: sessionSecondsTotalKey)

        // Time keeps accruing across foreground/background cycles within a launch, but the launch
        // is only one session for the purpose of the average.
        if defaults.string(forKey: completedSessionIDKey) != sessionID {
            defaults.set(sessionID, forKey: completedSessionIDKey)
            defaults.set(defaults.integer(forKey: completedSessionsKey) + 1, forKey: completedSessionsKey)
        }
    }

    // MARK: - Sending

    static func send(_ event: AnalyticsEvent, _ parameters: [AnalyticsParameter: String] = [:]) {
        guard isEnabled, !namespace.isEmpty,
              let url = URL(string: "https://nom.telemetrydeck.com/v2/namespace/\(namespace)/")
        else { return }

        var payload = defaultParameters
        payload.merge(calendarParameters) { _, event in event }
        payload.merge(retentionParameters) { _, event in event }
        for (key, value) in parameters { payload[key.rawValue] = .string(value) }

        let signal = Signal(
            appID: appID,
            clientUser: installID,
            sessionID: sessionID,
            type: event.rawValue,
            isTestMode: isTestMode,
            payload: payload
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

    // MARK: - Default parameters

    /// The parameters TelemetryDeck's official SDK attaches to every signal, and which its built-in
    /// Device / App Version / OS / distribution insights group by. Because the signal is posted by
    /// hand here rather than by the SDK, nothing fills these in unless we do — so the dashboard's
    /// standard panels stay empty. Everything below is aggregate and non-identifying: the same bar
    /// the events themselves are held to. Computed once; none of it changes within a launch.
    private static let defaultParameters: [String: SignalValue] = {
        var p: [String: SignalValue] = [:]

        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        p["TelemetryDeck.AppInfo.version"] = .string(version)
        p["TelemetryDeck.AppInfo.buildNumber"] = .string(build)
        p["TelemetryDeck.AppInfo.versionAndBuildNumber"] = .string("\(version) (build \(build))")

        let os = ProcessInfo.processInfo.operatingSystemVersion
        p["TelemetryDeck.Device.operatingSystem"] = .string("iOS")
        p["TelemetryDeck.Device.platform"] = .string("iOS")
        p["TelemetryDeck.Device.brand"] = .string("Apple")
        p["TelemetryDeck.Device.systemVersion"] = .string("\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
        p["TelemetryDeck.Device.systemMajorMinorVersion"] = .string("\(os.majorVersion).\(os.minorVersion)")
        p["TelemetryDeck.Device.systemMajorVersion"] = .string("\(os.majorVersion)")
        p["TelemetryDeck.Device.timeZone"] = .string(TimeZone.current.identifier)
        p["TelemetryDeck.Device.modelName"] = .string(hardwareModel)
        p["TelemetryDeck.Device.architecture"] = .string(architecture)

        p["TelemetryDeck.RunContext.locale"] = .string(Locale.current.identifier)
        if let language = Locale.current.language.languageCode?.identifier {
            p["TelemetryDeck.RunContext.language"] = .string(language)
        }
        p["TelemetryDeck.RunContext.isSimulator"] = .bool(isSimulator)
        p["TelemetryDeck.RunContext.isDebug"] = .bool(isTestMode)
        p["TelemetryDeck.RunContext.isTestFlight"] = .bool(isTestFlight)
        p["TelemetryDeck.RunContext.isAppStore"] = .bool(!isSimulator && !isTestFlight && !isTestMode)
        p["TelemetryDeck.RunContext.targetEnvironment"] = .string(isSimulator ? "simulator" : "native")

        if let region = Locale.current.region?.identifier {
            p["TelemetryDeck.UserPreference.region"] = .string(region)
        }
        if let language = Locale.preferredLanguages.first {
            p["TelemetryDeck.UserPreference.language"] = .string(language)
        }

        // Not the real SDK, but the dashboard expects a name here and it makes the origin obvious.
        p["TelemetryDeck.SDK.name"] = .string("GoalsCustomIngest")
        p["TelemetryDeck.SDK.version"] = .string(version)

        return p
    }()

    /// When the signal was sent, broken out the way TelemetryDeck's Calendar insights expect it —
    /// so "check-ins by hour of day" and "by weekday" work without a custom query. Recomputed per
    /// signal; the server's own timestamp is UTC and wouldn't answer these for the user's day.
    private static var calendarParameters: [String: SignalValue] {
        let now = Date()
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.day, .weekday, .weekOfYear, .month, .hour], from: now)

        var p: [String: SignalValue] = [:]
        if let day = parts.day { p["TelemetryDeck.Calendar.dayOfMonth"] = .int(day) }
        if let weekday = parts.weekday {
            // `weekday` is 1 = Sunday … 7 = Saturday; TelemetryDeck follows ISO 8601, 1 = Monday.
            p["TelemetryDeck.Calendar.dayOfWeek"] = .int((weekday + 5) % 7 + 1)
        }
        if let dayOfYear = calendar.ordinality(of: .day, in: .year, for: now) {
            p["TelemetryDeck.Calendar.dayOfYear"] = .int(dayOfYear)
        }
        if let week = parts.weekOfYear { p["TelemetryDeck.Calendar.weekOfYear"] = .int(week) }
        if let month = parts.month {
            p["TelemetryDeck.Calendar.monthOfYear"] = .int(month)
            p["TelemetryDeck.Calendar.quarterOfYear"] = .int((month - 1) / 3 + 1)
        }
        if let hour = parts.hour { p["TelemetryDeck.Calendar.hourOfDay"] = .int(hour) }
        p["TelemetryDeck.Calendar.isWeekend"] = .bool(calendar.isDateInWeekend(now))
        return p
    }

    /// The retention picture the SDK would otherwise keep for us, read back from the counters that
    /// `beginSession` / `endSession` maintain. Feeds TelemetryDeck's retention and "new vs
    /// returning" presets. All of it is derived from launch timing — never from identity.
    private static var retentionParameters: [String: SignalValue] {
        guard let defaults else { return [:] }
        var p: [String: SignalValue] = [:]

        if let firstDate = defaults.string(forKey: firstSessionDateKey) {
            p["TelemetryDeck.Acquisition.firstSessionDate"] = .string(firstDate)
        }
        let totalSessions = defaults.integer(forKey: totalSessionsKey)
        if totalSessions > 0 {
            p["TelemetryDeck.Retention.totalSessionsCount"] = .int(totalSessions)
        }
        let distinctDays = defaults.integer(forKey: distinctDaysKey)
        if distinctDays > 0 {
            p["TelemetryDeck.Retention.distinctDaysUsed"] = .int(distinctDays)
        }
        let windowStart = dayString(Date().addingTimeInterval(-30 * 86_400))
        let daysLastMonth = (defaults.stringArray(forKey: recentDaysKey) ?? []).filter { $0 >= windowStart }.count
        if daysLastMonth > 0 {
            p["TelemetryDeck.Retention.distinctDaysUsedLastMonth"] = .int(daysLastMonth)
        }
        let completedSessions = defaults.integer(forKey: completedSessionsKey)
        if completedSessions > 0 {
            let average = defaults.double(forKey: sessionSecondsTotalKey) / Double(completedSessions)
            p["TelemetryDeck.Retention.averageSessionSeconds"] = .double(average.rounded())
        }
        let previous = defaults.double(forKey: previousSessionSecondsKey)
        if previous > 0 {
            p["TelemetryDeck.Retention.previousSessionSeconds"] = .double(previous.rounded())
        }
        return p
    }

    // MARK: - Derivations

    private static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    /// TestFlight builds ship with a sandbox App Store receipt; App Store builds ship with a
    /// production one. Nothing in the receipt is read — only which file is present.
    private static var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    private static var architecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }

    /// The hardware identifier, e.g. `iPhone16,2`. On the simulator `uname` reports the host Mac, so
    /// the device being emulated is read from the environment instead.
    private static var hardwareModel: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var info = utsname()
        uname(&info)
        return Mirror(reflecting: info.machine).children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.unicodeScalars.append(UnicodeScalar(UInt8(value)))
        }
    }

    /// `yyyy-MM-dd` in the device's own time zone. Used as a sortable day key for the distinct-days
    /// counters; a plain format string keeps it free of `DateFormatter` locale surprises.
    private static func dayString(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // MARK: - Wire format

    /// A payload value. TelemetryDeck's Calendar and Retention insights aggregate numerically, so
    /// those parameters have to arrive as JSON numbers (and the run-context flags as booleans),
    /// not strings — hence a small sum type rather than the flat `[String: String]` that the
    /// event parameters alone would allow.
    private enum SignalValue: Encodable {
        case string(String)
        case int(Int)
        case double(Double)
        case bool(Bool)

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value): try container.encode(value)
            case .int(let value): try container.encode(value)
            case .double(let value): try container.encode(value)
            case .bool(let value): try container.encode(value)
            }
        }
    }

    private struct Signal: Encodable {
        let appID: String
        let clientUser: String
        let sessionID: String
        let type: String
        let isTestMode: Bool
        let payload: [String: SignalValue]
    }
}
