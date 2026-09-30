import Foundation

struct UsageAnalyticsResponseDTO: Decodable {
    let data: [UsageAnalyticsDayDTO]
    let groupBy: String?

    enum CodingKeys: String, CodingKey {
        case data
        case groupBy = "group_by"
    }

    func dataset(
        requestedStart: Date,
        requestedEnd: Date,
        calendar: Calendar = .current,
        fetchedAt: Date = .now
    ) -> UsageAnalyticsDataset? {
        let normalizedStart = calendar.startOfDay(for: requestedStart)
        let normalizedEnd = calendar.startOfDay(for: requestedEnd)
        guard groupBy == "day", normalizedStart <= normalizedEnd else { return nil }

        var observedDates = Set<Date>()
        var validatedDays: [UsageAnalyticsDay] = []
        var modelBreakdownIsPartial = false
        var clientBreakdownIsPartial = false

        for day in data {
            guard let dateText = day.date,
                  let date = Self.parseDate(dateText, calendar: calendar),
                  (normalizedStart ... normalizedEnd).contains(date),
                  observedDates.insert(date).inserted,
                  let validatedTotals = day.totals?.validatedDayTotals else { return nil }

            var models: [UsageModelActivity] = []
            if day.modelBreakdownDecodeFailed { modelBreakdownIsPartial = true }
            for lossy in day.models ?? [] {
                guard let activity = lossy.value?.validatedActivity else {
                    modelBreakdownIsPartial = true
                    continue
                }
                models.append(activity)
            }

            var clients: [UsageClientActivity] = []
            if day.clientBreakdownDecodeFailed { clientBreakdownIsPartial = true }
            for lossy in day.clients ?? [] {
                guard let activity = lossy.value?.validatedActivity else {
                    clientBreakdownIsPartial = true
                    continue
                }
                clients.append(activity)
            }

            validatedDays.append(UsageAnalyticsDay(
                date: date,
                totals: validatedTotals.totals,
                models: models,
                clients: clients,
                tokenDataIsAvailable: validatedTotals.tokenDataIsAvailable
            ))
        }

        return UsageAnalyticsDataset(
            requestedStart: normalizedStart,
            requestedEnd: normalizedEnd,
            days: validatedDays.sorted { $0.date < $1.date },
            fetchedAt: fetchedAt,
            modelBreakdownIsPartial: modelBreakdownIsPartial,
            clientBreakdownIsPartial: clientBreakdownIsPartial
        )
    }

    private static func parseDate(_ text: String, calendar: Calendar) -> Date? {
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
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        guard let value = calendar.date(from: components) else { return nil }

        let roundTrip = calendar.dateComponents([.year, .month, .day], from: value)
        guard roundTrip.year == year,
              roundTrip.month == month,
              roundTrip.day == day else { return nil }
        return calendar.startOfDay(for: value)
    }
}

struct UsageAnalyticsDayDTO: Decodable {
    let date: String?
    let totals: UsageAnalyticsTotalsDTO?
    let models: [LossyUsageModelDTO]?
    let clients: [LossyUsageClientDTO]?
    let modelBreakdownDecodeFailed: Bool
    let clientBreakdownDecodeFailed: Bool

    enum CodingKeys: String, CodingKey {
        case date
        case totals
        case models
        case clients
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try? container.decodeIfPresent(String.self, forKey: .date)
        totals = try? container.decodeIfPresent(UsageAnalyticsTotalsDTO.self, forKey: .totals)

        do {
            models = try container.decodeIfPresent([LossyUsageModelDTO].self, forKey: .models)
            modelBreakdownDecodeFailed = models == nil
        } catch {
            models = nil
            modelBreakdownDecodeFailed = true
        }

        do {
            clients = try container.decodeIfPresent([LossyUsageClientDTO].self, forKey: .clients)
            clientBreakdownDecodeFailed = clients == nil
        } catch {
            clients = nil
            clientBreakdownDecodeFailed = true
        }
    }
}

struct UsageAnalyticsTotalsDTO: Decodable {
    let threads: Int64?
    let turns: Int64?
    let uncachedTextInputTokens: Int64?
    let cachedTextInputTokens: Int64?
    let textOutputTokens: Int64?
    let textTotalTokens: Int64?

    enum CodingKeys: String, CodingKey {
        case threads
        case turns
        case uncachedTextInputTokens = "uncached_text_input_tokens"
        case cachedTextInputTokens = "cached_text_input_tokens"
        case textOutputTokens = "text_output_tokens"
        case textTotalTokens = "text_total_tokens"
    }

    var isCompleteAndNonnegative: Bool {
        [
            threads,
            turns,
            uncachedTextInputTokens,
            cachedTextInputTokens,
            textOutputTokens,
            textTotalTokens
        ].allSatisfy { value in
            guard let value else { return false }
            return value >= 0
        }
    }

