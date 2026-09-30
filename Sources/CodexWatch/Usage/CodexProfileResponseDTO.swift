import Foundation

struct CodexProfileResponseDTO: Decodable {
    static let maximumInvocationCount = 50

    private let stats: StatsDTO?

    enum CodingKeys: String, CodingKey {
        case stats
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stats = try? container.decodeIfPresent(StatsDTO.self, forKey: .stats)
    }

    func profileStats(fetchedAt: Date = .now) -> CodexProfileStats? {
        guard let stats else { return nil }
        return CodexProfileStats(
            lifetimeTokens: Self.nonnegative(stats.lifetimeTokens),
            peakDailyTokens: Self.nonnegative(stats.peakDailyTokens),
            longestRunningTurnSeconds: Self.nonnegative(stats.longestRunningTurnSeconds),
            currentStreakDays: Self.nonnegative(stats.currentStreakDays),
            longestStreakDays: Self.nonnegative(stats.longestStreakDays),
            dailyBuckets: Self.validatedBuckets(stats.dailyUsageBuckets),
            insights: CodexProfileInsights(
                fastModePercent: Self.percentage(stats.fastModePercent),
                reasoningEffort: Self.boundedText(stats.reasoningEffort),
                reasoningEffortPercent: Self.percentage(stats.reasoningEffortPercent),
                uniqueSkillsUsed: Self.nonnegative(stats.uniqueSkillsUsed),
                totalSkillsUsed: Self.nonnegative(stats.totalSkillsUsed),
                totalChats: Self.nonnegative(stats.totalChats)
            ),
            invocations: Self.validatedInvocations(stats.topInvocations),
            fetchedAt: fetchedAt
        )
    }

    private static func validatedBuckets(
        _ values: [DailyBucketDTO]?,
    ) -> [CodexProfileDailyBucket] {
        guard let values else { return [] }
        var dates = Set<Date>()
        var result: [CodexProfileDailyBucket] = []
        for value in values {
            guard let text = value.startDate,
                  let date = CodexProfileDateParser.parse(text),
                  dates.insert(date).inserted,
                  let tokens = nonnegative(value.tokens) else { return [] }
            result.append(CodexProfileDailyBucket(date: date, tokens: tokens))
        }
        return result.sorted { $0.date < $1.date }
    }

    private static func validatedInvocations(
        _ values: [LossyInvocationDTO]?
    ) -> [CodexProfileInvocation] {
        guard let values else { return [] }
        var usedIDs = Set<String>()
        let invocations: [CodexProfileInvocation] = values.compactMap { lossy in
            guard let value = lossy.value,
                  let kind = value.type.flatMap(CodexProfileInvocation.Kind.init(rawValue:)),
                  let usageCount = nonnegative(value.usageCount) else { return nil }
            let preferredName = kind == .plugin ? value.pluginName : value.skillName
            guard let displayName = boundedText(preferredName ?? value.pluginName ?? value.skillName)
            else { return nil }
            let preferredID = kind == .plugin ? value.pluginID : value.skillID
            let baseID = boundedText(preferredID) ?? displayName
            let id = "\(kind.rawValue):\(baseID)"
            guard usedIDs.insert(id).inserted else { return nil }
            return CodexProfileInvocation(
                id: id,
                displayName: displayName,
                kind: kind,
                usageCount: usageCount
            )
        }
        let ranked = invocations.sorted {
            guard $0.usageCount == $1.usageCount else {
                return $0.usageCount > $1.usageCount
            }
            let nameOrder = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
            guard nameOrder == .orderedSame else { return nameOrder == .orderedAscending }
            guard $0.displayName != $1.displayName else { return $0.id < $1.id }
            return $0.displayName < $1.displayName
        }
        return Array(ranked.prefix(Self.maximumInvocationCount))
    }

    private static func nonnegative<T: BinaryInteger>(_ value: T?) -> T? {
        guard let value, value >= 0 else { return nil }
        return value
    }

    private static func percentage(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (0 ... 100).contains(value) else { return nil }
        return value
    }

    private static func boundedText(_ value: String?) -> String? {
        BoundedText.trimmedNonEmpty(value)
    }
}

enum CodexProfileDateParser {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    static func parse(_ text: String) -> Date? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isNumber) }),
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        var components = DateComponents()
        components.calendar = Self.calendar
        components.timeZone = Self.calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        guard let date = Self.calendar.date(from: components) else { return nil }
        let roundTrip = Self.calendar.dateComponents([.year, .month, .day], from: date)
        guard roundTrip.year == year,
              roundTrip.month == month,
              roundTrip.day == day else { return nil }
        return Self.calendar.startOfDay(for: date)
    }
}

