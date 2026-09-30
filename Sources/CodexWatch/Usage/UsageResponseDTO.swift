import Foundation

struct UsageResponseDTO: Decodable {
    let planType: String?
    let primaryWindow: WindowDTO?
    let secondaryWindow: WindowDTO?
    let rateLimit: RateLimitDTO?
    private let additionalRateLimits: [AdditionalRateLimitDTO]
    let codeReviewRateLimit: RateLimitDTO?
    let spendControl: SpendControlDTO?
    let rateLimitResetCredits: ResetCreditsDTO?
    let credits: CreditsDTO?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
        case rateLimit = "rate_limit"
        case additionalRateLimits = "additional_rate_limits"
        case codeReviewRateLimit = "code_review_rate_limit"
        case spendControl = "spend_control"
        case rateLimitResetCredits = "rate_limit_reset_credits"
        case credits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        planType = try? container.decodeIfPresent(String.self, forKey: .planType)
        primaryWindow = try? container.decodeIfPresent(WindowDTO.self, forKey: .primaryWindow)
        secondaryWindow = try? container.decodeIfPresent(WindowDTO.self, forKey: .secondaryWindow)
        rateLimit = try? container.decodeIfPresent(RateLimitDTO.self, forKey: .rateLimit)
        codeReviewRateLimit = try? container.decodeIfPresent(
            RateLimitDTO.self,
            forKey: .codeReviewRateLimit
        )
        spendControl = try? container.decodeIfPresent(SpendControlDTO.self, forKey: .spendControl)
        rateLimitResetCredits = try? container.decodeIfPresent(
            ResetCreditsDTO.self,
            forKey: .rateLimitResetCredits
        )
        credits = try? container.decodeIfPresent(CreditsDTO.self, forKey: .credits)
        additionalRateLimits = (try? container.decodeIfPresent(
            [LossyAdditionalRateLimitDTO].self,
            forKey: .additionalRateLimits
        ))?.compactMap(\.value) ?? []
    }

    func snapshot(fetchedAt: Date = .now) -> UsageSnapshot {
        // The current ChatGPT endpoint nests the windows under `rate_limit`.
        // Keep the top-level fields as a compatibility fallback because older
        // responses (and our fixtures) exposed them directly.
        let windows = [
            makeWindow(id: "primary", dto: primaryWindow ?? rateLimit?.primaryWindow),
            makeWindow(id: "secondary", dto: secondaryWindow ?? rateLimit?.secondaryWindow)
        ].compactMap { $0 }

        return UsageSnapshot(
            plan: planType.flatMap(ChatGPTPlan.init(apiValue:)),
            creditsRemaining: credits?.validatedRemaining,
            windows: windows,
            additionalWindows: makeAdditionalWindows(),
            codeReviewWindows: makeCodeReviewWindows(),
            spendControl: spendControl?.validatedSummary,
            availableResetCredits: availableResetCredits,
            fetchedAt: fetchedAt
        )
    }

    private var availableResetCredits: Int? {
        guard let count = rateLimitResetCredits?.availableCount, count >= 0 else { return nil }
        return count
    }

    private func makeWindow(id: String, dto: WindowDTO?) -> UsageWindow? {
        guard let dto,
              let usedPercent = dto.usedPercent,
              usedPercent.isFinite,
              let seconds = dto.limitWindowSeconds,
              seconds > 0 else {
            return nil
        }

        return UsageWindow(
            id: id,
            kind: UsageWindowClassifier.kind(seconds: seconds),
            usedPercent: usedPercent,
            resetAt: dto.resetAt,
            durationSeconds: TimeInterval(seconds)
        )
    }

    private func makeAdditionalWindows() -> [NamedUsageWindow] {
        var usedIDs = Set<String>()
        var result: [NamedUsageWindow] = []

        for entry in additionalRateLimits {
            let isSpark = [entry.limitName, entry.meteredFeature]
                .compactMap { $0?.lowercased() }
                .contains { $0.contains("spark") }
            if isSpark {
                let candidates: [(WindowDTO?, String)] = [
                    (entry.rateLimit?.primaryWindow, "codex-spark"),
                    (entry.rateLimit?.secondaryWindow, "codex-spark-weekly")
                ]
                for (dto, fallbackID) in candidates {
                    guard let dto,
                          let seconds = dto.limitWindowSeconds,
                          let window = makeWindow(id: fallbackID, dto: dto) else { continue }
                    let isWeekly = seconds >= 6 * 24 * 60 * 60
                    let preferredID = isWeekly ? "codex-spark-weekly" : "codex-spark"
                    let id = Self.uniqueID(preferredID, usedIDs: &usedIDs)
                    let title = isWeekly ? "Codex Spark Weekly" : "Codex Spark 5-hour"
                    result.append(NamedUsageWindow(id: id, title: title, window: windowWithID(id, from: window)))
                }
                continue
            }

            guard let source = firstNonEmpty(entry.meteredFeature, entry.limitName) else {
                continue
            }
            let baseID = Self.slugID(source)
            guard !baseID.isEmpty else { continue }
            let baseTitle = firstNonEmpty(entry.limitName, entry.meteredFeature) ?? "Codex extra limit"
            let candidates: [(WindowDTO?, String)] = [
                (entry.rateLimit?.primaryWindow, "primary"),
                (entry.rateLimit?.secondaryWindow, "secondary")
            ]
            for (dto, role) in candidates {
                let preferredID = Self.appendingIDRole(role, to: baseID)
                guard let window = makeWindow(id: preferredID, dto: dto) else { continue }
                let id = Self.uniqueID(preferredID, usedIDs: &usedIDs)
                let title = Self.windowTitle(base: baseTitle, kind: window.kind)
                result.append(NamedUsageWindow(
                    id: id,
                    title: title,
                    window: windowWithID(id, from: window)
                ))
            }
        }
        return result
    }

    private func makeCodeReviewWindows() -> [NamedUsageWindow] {
        let candidates: [(String, String, WindowDTO?)] = [
            ("code-review-primary", "Code Review", codeReviewRateLimit?.primaryWindow),
            ("code-review-secondary", "Code Review Weekly", codeReviewRateLimit?.secondaryWindow)
        ]
        return candidates.compactMap { id, title, dto in
            makeWindow(id: id, dto: dto).map {
                NamedUsageWindow(id: id, title: title, window: $0)
            }
        }
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    private func windowWithID(_ id: String, from window: UsageWindow) -> UsageWindow {
        UsageWindow(
            id: id,
            kind: window.kind,
            usedPercent: window.usedPercent,
            resetAt: window.resetAt,
            durationSeconds: window.durationSeconds
        )
    }

    private static func slugID(_ value: String) -> String {
        var slug = ""
        var lastWasDash = false
        let maximumSlugLength = 64 - "codex-".count
        for scalar in value.lowercased().unicodeScalars {
            let isASCIIAlphaNumeric = (97 ... 122).contains(scalar.value)
                || (48 ... 57).contains(scalar.value)
            if isASCIIAlphaNumeric {
                guard slug.utf8.count < maximumSlugLength else { break }
                slug.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !slug.isEmpty, !lastWasDash {
                guard slug.utf8.count < maximumSlugLength else { break }
                slug.append("-")
                lastWasDash = true
            }
        }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "" : "codex-\(slug)"
    }

    private static func appendingIDRole(_ role: String, to baseID: String) -> String {
        let suffix = "-\(role)"
        let maximumBaseLength = max(0, 64 - suffix.utf8.count)
        let boundedBase = String(baseID.prefix(maximumBaseLength))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return boundedBase + suffix
    }

    private static func uniqueID(_ preferredID: String, usedIDs: inout Set<String>) -> String {
        if usedIDs.insert(preferredID).inserted { return preferredID }
        var counter = 2
        while true {
            let suffix = "-\(counter)"
            let maximumBaseLength = max(0, 64 - suffix.utf8.count)
            let boundedBase = String(preferredID.prefix(maximumBaseLength))
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            let candidate = boundedBase + suffix
            if usedIDs.insert(candidate).inserted { return candidate }
            counter += 1
        }
    }

    private static func windowTitle(base: String, kind: UsageWindowKind) -> String {
        let suffix: String
        switch kind {
        case let .rolling(hours): suffix = " \(hours)-hour"
        case .daily: suffix = " Daily"
        case .weekly: suffix = " Weekly"
        case .custom: suffix = " Quota"
        }
        return boundedText(base, maximumUTF8Bytes: 128 - suffix.utf8.count) + suffix
    }

    private static func boundedText(_ value: String, maximumUTF8Bytes: Int = 128) -> String {
        BoundedText.trimmed(value, maximumUTF8Bytes: maximumUTF8Bytes)
    }
}

private struct LossyAdditionalRateLimitDTO: Decodable {
    let value: AdditionalRateLimitDTO?

    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(AdditionalRateLimitDTO.self)
    }
}