    var validatedTotals: UsageTokenTotals? {
        guard isCompleteAndNonnegative,
              let totalTokens = textTotalTokens,
              let uncachedInputTokens = uncachedTextInputTokens,
              let cachedInputTokens = cachedTextInputTokens,
              let outputTokens = textOutputTokens,
              let turns,
              let chats = threads else { return nil }
        return UsageTokenTotals(
            totalTokens: totalTokens,
            uncachedInputTokens: uncachedInputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens,
            turns: turns,
            chats: chats
        )
    }

    var validatedDayTotals: ValidatedAnalyticsDayTotals? {
        if let totals = validatedTotals {
            return ValidatedAnalyticsDayTotals(totals: totals, tokenDataIsAvailable: true)
        }

        let tokenValues = [
            uncachedTextInputTokens,
            cachedTextInputTokens,
            textOutputTokens,
            textTotalTokens
        ]
        guard tokenValues.allSatisfy({ $0 == nil }),
              let threads,
              threads >= 0,
              let turns,
              turns >= 0 else { return nil }
        return ValidatedAnalyticsDayTotals(
            totals: UsageTokenTotals(
                totalTokens: 0,
                uncachedInputTokens: 0,
                cachedInputTokens: 0,
                outputTokens: 0,
                turns: turns,
                chats: threads
            ),
            tokenDataIsAvailable: false
        )
    }

}

struct ValidatedAnalyticsDayTotals: Equatable {
    let totals: UsageTokenTotals
    let tokenDataIsAvailable: Bool
}

struct UsageAnalyticsModelDTO: Decodable {
    let model: String?
    let threads: Int64?
    let turns: Int64?
    let credits: Decimal?

    enum CodingKeys: String, CodingKey {
        case model
        case threads
        case turns
        case credits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try? container.decodeIfPresent(String.self, forKey: .model)
        threads = try? container.decodeIfPresent(Int64.self, forKey: .threads)
        turns = try? container.decodeIfPresent(Int64.self, forKey: .turns)
        credits = Self.decodeDecimal(container, forKey: .credits)
    }

    var validatedActivity: UsageModelActivity? {
        guard let model = boundedAnalyticsIdentifier(model),
              let threads,
              threads >= 0,
              let turns,
              turns >= 0,
              let credits,
              !credits.isNaN,
              credits >= 0 else { return nil }
        return UsageModelActivity(
            model: model,
            turns: turns,
            chats: threads,
            credits: credits
        )
    }

    private static func decodeDecimal(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Decimal? {
        if let value = try? container.decodeIfPresent(Decimal.self, forKey: key) {
            return value
        }
        guard let value = try? container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        return ValidatedDecimal.parse(value)
    }
}

struct UsageAnalyticsClientDTO: Decodable {
    let clientID: String?
    let totals: UsageAnalyticsTotalsDTO

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case threads
        case turns
        case uncachedTextInputTokens = "uncached_text_input_tokens"
        case cachedTextInputTokens = "cached_text_input_tokens"
        case textOutputTokens = "text_output_tokens"
        case textTotalTokens = "text_total_tokens"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clientID = try? container.decodeIfPresent(String.self, forKey: .clientID)
        totals = UsageAnalyticsTotalsDTO(
            threads: try? container.decodeIfPresent(Int64.self, forKey: .threads),
            turns: try? container.decodeIfPresent(Int64.self, forKey: .turns),
            uncachedTextInputTokens: try? container.decodeIfPresent(
                Int64.self,
                forKey: .uncachedTextInputTokens
            ),
            cachedTextInputTokens: try? container.decodeIfPresent(
                Int64.self,
                forKey: .cachedTextInputTokens
            ),
            textOutputTokens: try? container.decodeIfPresent(Int64.self, forKey: .textOutputTokens),
            textTotalTokens: try? container.decodeIfPresent(Int64.self, forKey: .textTotalTokens)
        )
    }

    var validatedActivity: UsageClientActivity? {
        guard let clientID = boundedAnalyticsIdentifier(clientID),
              let totals = totals.validatedTotals else { return nil }
        return UsageClientActivity(clientID: clientID, totals: totals)
    }
}

struct LossyUsageModelDTO: Decodable {
    let value: UsageAnalyticsModelDTO?

    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(UsageAnalyticsModelDTO.self)
    }
}

struct LossyUsageClientDTO: Decodable {
    let value: UsageAnalyticsClientDTO?

    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(UsageAnalyticsClientDTO.self)
    }
}

private func boundedAnalyticsIdentifier(_ value: String?) -> String? {
    BoundedText.trimmedNonEmpty(value)
}