private struct StatsDTO: Decodable {
    let lifetimeTokens: Int64?
    let peakDailyTokens: Int64?
    let longestRunningTurnSeconds: Int64?
    let currentStreakDays: Int?
    let longestStreakDays: Int?
    let dailyUsageBuckets: [DailyBucketDTO]?
    let fastModePercent: Double?
    let reasoningEffort: String?
    let reasoningEffortPercent: Double?
    let uniqueSkillsUsed: Int?
    let totalSkillsUsed: Int64?
    let totalChats: Int64?
    let topInvocations: [LossyInvocationDTO]?

    enum CodingKeys: String, CodingKey {
        case lifetimeTokens = "lifetime_tokens"
        case peakDailyTokens = "peak_daily_tokens"
        case longestRunningTurnSeconds = "longest_running_turn_sec"
        case currentStreakDays = "current_streak_days"
        case longestStreakDays = "longest_streak_days"
        case dailyUsageBuckets = "daily_usage_buckets"
        case fastModePercent = "fast_mode_usage_percentage"
        case reasoningEffort = "most_used_reasoning_effort"
        case reasoningEffortPercent = "most_used_reasoning_effort_percentage"
        case uniqueSkillsUsed = "unique_skills_used"
        case totalSkillsUsed = "total_skills_used"
        case totalChats = "total_threads"
        case topInvocations = "top_invocations"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lifetimeTokens = try? container.decodeIfPresent(Int64.self, forKey: .lifetimeTokens)
        peakDailyTokens = try? container.decodeIfPresent(Int64.self, forKey: .peakDailyTokens)
        longestRunningTurnSeconds = try? container.decodeIfPresent(
            Int64.self,
            forKey: .longestRunningTurnSeconds
        )
        currentStreakDays = try? container.decodeIfPresent(Int.self, forKey: .currentStreakDays)
        longestStreakDays = try? container.decodeIfPresent(Int.self, forKey: .longestStreakDays)
        dailyUsageBuckets = try? container.decodeIfPresent(
            [DailyBucketDTO].self,
            forKey: .dailyUsageBuckets
        )
        fastModePercent = try? container.decodeIfPresent(Double.self, forKey: .fastModePercent)
        reasoningEffort = try? container.decodeIfPresent(String.self, forKey: .reasoningEffort)
        reasoningEffortPercent = try? container.decodeIfPresent(
            Double.self,
            forKey: .reasoningEffortPercent
        )
        uniqueSkillsUsed = try? container.decodeIfPresent(Int.self, forKey: .uniqueSkillsUsed)
        totalSkillsUsed = try? container.decodeIfPresent(Int64.self, forKey: .totalSkillsUsed)
        totalChats = try? container.decodeIfPresent(Int64.self, forKey: .totalChats)
        topInvocations = try? container.decodeIfPresent(
            [LossyInvocationDTO].self,
            forKey: .topInvocations
        )
    }
}

private struct DailyBucketDTO: Decodable {
    let startDate: String?
    let tokens: Int64?

    enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
        case tokens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startDate = try? container.decodeIfPresent(String.self, forKey: .startDate)
        tokens = try? container.decodeIfPresent(Int64.self, forKey: .tokens)
    }
}

private struct InvocationDTO: Decodable {
    let pluginID: String?
    let pluginName: String?
    let skillID: String?
    let skillName: String?
    let type: String?
    let usageCount: Int64?

    enum CodingKeys: String, CodingKey {
        case pluginID = "plugin_id"
        case pluginName = "plugin_name"
        case skillID = "skill_id"
        case skillName = "skill_name"
        case type
        case usageCount = "usage_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pluginID = try? container.decodeIfPresent(String.self, forKey: .pluginID)
        pluginName = try? container.decodeIfPresent(String.self, forKey: .pluginName)
        skillID = try? container.decodeIfPresent(String.self, forKey: .skillID)
        skillName = try? container.decodeIfPresent(String.self, forKey: .skillName)
        type = try? container.decodeIfPresent(String.self, forKey: .type)
        usageCount = try? container.decodeIfPresent(Int64.self, forKey: .usageCount)
    }
}

private struct LossyInvocationDTO: Decodable {
    let value: InvocationDTO?

    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(InvocationDTO.self)
    }
}