private struct AdditionalRateLimitDTO: Decodable {
    let limitName: String?
    let meteredFeature: String?
    let rateLimit: RateLimitDTO?

    enum CodingKeys: String, CodingKey {
        case limitName = "limit_name"
        case meteredFeature = "metered_feature"
        case rateLimit = "rate_limit"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limitName = try? container.decodeIfPresent(String.self, forKey: .limitName)
        meteredFeature = try? container.decodeIfPresent(String.self, forKey: .meteredFeature)
        rateLimit = try? container.decodeIfPresent(RateLimitDTO.self, forKey: .rateLimit)
    }
}

struct CreditsDTO: Decodable {
    let hasCredits: Bool?
    let unlimited: Bool?
    let balance: String?

    enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited
        case balance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasCredits = try? container.decodeIfPresent(Bool.self, forKey: .hasCredits)
        unlimited = try? container.decodeIfPresent(Bool.self, forKey: .unlimited)
        if let text = try? container.decodeIfPresent(String.self, forKey: .balance) {
            balance = text
        } else if let number = try? container.decodeIfPresent(Decimal.self, forKey: .balance) {
            balance = NSDecimalNumber(decimal: number).stringValue
        } else {
            balance = nil
        }
    }

    var validatedRemaining: CreditsRemaining? {
        if unlimited == true { return .unlimited }
        guard let hasCredits, let balance else { return nil }
        let trimmed = balance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 64,
              let value = ValidatedDecimal.parse(trimmed),
              !value.isNaN,
              hasCredits || value <= 0 else { return nil }
        return .balance(trimmed)
    }
}

