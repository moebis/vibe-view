import Foundation

enum AppServerUsageAdapter {
    private static let maximumTimestamp = Int64(253_402_300_799)

    static func snapshot(
        from response: AppServerRateLimitsResponse,
        fetchedAt: Date
    ) -> UsageSnapshot {
        let mappedBase = response.rateLimitsByLimitID?["codex"]
        let candidate = mappedBase ?? response.rateLimits
        let base = candidate.limitID == nil || candidate.limitID == "codex" ? candidate : nil
        let windows = [
            makeWindow(id: "primary", value: base?.primary),
            makeWindow(id: "secondary", value: base?.secondary)
        ].compactMap { $0 }

        var additionalWindows: [NamedUsageWindow] = []
        let buckets = (response.rateLimitsByLimitID ?? [:]).sorted(by: { $0.key < $1.key })
        for (index, bucket) in buckets.enumerated() {
            let (key, value) = bucket
            if key == base?.limitID || key == "codex" { continue }
            let baseID = boundedSlug(value.limitID ?? key).prefix(40)
            guard !baseID.isEmpty else { continue }
            for (role, source) in [("primary", value.primary), ("secondary", value.secondary)] {
                // Reserve the role suffix and disambiguate equal/truncated slugs.
                let id = "\(baseID)-\(index)-\(role)"
                guard let window = makeWindow(id: id, value: source) else { continue }
                additionalWindows.append(NamedUsageWindow(
                    id: id,
                    title: windowTitle(
                        base: boundedText(value.limitName ?? value.limitID ?? key, maximumBytes: 96),
                        kind: window.kind
                    ),
                    window: window
                ))
            }
        }

        return UsageSnapshot(
            plan: base?.planType.flatMap { ChatGPTPlan(apiValue: $0.rawValue) },
            creditsRemaining: credits(from: base?.credits),
            windows: windows,
            additionalWindows: additionalWindows,
            resetCredits: resetCredits(from: response.resetCredits?.credits),
            spendControl: spendControl(from: base?.individualLimit),
            rateLimitReachedReason: reachedReason(from: base?.reachedReason),
            availableResetCredits: availableResetCredits(from: response.resetCredits),
            fetchedAt: fetchedAt,
            source: .appServer
        )
    }

    static func profile(
        from response: AppServerAccountUsageResponse,
        fetchedAt: Date
    ) -> CodexProfileStats {
        let summary = response.summary
        return CodexProfileStats(
            lifetimeTokens: nonnegative(summary.lifetimeTokens),
            peakDailyTokens: nonnegative(summary.peakDailyTokens),
            longestRunningTurnSeconds: nonnegative(summary.longestRunningTurnSeconds),
            currentStreakDays: boundedInt(summary.currentStreakDays),
            longestStreakDays: boundedInt(summary.longestStreakDays),
            dailyBuckets: dailyBuckets(from: response.dailyUsageBuckets),
            insights: CodexProfileInsights(
                fastModePercent: nil,
                reasoningEffort: nil,
                reasoningEffortPercent: nil,
                uniqueSkillsUsed: nil,
                totalSkillsUsed: nil,
                totalChats: nil
            ),
            invocations: [],
            fetchedAt: fetchedAt
        )
    }

    private static func makeWindow(
        id: String,
        value: AppServerRateLimitWindow?
    ) -> UsageWindow? {
        guard let value,
              let minutes = value.windowDurationMinutes,
              minutes > 0,
              minutes <= Int64(Int.max / 60) else { return nil }
        let seconds = Int(minutes) * 60
        return UsageWindow(
            id: id,
            kind: UsageWindowClassifier.kind(seconds: seconds),
            usedPercent: Double(value.usedPercent),
            resetAt: date(from: value.resetsAt),
            durationSeconds: TimeInterval(seconds)
        )
    }

    private static func credits(from value: AppServerCreditsSnapshot?) -> CreditsRemaining? {
        guard let value else { return nil }
        if value.unlimited { return .unlimited }
        guard value.hasCredits,
              let balance = value.balance?.trimmingCharacters(in: .whitespacesAndNewlines),
              !balance.isEmpty,
              balance.utf8.count <= 64,
              let decimal = ValidatedDecimal.parse(balance),
              !decimal.isNaN else { return nil }
        return .balance(balance)
    }

