import Foundation

enum ChatGPTPlan: Equatable, Sendable {
    case free
    case go
    case plus
    case pro
    case proLite
    case business
    case enterprise
    case edu

    init?(apiValue: String) {
        switch apiValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "free": self = .free
        case "go": self = .go
        case "plus": self = .plus
        case "pro": self = .pro
        case "prolite": self = .proLite
        case "team", "self_serve_business_prolite", "self_serve_business_usage_based", "business":
            self = .business
        case "ent26", "enterprise_cbp_automation", "enterprise_cbp_usage_based", "enterprise":
            self = .enterprise
        case "edu", "edu_plus", "edu_pro": self = .edu
        default: return nil
        }
    }

    var displayName: String {
        switch self {
        case .free: "Free"
        case .go: "Go"
        case .plus: "Plus"
        case .pro: "Pro"
        case .proLite: "Pro Lite"
        case .business: "Business"
        case .enterprise: "Enterprise"
        case .edu: "Edu"
        }
    }
}

enum UsageWindowKind: Equatable, Sendable {
    case rolling(hours: Int)
    case daily
    case weekly
    case custom(seconds: Int)
}

struct UsageWindow: Equatable, Identifiable, Sendable {
    let id: String
    let kind: UsageWindowKind
    let usedPercent: Double
    let resetAt: Date?
    let durationSeconds: TimeInterval?

    init(
        id: String,
        kind: UsageWindowKind,
        usedPercent: Double,
        resetAt: Date? = nil,
        durationSeconds: TimeInterval? = nil
    ) {
        self.id = id
        self.kind = kind
        self.usedPercent = UsageWindowClassifier.clampPercent(usedPercent)
        self.resetAt = resetAt
        self.durationSeconds = durationSeconds
    }

    var remainingPercent: Double {
        max(0, 100 - usedPercent)
    }
}

struct NamedUsageWindow: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let window: UsageWindow
}

struct ResetCredit: Equatable, Identifiable, Sendable {
    let id: String
    let status: String
    let title: String?
    let grantedAt: Date?
    let expiresAt: Date?
    let isSupportedByPlan: Bool?
}

struct SpendControlSummary: Equatable, Sendable {
    let limit: Decimal
    let used: Decimal
    let remainingPercent: Double?
    let resetsAt: Date?
}

enum RateLimitReachedReason: Equatable, Sendable {
    case quotaReached
    case workspaceCreditsDepleted
    case workspaceUsageLimitReached

    var displayName: String {
        switch self {
        case .quotaReached: "Quota reached"
        case .workspaceCreditsDepleted: "Workspace credits depleted"
        case .workspaceUsageLimitReached: "Workspace usage limit reached"
        }
    }
}

enum UsageDataSource: Equatable, Sendable {
    case appServer
    case legacyHTTPS
}

struct UsageSnapshot: Equatable, Sendable {
    let plan: ChatGPTPlan?
    let creditsRemaining: CreditsRemaining?
    let windows: [UsageWindow]
    let additionalWindows: [NamedUsageWindow]
    let codeReviewWindows: [NamedUsageWindow]
    let resetCredits: [ResetCredit]
    let spendControl: SpendControlSummary?
    let rateLimitReachedReason: RateLimitReachedReason?
    private let reportedAvailableResetCredits: Int?
    let analyticsDataset: UsageAnalyticsDataset?
    let profileStats: CodexProfileStats?
    let fetchedAt: Date
    let source: UsageDataSource

    init(
        plan: ChatGPTPlan? = nil,
        creditsRemaining: CreditsRemaining? = nil,
        windows: [UsageWindow],
        additionalWindows: [NamedUsageWindow] = [],
        codeReviewWindows: [NamedUsageWindow] = [],
        resetCredits: [ResetCredit] = [],
        spendControl: SpendControlSummary? = nil,
        rateLimitReachedReason: RateLimitReachedReason? = nil,
        availableResetCredits: Int? = nil,
        nextResetCreditGrantedAt: Date? = nil,
        nextResetCreditExpiry: Date? = nil,
        analyticsDataset: UsageAnalyticsDataset? = nil,
        profileStats: CodexProfileStats? = nil,
        fetchedAt: Date = .now,
        source: UsageDataSource = .legacyHTTPS
    ) {
        self.plan = plan
        self.creditsRemaining = creditsRemaining
        self.windows = windows
        self.additionalWindows = additionalWindows
        self.codeReviewWindows = codeReviewWindows
        self.spendControl = spendControl
        self.rateLimitReachedReason = rateLimitReachedReason
        self.reportedAvailableResetCredits = availableResetCredits
        if resetCredits.isEmpty,
           nextResetCreditGrantedAt != nil || nextResetCreditExpiry != nil {
            self.resetCredits = [ResetCredit(
                id: "legacy-next-reset-credit",
                status: "available",
                title: nil,
                grantedAt: nextResetCreditGrantedAt,
                expiresAt: nextResetCreditExpiry,
                isSupportedByPlan: true
            )]
        } else {
            self.resetCredits = resetCredits
        }
        self.analyticsDataset = analyticsDataset
        self.profileStats = profileStats
        self.fetchedAt = fetchedAt
        self.source = source
    }

