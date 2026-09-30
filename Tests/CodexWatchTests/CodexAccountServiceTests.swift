import Foundation
import XCTest
@testable import CodexWatch

final class CodexAccountServiceTests: XCTestCase {
    func testChatGPTAccountReadsOfficialQuotaAndLifetimeSurfaces() async throws {
        let client = AppServerAccountClientFake(
            account: AppServerAccountResponse(
                account: .chatGPT(planType: .plus),
                requiresOpenAIAuth: true
            ),
            rateLimits: rateLimits(),
            usage: usage()
        )
        let service = CodexAccountService(client: client)
        let fetchedAt = Date(timeIntervalSince1970: 2_000_000_000)

        let quota = try await service.fetchQuota(fetchedAt: fetchedAt)
        let profile = try await service.fetchProfile(fetchedAt: fetchedAt)

        XCTAssertEqual(quota.plan, .plus)
        XCTAssertEqual(quota.weeklyWindow?.usedPercent, 40)
        XCTAssertEqual(profile.lifetimeTokens, 123)
        let startCount = await client.startCount()
        XCTAssertEqual(startCount, 1)
    }

    func testNonChatGPTAccountFailsWithSignInRequired() async {
        for account in [AppServerAccount.apiKey, .amazonBedrock, .unsupported] {
            let client = AppServerAccountClientFake(
                account: AppServerAccountResponse(account: account, requiresOpenAIAuth: true),
                rateLimits: rateLimits(), usage: usage()
            )
            let service = CodexAccountService(client: client)
            do {
                _ = try await service.fetchQuota(fetchedAt: Date.now)
                XCTFail("Expected ChatGPT sign-in requirement")
            } catch {
                XCTAssertEqual(error as? CodexAccountServiceError, .signInRequired)
            }
            await service.stop()
        }
    }

    func testResetRequiresValidUUIDAndForwardsTheSelectedCredit() async throws {
        let client = AppServerAccountClientFake(
            account: AppServerAccountResponse(
                account: .chatGPT(planType: .plus),
                requiresOpenAIAuth: true
            ),
            rateLimits: rateLimits(),
            usage: usage()
        )
        let service = CodexAccountService(client: client)
        let key = "8ae96ff3-3425-4f4c-8772-b6fd61502868"

        let outcome = try await service.consumeReset(
            idempotencyKey: key,
            creditID: "RateLimitResetCredit_1"
        )

        XCTAssertEqual(outcome, .reset)
        let request = await client.lastResetRequest()
        XCTAssertEqual(request?.idempotencyKey, key)
        XCTAssertEqual(request?.creditID, "RateLimitResetCredit_1")
    }

    private func rateLimits() -> AppServerRateLimitsResponse {
        let base = AppServerRateLimitSnapshot(
            limitID: "codex",
            limitName: nil,
            primary: AppServerRateLimitWindow(
                usedPercent: 20,
                windowDurationMinutes: 300,
                resetsAt: nil
            ),
            secondary: AppServerRateLimitWindow(
                usedPercent: 40,
                windowDurationMinutes: 10_080,
                resetsAt: nil
            ),
            credits: nil,
            individualLimit: nil,
            spendControlReached: nil,
            planType: .plus,
            reachedReason: nil
        )
        return AppServerRateLimitsResponse(
            rateLimits: base,
            rateLimitsByLimitID: nil,
            resetCredits: nil
        )
    }

    private func usage() -> AppServerAccountUsageResponse {
        AppServerAccountUsageResponse(
            summary: AppServerAccountUsageSummary(
                lifetimeTokens: 123,
                peakDailyTokens: nil,
                longestRunningTurnSeconds: nil,
                currentStreakDays: nil,
                longestStreakDays: nil
            ),
            dailyUsageBuckets: nil
        )
    }
}

private actor AppServerAccountClientFake: AppServerAccountServing {
    struct ResetRequest: Equatable, Sendable {
        let idempotencyKey: String
        let creditID: String?
    }

    private let account: AppServerAccountResponse
    private let rateLimits: AppServerRateLimitsResponse
    private let usage: AppServerAccountUsageResponse
    private var starts = 0
    private var resetRequest: ResetRequest?

    init(
        account: AppServerAccountResponse,
        rateLimits: AppServerRateLimitsResponse,
        usage: AppServerAccountUsageResponse
    ) {
        self.account = account
        self.rateLimits = rateLimits
        self.usage = usage
    }

    func start() async throws {
        starts += 1
    }

    func readAccount() async throws -> AppServerAccountResponse { account }
    func readRateLimits() async throws -> AppServerRateLimitsResponse { rateLimits }
    func readAccountUsage() async throws -> AppServerAccountUsageResponse { usage }

    func consumeRateLimitReset(
        idempotencyKey: String,
        creditID: String?
    ) async throws -> AppServerResetOutcome {
        resetRequest = ResetRequest(idempotencyKey: idempotencyKey, creditID: creditID)
        return .reset
    }

    func accountUpdates() async -> AsyncStream<AppServerAccountUpdate> {
        AsyncStream { $0.finish() }
    }

    func stop() async {}

    func startCount() -> Int { starts }
    func lastResetRequest() -> ResetRequest? { resetRequest }
}
