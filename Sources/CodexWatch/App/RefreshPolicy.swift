import Foundation

enum RefreshFrequency: Int, CaseIterable, Sendable {
    case manual = 0
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1_800
    case adaptive = -1

    static let preferenceKey = "codexWatch.refreshFrequency"

    static func load(from defaults: UserDefaults = .standard) -> RefreshFrequency {
        guard defaults.object(forKey: preferenceKey) != nil,
              let stored = RefreshFrequency(rawValue: defaults.integer(forKey: preferenceKey)) else {
            defaults.set(RefreshFrequency.adaptive.rawValue, forKey: preferenceKey)
            return .adaptive
        }
        return stored
    }

    func persist(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.preferenceKey)
    }

    var displayName: String {
        switch self {
        case .manual: "Manual"
        case .oneMinute: "1 Minute"
        case .twoMinutes: "2 Minutes"
        case .fiveMinutes: "5 Minutes"
        case .fifteenMinutes: "15 Minutes"
        case .thirtyMinutes: "30 Minutes"
        case .adaptive: "Adaptive"
        }
    }
}

enum RefreshTrigger: Equatable, Sendable {
    case automatic
    case manual
    case menuOpened
    case wake
    case rateLimitUpdated
    case accountUpdated

    var replacesActiveWork: Bool {
        self == .manual || self == .accountUpdated
    }
}

struct RefreshRequest: Equatable, Sendable {
    let generation: Int
    let trigger: RefreshTrigger
    let includeAnalytics: Bool
    let requestedAt: Date
}

struct RefreshResult: Equatable, Sendable {
    let snapshot: UsageSnapshot?
    let error: MenuBarErrorState?
    let analyticsStale: Bool
    let profileStale: Bool
    let quotaFetchedAt: Date?

    init(
        snapshot: UsageSnapshot?,
        error: MenuBarErrorState?,
        analyticsStale: Bool,
        profileStale: Bool = false,
        quotaFetchedAt: Date? = nil
    ) {
        self.snapshot = snapshot
        self.error = error
        self.analyticsStale = analyticsStale
        self.profileStale = profileStale
        self.quotaFetchedAt = quotaFetchedAt
    }
}

enum QuotaRefreshAttempt: Equatable, Sendable {
    case success(UsageSnapshot)
    case failure(MenuBarErrorState)
}

enum RefreshBatch {
    static func execute(
        previousSnapshot: UsageSnapshot?,
        analyticsWasStale: Bool,
        profileWasStale: Bool,
        includeAnalytics: Bool,
        requestedAt: Date,
        quota: @Sendable @escaping () async -> QuotaRefreshAttempt,
        analytics: @Sendable @escaping () async -> CapabilityRefreshAttempt<UsageAnalyticsDataset>,
        profile: @Sendable @escaping () async -> CapabilityRefreshAttempt<CodexProfileStats>,
        onQuota: (@Sendable (RefreshResult) async -> Void)? = nil
    ) async -> RefreshResult {
        async let fetchedQuota = quota()
        let quotaAttempt: QuotaRefreshAttempt
        let analyticsAttempt: CapabilityRefreshAttempt<UsageAnalyticsDataset>
        let profileAttempt: CapabilityRefreshAttempt<CodexProfileStats>
        if includeAnalytics {
            async let fetchedAnalytics = analytics()
            async let fetchedProfile = profile()
            quotaAttempt = await fetchedQuota
            if let onQuota, !Task.isCancelled {
                await onQuota(resolve(
                    previousSnapshot: previousSnapshot,
                    analyticsWasStale: analyticsWasStale,
                    profileWasStale: profileWasStale,
                    requestedAt: requestedAt,
                    quotaAttempt: quotaAttempt,
                    analyticsAttempt: .notAttempted,
                    profileAttempt: .notAttempted
                ))
            }
            (analyticsAttempt, profileAttempt) = await (fetchedAnalytics, fetchedProfile)
        } else {
            quotaAttempt = await fetchedQuota
            analyticsAttempt = .notAttempted
            profileAttempt = .notAttempted
        }

        return resolve(
            previousSnapshot: previousSnapshot,
            analyticsWasStale: analyticsWasStale,
            profileWasStale: profileWasStale,
            requestedAt: requestedAt,
            quotaAttempt: quotaAttempt,
            analyticsAttempt: analyticsAttempt,
            profileAttempt: profileAttempt
        )
    }

