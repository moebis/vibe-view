import Foundation
import XCTest
@testable import CodexWatch

final class AppServerUsageAdapterTests: XCTestCase {
    func testRateLimitsMapToExistingQuotaSemanticsAndOfficialAccountDetails() {
        let fetchedAt = Date(timeIntervalSince1970: 2_000_000_000)
        let base = AppServerRateLimitSnapshot(
            limitID: "codex",
            limitName: nil,
            primary: AppServerRateLimitWindow(
                usedPercent: 25,
                windowDurationMinutes: 300,
                resetsAt: 2_000_001_000
            ),
            secondary: AppServerRateLimitWindow(
                usedPercent: 40,
                windowDurationMinutes: 10_080,
                resetsAt: 2_000_002_000
            ),
            credits: AppServerCreditsSnapshot(
                hasCredits: true,
                unlimited: false,
                balance: "7.25"
            ),
            individualLimit: nil,
            spendControlReached: nil,
            planType: .team,
            reachedReason: .workspaceOwnerCreditsDepleted
        )
        let spark = AppServerRateLimitSnapshot(
            limitID: "codex-spark",
            limitName: "Codex Spark",
            primary: AppServerRateLimitWindow(
                usedPercent: 10,
                windowDurationMinutes: 300,
                resetsAt: nil
            ),
            secondary: nil,
            credits: nil,
            individualLimit: nil,
            spendControlReached: nil,
            planType: nil,
            reachedReason: nil
        )
        let response = AppServerRateLimitsResponse(
            rateLimits: base,
            rateLimitsByLimitID: ["codex": base, "codex-spark": spark],
            resetCredits: AppServerResetCreditsSummary(
                availableCount: 2,
                credits: [AppServerResetCredit(
                    id: "RateLimitResetCredit_1",
                    resetType: .codexRateLimits,
                    status: .available,
                    grantedAt: 2_000_000_100,
                    expiresAt: 2_000_100_000,
                    title: "Rate-limit reset",
                    description: "Reset an eligible window."
                )]
            )
        )

        let snapshot = AppServerUsageAdapter.snapshot(from: response, fetchedAt: fetchedAt)

        XCTAssertEqual(snapshot.plan, .business)
        XCTAssertEqual(snapshot.weeklyWindow?.usedPercent, 40)
        XCTAssertEqual(snapshot.creditsRemaining, .balance("7.25"))
        XCTAssertEqual(snapshot.availableResetCredits, 2)
        XCTAssertEqual(snapshot.resetCredits.first?.id, "RateLimitResetCredit_1")
        XCTAssertEqual(snapshot.rateLimitReachedReason, .workspaceCreditsDepleted)
        XCTAssertEqual(snapshot.additionalWindows.map(\.id), ["codex-spark-1-primary"])
        XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
    }

    func testLongAndCollidingBucketNamesKeepBothWindowsDistinct() {
        func bucket(_ id: String) -> AppServerRateLimitSnapshot {
            AppServerRateLimitSnapshot(
                limitID: id, limitName: id,
                primary: AppServerRateLimitWindow(
                    usedPercent: 10, windowDurationMinutes: 300, resetsAt: nil
                ),
                secondary: AppServerRateLimitWindow(
                    usedPercent: 20, windowDurationMinutes: 10_080, resetsAt: nil
                ),
                credits: nil, individualLimit: nil, spendControlReached: nil,
                planType: nil, reachedReason: nil
            )
        }
        let base = bucket("codex")
        let longName = String(repeating: "a", count: 100)
        let snapshot = AppServerUsageAdapter.snapshot(
            from: AppServerRateLimitsResponse(
                rateLimits: base,
                rateLimitsByLimitID: [
                    "codex": base, "long-a": bucket(longName + "a"),
                    "long-b": bucket(longName + "b"),
                    "punctuation-a": bucket("codex_other"),
                    "punctuation-b": bucket("codex-other")
                ],
                resetCredits: nil
            ),
            fetchedAt: .now
        )
        let windows = snapshot.additionalWindows
        XCTAssertEqual(windows.count, 8)
        XCTAssertEqual(Set(windows.map(\.id)).count, 8)
        XCTAssertTrue(windows.allSatisfy { $0.id.utf8.count <= 64 })
        XCTAssertEqual(windows.filter { $0.window.kind == .weekly }.count, 4)
        XCTAssertEqual(snapshot.weeklyWindow?.remainingPercent, 80)
    }

    func testOfficialUsageMapsExactLifetimeSummaryAndValidatedDailyBuckets() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let fetchedAt = Date(timeIntervalSince1970: 2_000_000_000)
        let response = AppServerAccountUsageResponse(
            summary: AppServerAccountUsageSummary(
                lifetimeTokens: 1_234_567,
                peakDailyTokens: 45_678,
                longestRunningTurnSeconds: 59,
                currentStreakDays: 8,
                longestStreakDays: 14
            ),
            dailyUsageBuckets: [
                AppServerAccountUsageDailyBucket(startDate: "2026-06-18", tokens: 12_345)
            ]
        )

        let profile = AppServerUsageAdapter.profile(from: response, fetchedAt: fetchedAt)

        XCTAssertEqual(profile.lifetimeTokens, 1_234_567)
        XCTAssertEqual(profile.peakDailyTokens, 45_678)
        XCTAssertEqual(profile.longestRunningTurnSeconds, 59)
        XCTAssertEqual(profile.currentStreakDays, 8)
        XCTAssertEqual(profile.longestStreakDays, 14)
        XCTAssertEqual(
            profile.dailyBuckets,
            [CodexProfileDailyBucket(
                date: calendar.date(from: DateComponents(year: 2026, month: 6, day: 18))!,
                tokens: 12_345
            )]
        )
        XCTAssertEqual(profile.insights, CodexProfileInsights(
            fastModePercent: nil,
            reasoningEffort: nil,
            reasoningEffortPercent: nil,
            uniqueSkillsUsed: nil,
            totalSkillsUsed: nil,
            totalChats: nil
        ))
        XCTAssertEqual(profile.invocations, [])
        XCTAssertEqual(profile.fetchedAt, fetchedAt)
    }
}
