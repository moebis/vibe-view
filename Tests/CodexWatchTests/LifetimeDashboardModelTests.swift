import Foundation
import XCTest
@testable import CodexWatch

final class LifetimeDashboardModelTests: XCTestCase {
    func testHeadlineMetricsMatchOfficialProfileSemantics() {
        let model = LifetimeDashboardModel(
            profile: makeProfile(
                lifetimeTokens: 30_300_000_000,
                peakTokens: 1_100_000_000,
                longestSeconds: 56_580,
                currentStreak: 42,
                longestStreak: 82
            )
        )

        XCTAssertEqual(model.lifetimeTokens, "30.3B")
        XCTAssertEqual(model.peakTokens, "1.1B")
        XCTAssertEqual(model.longestChat, "15h 43m")
        XCTAssertEqual(model.currentStreak, "42 days")
        XCTAssertEqual(model.longestStreak, "82 days")
    }

    func testCompactNumbersPromoteRoundedValuesToTheNextUnit() {
        XCTAssertEqual(CompactNumberFormat.string(999), "999")
        XCTAssertEqual(CompactNumberFormat.string(1_000), "1K")
        XCTAssertEqual(CompactNumberFormat.string(8_449), "8.4K")
        XCTAssertEqual(CompactNumberFormat.string(999_950), "1M")
        XCTAssertEqual(CompactNumberFormat.string(999_950_000), "1B")
        XCTAssertEqual(CompactNumberFormat.string(-2_500_000), "-2.5M")
        XCTAssertEqual(CompactNumberFormat.string(1_500_000_000_000), "1500B")
        XCTAssertEqual(BoundedText.trimmed("  é🙂ab  ", maximumUTF8Bytes: 6), "é🙂")
        XCTAssertNil(BoundedText.trimmedNonEmpty("   "))
    }

    func testMissingHeadlineMetricsRemainUnavailable() {
        let model = LifetimeDashboardModel(
            profile: makeProfile(
                lifetimeTokens: nil,
                peakTokens: nil,
                longestSeconds: nil,
                currentStreak: nil,
                longestStreak: nil
            )
        )

        XCTAssertEqual(model.lifetimeTokens, "Unavailable")
        XCTAssertEqual(model.peakTokens, "Unavailable")
        XCTAssertEqual(model.longestChat, "Unavailable")
        XCTAssertEqual(model.currentStreak, "Unavailable")
        XCTAssertEqual(model.longestStreak, "Unavailable")
    }

    func testLongestRunningTurnUnderOneMinuteNeverDisplaysZeroMinutes() {
        let oneSecond = LifetimeDashboardModel(
            profile: makeProfile(
                lifetimeTokens: 1,
                peakTokens: 1,
                longestSeconds: 1,
                currentStreak: 1,
                longestStreak: 1
            )
        )
        let fiftyNineSeconds = LifetimeDashboardModel(
            profile: makeProfile(
                lifetimeTokens: 1,
                peakTokens: 1,
                longestSeconds: 59,
                currentStreak: 1,
                longestStreak: 1
            )
        )

        XCTAssertEqual(oneSecond.longestChat, "1s")
        XCTAssertEqual(fiftyNineSeconds.longestChat, "59s")
    }

    func testActivityUsesOnlyServerBucketsAndReportsActualCoverageEndpoints() {
        let profile = makeProfile(
            lifetimeTokens: 1,
            peakTokens: 1,
            longestSeconds: 60,
            currentStreak: 1,
            longestStreak: 1,
            dailyBuckets: [
                CodexProfileDailyBucket(date: day("2026-08-18"), tokens: 20),
                CodexProfileDailyBucket(date: day("2026-08-20"), tokens: 40)
            ]
        )

        let model = LifetimeDashboardModel(profile: profile)

        XCTAssertEqual(model.activityDays.map(\.date), [day("2026-08-18"), day("2026-08-20")])
        XCTAssertEqual(model.activityDays.map(\.tokens), [20, 40])
        XCTAssertEqual(model.observedBucketCount, 2)
        XCTAssertEqual(model.maximumDailyTokens, 40)
        XCTAssertEqual(model.activityCoverage, "2 server-observed days · Aug 18–Aug 20, 2026")
        XCTAssertEqual(
            LifetimeDashboardModel.accessibilityText(model.activityDays[1]),
            "Aug 20, 2026, 40 tokens"
        )
    }

    func testActivityDoesNotDiscardBucketsOlderThanOneYear() {
        let profile = makeProfile(
            lifetimeTokens: 1,
            peakTokens: 1,
            longestSeconds: 60,
            currentStreak: 1,
            longestStreak: 1,
            dailyBuckets: [
                CodexProfileDailyBucket(date: day("2024-01-01"), tokens: 20),
                CodexProfileDailyBucket(date: day("2026-08-20"), tokens: 40)
            ]
        )

        let model = LifetimeDashboardModel(profile: profile)

        XCTAssertEqual(model.activityDays.map(\.date), [day("2024-01-01"), day("2026-08-20")])
        XCTAssertEqual(model.activityCoverage, "2 server-observed days · Jan 1, 2024–Aug 20, 2026")
    }

    func testInsightsAndInvocationsUseServerValues() {
        let profile = CodexProfileStats(
            lifetimeTokens: 1,
            peakDailyTokens: 1,
            longestRunningTurnSeconds: 1,
            currentStreakDays: 1,
            longestStreakDays: 1,
            dailyBuckets: [],
            insights: CodexProfileInsights(
                fastModePercent: 7,
                reasoningEffort: "Extra High",
                reasoningEffortPercent: 60,
                uniqueSkillsUsed: 82,
                totalSkillsUsed: 8_369,
                totalChats: 6_316
            ),
            invocations: [
                CodexProfileInvocation(
                    id: "plugin:superpowers",
                    displayName: "superpowers",
                    kind: .plugin,
                    usageCount: 6_122
                )
            ],
            fetchedAt: day("2026-08-20")
        )

        let model = LifetimeDashboardModel(profile: profile)

        XCTAssertEqual(model.insights.map(\.value), ["7%", "Extra High · 60%", "82", "8.4K", "6.3K"])
        XCTAssertEqual(model.invocations.first?.name, "@superpowers")
        XCTAssertEqual(model.invocations.first?.usage, "6.1K runs")
        XCTAssertEqual(model.dataThrough, "Aug 20, 2026")
    }

    private func makeProfile(
        lifetimeTokens: Int64?,
        peakTokens: Int64?,
        longestSeconds: Int64?,
        currentStreak: Int?,
        longestStreak: Int?,
        dailyBuckets: [CodexProfileDailyBucket] = []
    ) -> CodexProfileStats {
        CodexProfileStats(
            lifetimeTokens: lifetimeTokens,
            peakDailyTokens: peakTokens,
            longestRunningTurnSeconds: longestSeconds,
            currentStreakDays: currentStreak,
            longestStreakDays: longestStreak,
            dailyBuckets: dailyBuckets,
            insights: CodexProfileInsights(
                fastModePercent: nil,
                reasoningEffort: nil,
                reasoningEffortPercent: nil,
                uniqueSkillsUsed: nil,
                totalSkillsUsed: nil,
                totalChats: nil
            ),
            invocations: [],
            fetchedAt: day("2026-08-20")
        )
    }

    private func day(_ value: String) -> Date {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        return utcCalendar().date(from: DateComponents(
            year: parts[0],
            month: parts[1],
            day: parts[2]
        ))!
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
