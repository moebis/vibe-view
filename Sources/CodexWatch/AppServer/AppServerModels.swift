import Foundation

enum AppServerPlanType: String, Decodable, CaseIterable, Hashable, Sendable {
    case free
    case go
    case plus
    case pro
    case prolite
    case team
    case selfServeBusinessProlite = "self_serve_business_prolite"
    case selfServeBusinessUsageBased = "self_serve_business_usage_based"
    case business
    case ent26
    case enterpriseCBPAutomation = "enterprise_cbp_automation"
    case enterpriseCBPUsageBased = "enterprise_cbp_usage_based"
    case enterprise
    case edu
    case eduPlus = "edu_plus"
    case eduPro = "edu_pro"
    case unknown

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .unknown
    }
}

struct AppServerClientInfo: Encodable, Equatable, Sendable {
    let name: String
    let title: String?
    let version: String
}

enum AppServerAccount: Equatable, Sendable {
    case apiKey
    case chatGPT(planType: AppServerPlanType)
    case amazonBedrock(usesCodexManagedCredentials: Bool)
}

extension AppServerAccount: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type
        case planType
        case usesCodexManagedCredentials
    }

    private enum AccountType: String, Decodable {
        case apiKey
        case chatgpt
        case amazonBedrock
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(AccountType.self, forKey: .type) {
        case .apiKey:
            self = .apiKey
        case .chatgpt:
            self = try .chatGPT(
                planType: container.decode(AppServerPlanType.self, forKey: .planType)
            )
        case .amazonBedrock:
            self = try .amazonBedrock(
                usesCodexManagedCredentials: container.decode(
                    Bool.self,
                    forKey: .usesCodexManagedCredentials
                )
            )
        }
    }
}

struct AppServerAccountResponse: Decodable, Equatable, Sendable {
    let account: AppServerAccount?
    let requiresOpenAIAuth: Bool

    private enum CodingKeys: String, CodingKey {
        case account
        case requiresOpenAIAuth = "requiresOpenaiAuth"
    }
}

struct AppServerRateLimitWindow: Decodable, Equatable, Sendable {
    let usedPercent: Int
    let windowDurationMinutes: Int64?
    let resetsAt: Int64?

    private enum CodingKeys: String, CodingKey {
        case usedPercent
        case windowDurationMinutes = "windowDurationMins"
        case resetsAt
    }
}

struct AppServerCreditsSnapshot: Decodable, Equatable, Sendable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?
}

struct AppServerSpendControlLimit: Decodable, Equatable, Sendable {
    let limit: String
    let used: String
    let remainingPercent: Double
    let resetsAt: Int64
}

enum AppServerRateLimitReachedReason: String, Decodable, Equatable, Sendable {
    case rateLimitReached = "rate_limit_reached"
    case workspaceOwnerCreditsDepleted = "workspace_owner_credits_depleted"
    case workspaceMemberCreditsDepleted = "workspace_member_credits_depleted"
    case workspaceOwnerUsageLimitReached = "workspace_owner_usage_limit_reached"
    case workspaceMemberUsageLimitReached = "workspace_member_usage_limit_reached"
    case unknown

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .unknown
    }
}

struct AppServerRateLimitSnapshot: Decodable, Equatable, Sendable {
    let limitID: String?
    let limitName: String?
    let primary: AppServerRateLimitWindow?
    let secondary: AppServerRateLimitWindow?
    let credits: AppServerCreditsSnapshot?
    let individualLimit: AppServerSpendControlLimit?
    let spendControlReached: Bool?
    let planType: AppServerPlanType?
    let reachedReason: AppServerRateLimitReachedReason?

    private enum CodingKeys: String, CodingKey {
        case limitID = "limitId"
        case limitName
        case primary
        case secondary
        case credits
        case individualLimit
        case spendControlReached
        case planType
        case reachedReason = "rateLimitReachedType"
    }
}

enum AppServerResetCreditType: String, Decodable, Equatable, Sendable {
    case codexRateLimits
    case unknown

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .unknown
    }
}

enum AppServerResetCreditStatus: String, Decodable, Equatable, Sendable {
    case available
    case redeeming
    case redeemed
    case unknown

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .unknown
    }
}

struct AppServerResetCredit: Decodable, Equatable, Sendable {
    let id: String
    let resetType: AppServerResetCreditType
    let status: AppServerResetCreditStatus
    let grantedAt: Int64
    let expiresAt: Int64?
    let title: String?
    let description: String?
}

struct AppServerResetCreditsSummary: Decodable, Equatable, Sendable {
    let availableCount: Int64
    let credits: [AppServerResetCredit]?
}

struct AppServerRateLimitsResponse: Decodable, Equatable, Sendable {
    let rateLimits: AppServerRateLimitSnapshot
    let rateLimitsByLimitID: [String: AppServerRateLimitSnapshot]?
    let resetCredits: AppServerResetCreditsSummary?

    private enum CodingKeys: String, CodingKey {
        case rateLimits
        case rateLimitsByLimitID = "rateLimitsByLimitId"
        case resetCredits = "rateLimitResetCredits"
    }
}

struct AppServerAccountUsageSummary: Decodable, Equatable, Sendable {
    let lifetimeTokens: Int64?
    let peakDailyTokens: Int64?
    let longestRunningTurnSeconds: Int64?
    let currentStreakDays: Int64?
    let longestStreakDays: Int64?

    private enum CodingKeys: String, CodingKey {
        case lifetimeTokens
        case peakDailyTokens
        case longestRunningTurnSeconds = "longestRunningTurnSec"
        case currentStreakDays
        case longestStreakDays
    }
}

struct AppServerAccountUsageDailyBucket: Decodable, Equatable, Sendable {
    let startDate: String
    let tokens: Int64
}

struct AppServerAccountUsageResponse: Decodable, Equatable, Sendable {
    let summary: AppServerAccountUsageSummary
    let dailyUsageBuckets: [AppServerAccountUsageDailyBucket]?

    // The generated schema also exposes threadUsage. Vibe View intentionally
    // omits it so per-thread account data is neither retained nor surfaced.
}

enum AppServerResetOutcome: String, Decodable, Equatable, Sendable {
    case reset
    case nothingToReset
    case noCredit
    case alreadyRedeemed
}

struct AppServerResetResponse: Decodable, Equatable, Sendable {
    let outcome: AppServerResetOutcome
}

struct AppServerInitializeResponse: Decodable, Equatable, Sendable {
    let userAgent: String
    let codexHome: String
    let platformFamily: String
    let platformOs: String
}

struct AppServerRateLimitsUpdatedNotification: Decodable, Sendable {
    let rateLimits: AppServerRateLimitSnapshot
}