    private static func resolve(
        previousSnapshot: UsageSnapshot?,
        analyticsWasStale: Bool,
        profileWasStale: Bool,
        requestedAt: Date,
        quotaAttempt: QuotaRefreshAttempt,
        analyticsAttempt: CapabilityRefreshAttempt<UsageAnalyticsDataset>,
        profileAttempt: CapabilityRefreshAttempt<CodexProfileStats>
    ) -> RefreshResult {
        let analyticsState = CapabilityRefreshState.resolve(
            previous: previousSnapshot?.analyticsDataset,
            wasStale: analyticsWasStale,
            attempt: analyticsAttempt
        )
        let profileState = CapabilityRefreshState.resolve(
            previous: previousSnapshot?.profileStats,
            wasStale: profileWasStale,
            attempt: profileAttempt
        )

        let baseSnapshot: UsageSnapshot?
        let error: MenuBarErrorState?
        let quotaFetchedAt: Date?
        switch quotaAttempt {
        case let .success(snapshot):
            baseSnapshot = snapshot
            error = nil
            quotaFetchedAt = snapshot.fetchedAt
        case let .failure(quotaError):
            baseSnapshot = previousSnapshot
            error = quotaError
            quotaFetchedAt = nil
        }

        let combinedSnapshot: UsageSnapshot?
        if let baseSnapshot {
            combinedSnapshot = baseSnapshot
                .adding(analyticsDataset: analyticsState.value)
                .adding(profileStats: profileState.value)
        } else if analyticsState.value != nil || profileState.value != nil {
            combinedSnapshot = UsageSnapshot(
                windows: [],
                analyticsDataset: analyticsState.value,
                profileStats: profileState.value,
                fetchedAt: requestedAt
            )
        } else {
            combinedSnapshot = nil
        }

        return RefreshResult(
            snapshot: combinedSnapshot,
            error: error,
            analyticsStale: analyticsState.isStale
                || (error == .signInRequired && analyticsState.value != nil),
            profileStale: profileState.isStale
                || (error == .signInRequired && profileState.value != nil),
            quotaFetchedAt: quotaFetchedAt
        )
    }
}

enum CapabilityRefreshAttempt<Value: Sendable>: Sendable {
    case notAttempted
    case success(Value)
    case failure
}

struct CapabilityRefreshState<Value: Sendable>: Sendable {
    let value: Value?
    let isStale: Bool

    static func resolve(
        previous: Value?,
        wasStale: Bool,
        attempt: CapabilityRefreshAttempt<Value>
    ) -> CapabilityRefreshState<Value> {
        switch attempt {
        case .notAttempted:
            return CapabilityRefreshState(value: previous, isStale: wasStale)
        case let .success(value):
            return CapabilityRefreshState(value: value, isStale: false)
        case .failure:
            return CapabilityRefreshState(value: previous, isStale: previous != nil)
        }
    }
}

enum RefreshPolicy {
    static let analyticsInterval: TimeInterval = 15 * 60
    static let menuOpenFreshness: TimeInterval = 60

    static func shouldIncludeAnalytics(
        trigger: RefreshTrigger,
        lastAttempt: Date?,
        now: Date
    ) -> Bool {
        if trigger == .menuOpened { return false }
        if trigger == .rateLimitUpdated { return false }
        if trigger == .manual || trigger == .accountUpdated { return true }
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= analyticsInterval
    }
}

enum AdaptiveRefreshPolicy {
    static func nextDelay(
        now: Date,
        lastMenuOpenAt: Date?,
        lowPowerMode: Bool,
        thermalConstrained: Bool
    ) -> TimeInterval {
        if lowPowerMode || thermalConstrained { return 30 * 60 }
        guard let lastMenuOpenAt else { return 30 * 60 }

        let elapsed = max(0, now.timeIntervalSince(lastMenuOpenAt))
        if elapsed <= 5 * 60 { return 2 * 60 }
        if elapsed <= 60 * 60 { return 5 * 60 }
        if elapsed <= 4 * 60 * 60 { return 15 * 60 }
        return 30 * 60
    }
}
