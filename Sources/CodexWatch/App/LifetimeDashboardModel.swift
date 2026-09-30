import Foundation

struct LifetimeActivityDay: Equatable, Identifiable, Sendable {
    let date: Date
    let tokens: Int64?

    var id: Date { date }
}

struct LifetimeInsightRow: Equatable, Identifiable, Sendable {
    let title: String
    let value: String

    var id: String { title }
}

struct LifetimeInvocationRow: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let usage: String
    let kind: CodexProfileInvocation.Kind
}

struct LifetimeDashboardModel: Equatable, Sendable {
    let lifetimeTokens: String
    let peakTokens: String
    let longestChat: String
    let currentStreak: String
    let longestStreak: String
    let activityDays: [LifetimeActivityDay]
    let observedBucketCount: Int
    let maximumDailyTokens: Int64
    let activityCoverage: String
    let insights: [LifetimeInsightRow]
    let invocations: [LifetimeInvocationRow]
    let dataThrough: String
    let fetchedAt: String

    init(profile: CodexProfileStats) {
        lifetimeTokens = Self.optionalCompact(profile.lifetimeTokens)
        peakTokens = Self.optionalCompact(profile.peakDailyTokens)
        longestChat = profile.longestRunningTurnSeconds.map(Self.duration) ?? "Unavailable"
        currentStreak = profile.currentStreakDays.map(Self.days) ?? "Unavailable"
        longestStreak = profile.longestStreakDays.map(Self.days) ?? "Unavailable"

        activityDays = profile.dailyBuckets.map {
            LifetimeActivityDay(date: $0.date, tokens: $0.tokens)
        }
        observedBucketCount = activityDays.count { $0.tokens != nil }
        maximumDailyTokens = activityDays.compactMap(\.tokens).max() ?? 0
        activityCoverage = Self.coverageText(
            days: activityDays,
            observedCount: observedBucketCount
        )
        insights = Self.makeInsights(profile.insights)
        invocations = profile.invocations.map {
            LifetimeInvocationRow(
                id: $0.id,
                name: "@\($0.displayName)",
                usage: "\(Self.compact($0.usageCount)) runs",
                kind: $0.kind
            )
        }
        let profileDataThrough = profile.dailyBuckets.last?.date ?? profile.fetchedAt
        dataThrough = Self.dateText(profileDataThrough)
        fetchedAt = Self.dateTimeText(profile.fetchedAt)
    }

    static func accessibilityText(_ day: LifetimeActivityDay) -> String {
        if let tokens = day.tokens {
            return "\(dateText(day.date)), \(tokens) tokens"
        }
        return "\(dateText(day.date)), token activity unavailable"
    }

    private static func makeInsights(_ insights: CodexProfileInsights) -> [LifetimeInsightRow] {
        var rows: [LifetimeInsightRow] = []
        if let value = percentage(insights.fastModePercent) {
            rows.append(LifetimeInsightRow(title: "Fast Mode", value: value))
        }
        if let effort = insights.reasoningEffort {
            let value = insights.reasoningEffortPercent.flatMap(percentage)
                .map { "\(effort) · \($0)" } ?? effort
            rows.append(LifetimeInsightRow(title: "Most used reasoning", value: value))
        } else if let value = percentage(insights.reasoningEffortPercent) {
            rows.append(LifetimeInsightRow(title: "Most used reasoning", value: value))
        }
        if let value = insights.uniqueSkillsUsed {
            rows.append(LifetimeInsightRow(title: "Skills explored", value: String(value)))
        }
        if let value = insights.totalSkillsUsed {
            rows.append(LifetimeInsightRow(title: "Total skills used", value: compact(value)))
        }
        if let value = insights.totalChats {
            rows.append(LifetimeInsightRow(title: "Total chats", value: compact(value)))
        }
        return rows
    }

    private static func coverageText(
        days: [LifetimeActivityDay],
        observedCount: Int
    ) -> String {
        guard let first = days.first?.date, let last = days.last?.date else {
            return "No daily activity buckets reported"
        }
        return "\(observedCount) server-observed days · \(rangeText(first, last))"
    }

    private static func rangeText(_ first: Date, _ last: Date) -> String {
        let sameYear = CodexProfileDateParser.calendar.component(.year, from: first)
            == CodexProfileDateParser.calendar.component(.year, from: last)
        let start = first.formatted(sameYear ? rangeStartStyle : dateStyle)
        let end = last.formatted(dateStyle)
        return "\(start)–\(end)"
    }

    private static func optionalCompact(_ value: Int64?) -> String {
        value.map(compact) ?? "Unavailable"
    }

    static func compact(_ value: Int64) -> String {
        CompactNumberFormat.string(value)
    }

    private static func duration(_ seconds: Int64) -> String {
        if seconds < 60 { return "\(max(0, seconds))s" }
        let totalMinutes = seconds / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    private static func days(_ value: Int) -> String {
        "\(value) \(value == 1 ? "day" : "days")"
    }

    private static func percentage(_ value: Double?) -> String? {
        guard let value, value.isFinite else { return nil }
        var text = String(
            format: "%.1f",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
        if text.hasSuffix(".0") { text.removeLast(2) }
        return "\(text)%"
    }

    private static func dateText(_ date: Date) -> String {
        date.formatted(dateStyle)
    }

    private static func dateTimeText(_ date: Date) -> String {
        date.formatted(
            .dateTime.year().month(.abbreviated).day().hour().minute()
                .locale(Locale(identifier: "en_US_POSIX"))
        )
    }

    private static let dateStyle = Date.FormatStyle(
        date: .abbreviated,
        time: .omitted,
        locale: Locale(identifier: "en_US_POSIX"),
        calendar: CodexProfileDateParser.calendar,
        timeZone: CodexProfileDateParser.calendar.timeZone
    )

    private static let rangeStartStyle = Date.FormatStyle(
        date: .omitted,
        time: .omitted,
        locale: Locale(identifier: "en_US_POSIX"),
        calendar: CodexProfileDateParser.calendar,
        timeZone: CodexProfileDateParser.calendar.timeZone
    )
    .month(.abbreviated)
    .day()
}