    var availableResetCredits: Int? {
        reportedAvailableResetCredits
    }

    var nextResetCreditGrantedAt: Date? {
        nextAvailableResetCredit?.grantedAt
    }

    var nextResetCreditExpiry: Date? {
        nextAvailableResetCredit?.expiresAt
    }

    var weeklyWindow: UsageWindow? {
        windows.first { window in
            if case .weekly = window.kind { return true }
            return false
        }
    }

    func adding(resetCredits newResetCredits: [ResetCredit]) -> UsageSnapshot {
        return UsageSnapshot(
            plan: plan,
            creditsRemaining: creditsRemaining,
            windows: windows,
            additionalWindows: additionalWindows,
            codeReviewWindows: codeReviewWindows,
            resetCredits: newResetCredits,
            spendControl: spendControl,
            rateLimitReachedReason: rateLimitReachedReason,
            availableResetCredits: availableResetCredits,
            analyticsDataset: analyticsDataset,
            profileStats: profileStats,
            fetchedAt: fetchedAt,
            source: source
        )
    }

    func adding(analyticsDataset newAnalyticsDataset: UsageAnalyticsDataset?) -> UsageSnapshot {
        UsageSnapshot(
            plan: plan,
            creditsRemaining: creditsRemaining,
            windows: windows,
            additionalWindows: additionalWindows,
            codeReviewWindows: codeReviewWindows,
            resetCredits: resetCredits,
            spendControl: spendControl,
            rateLimitReachedReason: rateLimitReachedReason,
            availableResetCredits: availableResetCredits,
            analyticsDataset: newAnalyticsDataset ?? analyticsDataset,
            profileStats: profileStats,
            fetchedAt: fetchedAt,
            source: source
        )
    }

    func adding(profileStats newProfileStats: CodexProfileStats?) -> UsageSnapshot {
        UsageSnapshot(
            plan: plan,
            creditsRemaining: creditsRemaining,
            windows: windows,
            additionalWindows: additionalWindows,
            codeReviewWindows: codeReviewWindows,
            resetCredits: resetCredits,
            spendControl: spendControl,
            rateLimitReachedReason: rateLimitReachedReason,
            availableResetCredits: availableResetCredits,
            analyticsDataset: analyticsDataset,
            profileStats: newProfileStats ?? profileStats,
            fetchedAt: fetchedAt,
            source: source
        )
    }

    private var nextAvailableResetCredit: ResetCredit? {
        resetCredits
            .filter { $0.status == "available" && $0.isSupportedByPlan != false }
            .filter { $0.expiresAt != nil }
            .min { lhs, rhs in
                lhs.expiresAt ?? .distantFuture < rhs.expiresAt ?? .distantFuture
            }
    }
}

enum CreditsRemaining: Equatable, Sendable {
    case balance(String)
    case unlimited

    var displayValue: String {
        switch self {
        case let .balance(value):
            guard var decimal = ValidatedDecimal.parse(value) else { return "Unavailable" }
            var rounded = Decimal()
            NSDecimalRound(&rounded, &decimal, 0, .plain)
            return rounded.formatted(
                .number.locale(Locale(identifier: "en_US"))
                    .grouping(.automatic).precision(.fractionLength(0))
            )
        case .unlimited: return "Unlimited"
        }
    }
}

extension CreditsRemaining {
    var displayDetail: String? {
        guard case let .balance(value) = self else { return nil }
        return "Reported balance: \(value) credits. Display rounded to the nearest whole credit."
    }
}