struct ResetCreditsDTO: Decodable {
    let availableCount: Int?

    enum CodingKeys: String, CodingKey {
        case availableCount = "available_count"
    }
}

struct ResetCreditDetailsDTO: Decodable {
    private let credits: [LossyResetCreditDTO]

    enum CodingKeys: String, CodingKey {
        case credits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        credits = (try? container.decodeIfPresent([LossyResetCreditDTO].self, forKey: .credits)) ?? []
    }

    func inventory() -> [ResetCredit] {
        credits.enumerated().compactMap { index, lossy in
            guard let dto = lossy.value,
                  let status = Self.boundedNonEmpty(dto.status, maximumUTF8Bytes: 64) else {
                return nil
            }
            let id = Self.boundedNonEmpty(dto.id, maximumUTF8Bytes: 256)
                ?? "reset-credit-\(index)"
            return ResetCredit(
                id: id,
                status: status,
                title: Self.boundedNonEmpty(dto.title, maximumUTF8Bytes: 256),
                grantedAt: dto.grantedAt,
                expiresAt: dto.expiresAt,
                isSupportedByPlan: dto.isSupportedByPlan
            )
        }
    }

    private static func boundedNonEmpty(
        _ value: String?,
        maximumUTF8Bytes: Int
    ) -> String? {
        BoundedText.trimmedNonEmpty(value, maximumUTF8Bytes: maximumUTF8Bytes)
    }
}

private struct LossyResetCreditDTO: Decodable {
    let value: ResetCreditDTO?

    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(ResetCreditDTO.self)
    }
}

