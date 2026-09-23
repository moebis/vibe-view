import Foundation

struct QuotaNotificationDecision: Equatable, Sendable {
    let threshold: Int
    let identifier: String
    let title: String
    let body: String
}

struct QuotaNotificationPolicy: Sendable {
    private static let thresholds = [0, 5, 10, 25]
    private var lastNotifiedThreshold: Int?
    private var lastWindowResetAt: Date?

    mutating func consume(
        remainingPercent: Double?,
        isFresh: Bool,
        windowResetAt: Date? = nil
    ) -> QuotaNotificationDecision? {
        guard isFresh,
              let remainingPercent,
              remainingPercent.isFinite else { return nil }

        if let windowResetAt, windowResetAt != lastWindowResetAt {
            lastWindowResetAt = windowResetAt
            lastNotifiedThreshold = nil
        }

        let remaining = min(100, max(0, remainingPercent))
        guard let threshold = Self.thresholds.first(where: { remaining <= Double($0) }) else {
            return nil
        }
        guard lastNotifiedThreshold == nil || threshold < lastNotifiedThreshold! else { return nil }
        lastNotifiedThreshold = threshold

        return QuotaNotificationDecision(
            threshold: threshold,
            identifier: "codex-watch-weekly-\(threshold)",
            title: threshold == 0 ? "Codex weekly quota is exhausted" : "Codex weekly quota is low",
            body: "Open Vibe View to review the remaining quota."
        )
    }
}

enum FeaturePreferences {
    static let notificationsEnabledKey = "quotaNotificationsEnabled"
    static func notificationsEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: notificationsEnabledKey)
    }

    static func setNotificationsEnabled(
        _ enabled: Bool,
        in defaults: UserDefaults = .standard
    ) {
        defaults.set(enabled, forKey: notificationsEnabledKey)
    }
}

enum DiagnosticsDataSource: Sendable {
    case appServer
    case legacyHTTPS
    case unavailable

    var displayName: String {
        switch self {
        case .appServer: "Codex App Server"
        case .legacyHTTPS: "Legacy HTTPS compatibility"
        case .unavailable: "Unavailable"
        }
    }
}

enum DiagnosticsSurfaceState: String, Sendable {
    case current
    case stale
    case unavailable
}

struct SafeDiagnostics: Sendable {
    let version: String
    let dataSource: DiagnosticsDataSource
    let quota: DiagnosticsSurfaceState
    let usage: DiagnosticsSurfaceState
    let lifetime: DiagnosticsSurfaceState
    let notificationsEnabled: Bool
    let launchAtLoginEnabled: Bool

    var text: String {
        [
            "Vibe View \(version)",
            "Quota source: \(dataSource.displayName)",
            "Quota: \(quota.rawValue)",
            "Usage analytics: \(usage.rawValue)",
            "Lifetime: \(lifetime.rawValue)",
            "Notifications: \(notificationsEnabled ? "enabled" : "disabled")",
            "Launch at Login: \(launchAtLoginEnabled ? "enabled" : "disabled")"
        ].joined(separator: "\n")
    }
}

struct PendingResetRedemption: Equatable, Sendable {
    let idempotencyKey: String
    let creditID: String?
}

struct ResetCreditRedemptionState: Sendable {
    private(set) var pending: PendingResetRedemption?

    mutating func request(
        creditID: String?,
        makeKey: () -> String = { UUID().uuidString }
    ) -> PendingResetRedemption {
        if let pending { return pending }
        let request = PendingResetRedemption(
            idempotencyKey: makeKey(),
            creditID: creditID
        )
        pending = request
        return request
    }

    mutating func complete(outcome: AppServerResetOutcome) {
        pending = nil
    }

    static func message(for outcome: AppServerResetOutcome) -> String {
        switch outcome {
        case .reset:
            "Weekly quota was reset."
        case .alreadyRedeemed:
            "This reset credit was already used. Quota has been refreshed."
        case .nothingToReset:
            "There is no exhausted quota to reset."
        case .noCredit:
            "No reset credit is available."
        }
    }
}