    private static func spendControl(
        from value: AppServerSpendControlLimit?
    ) -> SpendControlSummary? {
        guard let value,
              let limit = ValidatedDecimal.parse(value.limit),
              let used = ValidatedDecimal.parse(value.used),
              !limit.isNaN,
              !used.isNaN,
              limit >= 0, used >= 0,
              value.remainingPercent.isFinite else { return nil }
        return SpendControlSummary(
            limit: limit,
            used: used,
            remainingPercent: min(100, max(0, value.remainingPercent)),
            resetsAt: date(from: value.resetsAt)
        )
    }

    private static func reachedReason(
        from value: AppServerRateLimitReachedReason?
    ) -> RateLimitReachedReason? {
        switch value {
        case .rateLimitReached: .quotaReached
        case .workspaceOwnerCreditsDepleted, .workspaceMemberCreditsDepleted:
            .workspaceCreditsDepleted
        case .workspaceOwnerUsageLimitReached, .workspaceMemberUsageLimitReached:
            .workspaceUsageLimitReached
        case .unknown: nil
        case nil: nil
        }
    }

    private static func availableResetCredits(
        from summary: AppServerResetCreditsSummary?
    ) -> Int? {
        guard let summary,
              summary.availableCount >= 0,
              summary.availableCount <= Int64(Int.max) else { return nil }
        return Int(summary.availableCount)
    }

    private static func resetCredits(
        from values: [AppServerResetCredit]?
    ) -> [ResetCredit] {
        (values ?? []).compactMap { value in
            let id = boundedText(value.id, maximumBytes: 256)
            guard !id.isEmpty else { return nil }
            return ResetCredit(
                id: id,
                status: value.status.rawValue,
                title: value.title.map { boundedText($0, maximumBytes: 256) },
                grantedAt: date(from: value.grantedAt),
                expiresAt: date(from: value.expiresAt),
                isSupportedByPlan: value.resetType == .codexRateLimits
            )
        }
    }

    private static func dailyBuckets(
        from values: [AppServerAccountUsageDailyBucket]?
    ) -> [CodexProfileDailyBucket] {
        guard let values else { return [] }
        var seen = Set<Date>()
        var result: [CodexProfileDailyBucket] = []
        for value in values {
            guard value.tokens >= 0,
                  let date = profileDate(value.startDate),
                  seen.insert(date).inserted else { return [] }
            result.append(CodexProfileDailyBucket(date: date, tokens: value.tokens))
        }
        return result.sorted { $0.date < $1.date }
    }

    private static func profileDate(_ value: String) -> Date? {
        CodexProfileDateParser.parse(value)
    }

    private static func date(from timestamp: Int64?) -> Date? {
        guard let timestamp,
              timestamp >= 0,
              timestamp <= maximumTimestamp else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }

    private static func nonnegative(_ value: Int64?) -> Int64? {
        guard let value, value >= 0 else { return nil }
        return value
    }

    private static func boundedInt(_ value: Int64?) -> Int? {
        guard let value,
              value >= 0,
              value <= Int64(Int.max) else { return nil }
        return Int(value)
    }

    private static func boundedSlug(_ value: String) -> String {
        var result = ""
        var lastWasDash = false
        for scalar in value.lowercased().unicodeScalars {
            let isASCIIAlphaNumeric = (97 ... 122).contains(scalar.value)
                || (48 ... 57).contains(scalar.value)
            if isASCIIAlphaNumeric {
                guard result.utf8.count < 64 else { break }
                result.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !result.isEmpty, !lastWasDash {
                result.append("-")
                lastWasDash = true
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func boundedText(_ value: String, maximumBytes: Int) -> String {
        var result = ""
        for character in value.trimmingCharacters(in: .whitespacesAndNewlines) {
            let candidate = result + String(character)
            guard candidate.utf8.count <= maximumBytes else { break }
            result = candidate
        }
        return result
    }

    private static func windowTitle(base: String, kind: UsageWindowKind) -> String {
        let usableBase = base.isEmpty ? "Codex quota" : base
        return switch kind {
        case let .rolling(hours): "\(usableBase) \(hours)-hour"
        case .daily: "\(usableBase) Daily"
        case .weekly: "\(usableBase) Weekly"
        case .custom: "\(usableBase) Quota"
        }
    }
}
