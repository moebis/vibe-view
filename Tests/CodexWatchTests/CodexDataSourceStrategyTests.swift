import Foundation
import XCTest
@testable import CodexWatch

final class CodexDataSourceStrategyTests: XCTestCase {
    func testOfficialQuotaIsPreferredOverLegacyFileCredentials() async {
        let account = CodexAccountServingFake(quota: snapshot(source: .appServer), profile: profile(1))
        let legacy = LegacyUsageServingFake(snapshot: snapshot(source: .legacyHTTPS), profile: profile(2))

        let attempt = await CodexDataSourceStrategy.fetchQuota(
            account: account,
            legacy: legacy,
            fetchedAt: .now
        )

        guard case let .success(value) = attempt else {
            return XCTFail("Expected official quota")
        }
        XCTAssertEqual(value.source, .appServer)
        let legacyFetches = await legacy.quotaFetchCount()
        XCTAssertEqual(legacyFetches, 0)
    }

    func testLegacyQuotaIsUsedOnlyWhenAppServerIsUnavailable() async {
        let account = CodexAccountServingFake(
            quota: snapshot(source: .appServer),
            profile: profile(1),
            failure: .unavailable
        )
        let legacy = LegacyUsageServingFake(snapshot: snapshot(source: .legacyHTTPS), profile: profile(2))

        let attempt = await CodexDataSourceStrategy.fetchQuota(
            account: account,
            legacy: legacy,
            fetchedAt: .now
        )

        guard case let .success(value) = attempt else {
            return XCTFail("Expected compatibility quota")
        }
        XCTAssertEqual(value.source, .legacyHTTPS)
        let legacyFetches = await legacy.quotaFetchCount()
        XCTAssertEqual(legacyFetches, 1)
    }

    func testRichLegacyLifetimeIsPreferredAndOfficialLifetimeIsTheFallback() async {
        let account = CodexAccountServingFake(quota: snapshot(source: .appServer), profile: profile(1))
        let legacy = LegacyUsageServingFake(snapshot: snapshot(source: .legacyHTTPS), profile: profile(2))

        let legacyAttempt = await CodexDataSourceStrategy.fetchProfile(
            account: account,
            legacy: legacy,
            fetchedAt: .now
        )
        guard case let .success(legacyProfile) = legacyAttempt else {
            return XCTFail("Expected rich compatibility profile")
        }
        XCTAssertEqual(legacyProfile.lifetimeTokens, 2)

        await legacy.setProfileFailure(true)
        let officialAttempt = await CodexDataSourceStrategy.fetchProfile(
            account: account,
            legacy: legacy,
            fetchedAt: .now
        )
        guard case let .success(officialProfile) = officialAttempt else {
            return XCTFail("Expected official lifetime fallback")
        }
        XCTAssertEqual(officialProfile.lifetimeTokens, 1)
    }

    private func snapshot(source: UsageDataSource) -> UsageSnapshot {
        UsageSnapshot(
            windows: [UsageWindow(id: "weekly", kind: .weekly, usedPercent: 20)],
            fetchedAt: Date(timeIntervalSince1970: 100),
            source: source
        )
    }

    private func profile(_ tokens: Int64) -> CodexProfileStats {
        CodexProfileStats(
            lifetimeTokens: tokens,
            peakDailyTokens: nil,
            longestRunningTurnSeconds: nil,
            currentStreakDays: nil,
            longestStreakDays: nil,
            dailyBuckets: [],
            insights: CodexProfileInsights(
                fastModePercent: nil,
                reasoningEffort: nil,
                reasoningEffortPercent: nil,
                uniqueSkillsUsed: nil,
                totalSkillsUsed: nil,
                totalChats: nil
            ),
            invocations: [],
            fetchedAt: Date(timeIntervalSince1970: 100)
        )
    }
}

private actor CodexAccountServingFake: CodexAccountServing {
    private let quota: UsageSnapshot
    private let profile: CodexProfileStats
    private let failure: CodexAccountServiceError?

    init(
        quota: UsageSnapshot,
        profile: CodexProfileStats,
        failure: CodexAccountServiceError? = nil
    ) {
        self.quota = quota
        self.profile = profile
        self.failure = failure
    }

    func fetchQuota(fetchedAt: Date) async throws -> UsageSnapshot {
        if let failure { throw failure }
        return quota
    }

    func fetchProfile(fetchedAt: Date) async throws -> CodexProfileStats {
        if let failure { throw failure }
        return profile
    }

    func consumeReset(idempotencyKey: String, creditID: String?) async throws -> AppServerResetOutcome {
        .reset
    }

    func accountUpdates() async throws -> AsyncStream<AppServerAccountUpdate> {
        AsyncStream { $0.finish() }
    }

    func stop() async {}
}

private actor LegacyUsageServingFake: LegacyUsageServing {
    private let snapshot: UsageSnapshot
    private let profile: CodexProfileStats
    private var profileFails = false
    private var quotaFetches = 0

    init(snapshot: UsageSnapshot, profile: CodexProfileStats) {
        self.snapshot = snapshot
        self.profile = profile
    }

    func fetch() async throws -> UsageSnapshot {
        quotaFetches += 1
        return snapshot
    }

    func fetchProfileStats(referenceDate: Date) async throws -> CodexProfileStats {
        if profileFails { throw CodexUsageError.decodingFailed }
        return profile
    }

    func fetchAnalyticsDataset(
        referenceDate: Date,
        calendar: Calendar
    ) async throws -> UsageAnalyticsDataset {
        throw CodexUsageError.decodingFailed
    }

    func setProfileFailure(_ value: Bool) {
        profileFails = value
    }

    func quotaFetchCount() -> Int { quotaFetches }
}