struct ResetCreditDTO: Decodable {
    let id: String?
    let status: String?
    let title: String?
    let grantedAt: Date?
    let expiresAt: Date?
    let isSupportedByPlan: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case title
        case grantedAt = "granted_at"
        case expiresAt = "expires_at"
        case isSupportedByPlan = "is_supported_by_plan"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decodeIfPresent(String.self, forKey: .id)
        status = try? container.decodeIfPresent(String.self, forKey: .status)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        isSupportedByPlan = try? container.decodeIfPresent(Bool.self, forKey: .isSupportedByPlan)
        grantedAt = container.decodeISO8601DateIfPresent(forKey: .grantedAt)
        expiresAt = container.decodeISO8601DateIfPresent(forKey: .expiresAt)
    }
}

struct SpendControlDTO: Decodable {
    let individualLimit: SpendControlLimitDTO?

    enum CodingKeys: String, CodingKey {
        case individualLimit = "individual_limit"
    }
}

struct SpendControlLimitDTO: Decodable {
    let limit: Decimal?
    let used: Decimal?
    let remainingPercent: Double?
    let resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case limit
        case used
        case remainingPercent = "remaining_percent"
        case resetsAt = "resets_at"
        case resetAt = "reset_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limit = Self.decodeDecimal(container, forKey: .limit)
        used = Self.decodeDecimal(container, forKey: .used)
        remainingPercent = Self.decodeDouble(container, forKey: .remainingPercent)
        resetsAt = Self.decodeDate(container, forKeys: [.resetsAt, .resetAt])
    }

    var validatedSummary: SpendControlSummary? {
        guard let limit,
              let used,
              !limit.isNaN,
              !used.isNaN,
              limit >= 0,
              used >= 0 else { return nil }
        if let remainingPercent,
           (!remainingPercent.isFinite || !(0 ... 100).contains(remainingPercent)) {
            return nil
        }
        return SpendControlSummary(
            limit: limit,
            used: used,
            remainingPercent: remainingPercent,
            resetsAt: resetsAt
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

    private static func decodeDouble(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Double? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        guard let value = try? container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func decodeDate(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKeys keys: [CodingKeys]
    ) -> Date? {
        for key in keys {
            if let value = decodeDouble(container, forKey: key) {
                let seconds = value > 1_000_000_000_000 ? value / 1_000 : value
                if seconds.isFinite,
                   (0 ... Date.distantFuture.timeIntervalSince1970).contains(seconds) {
                    return Date(timeIntervalSince1970: seconds)
                }
            }
        }
        return nil
    }
}

private extension SpendControlDTO {
    var validatedSummary: SpendControlSummary? {
        individualLimit?.validatedSummary
    }
}

struct RateLimitDTO: Decodable {
    let primaryWindow: WindowDTO?
    let secondaryWindow: WindowDTO?

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        primaryWindow = try? container.decodeIfPresent(WindowDTO.self, forKey: .primaryWindow)
        secondaryWindow = try? container.decodeIfPresent(WindowDTO.self, forKey: .secondaryWindow)
    }
}

struct WindowDTO: Decodable {
    let usedPercent: Double?
    let limitWindowSeconds: Int?
    let resetAt: Date?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAt = "reset_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercent = try container.decodeIfPresent(Double.self, forKey: .usedPercent)
        limitWindowSeconds = try container.decodeIfPresent(Int.self, forKey: .limitWindowSeconds)

        if let epoch = try? container.decode(Double.self, forKey: .resetAt) {
            let seconds = epoch > 1_000_000_000_000 ? epoch / 1_000 : epoch
            if seconds.isFinite,
               (0 ... Date.distantFuture.timeIntervalSince1970).contains(seconds) {
                resetAt = Date(timeIntervalSince1970: seconds)
            } else {
                resetAt = nil
            }
        } else if let text = try? container.decode(String.self, forKey: .resetAt) {
            resetAt = ISO8601Parsing.date(from: text)
        } else {
            resetAt = nil
        }
    }
}

private extension KeyedDecodingContainer {
    func decodeISO8601DateIfPresent(forKey key: Key) -> Date? {
        guard let text = try? decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        return ISO8601Parsing.date(from: text)
    }
}
