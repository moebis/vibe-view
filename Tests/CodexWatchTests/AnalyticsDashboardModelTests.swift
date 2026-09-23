import Combine
import Foundation
import XCTest
@testable import CodexWatch

@MainActor
final class AnalyticsDashboardModelTests: XCTestCase {
    func testDashboardRestoresAndPersistsTopLevelSection() {
        let suiteName = "AnalyticsDashboardModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("lifetime", forKey: "codexWatch.analyticsSection")

        let model = AnalyticsDashboardModel(defaults: defaults, calendar: utcCalendar())

        XCTAssertEqual(model.section, .lifetime)
        model.section = .usage
        XCTAssertEqual(defaults.string(forKey: "codexWatch.analyticsSection"), "usage")
    }

    func testDashboardRestoresRangeAndReprojectsNewDataset() throws {
        let suiteName = "AnalyticsDashboardModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(90, forKey: "codexWatch.analyticsRange")
        let model = AnalyticsDashboardModel(defaults: defaults, calendar: utcCalendar())
        let now = day("2026-08-20")

        model.update(dataset: makeDashboardDataset(total: 100), error: nil, now: now)

        XCTAssertEqual(model.range, .days90)
        XCTAssertEqual(model.projection?.totalTokens, 100)

        model.range = .days7
        XCTAssertEqual(defaults.integer(forKey: "codexWatch.analyticsRange"), 7)
        XCTAssertEqual(model.projection?.range, .days7)
    }

    func testDashboardKeepsLastDatasetAndMarksAnalyticsStale() {
        let suiteName = "AnalyticsDashboardModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AnalyticsDashboardModel(defaults: defaults, calendar: utcCalendar())
        let now = day("2026-08-20")

        model.update(dataset: makeDashboardDataset(total: 100), error: nil, now: now)
        model.update(dataset: nil, error: .analyticsUnavailable, now: now)

        XCTAssertEqual(model.projection?.totalTokens, 100)
        XCTAssertTrue(model.isStale)
        XCTAssertEqual(model.errorState, .analyticsUnavailable)
    }

    func testDashboardRefreshStatusUsesFetchedTimeThenLastSuccessfulTimeWhenStale() {
        let suiteName = "AnalyticsDashboardModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AnalyticsDashboardModel(defaults: defaults, calendar: utcCalendar())
        let fetchedAt = day("2026-08-20")

        model.update(dataset: makeDashboardDataset(total: 100), error: nil, now: fetchedAt)

        XCTAssertEqual(model.selectedRefreshStatus?.label, "Fetched")
        XCTAssertEqual(model.selectedRefreshStatus?.fetchedAt, fetchedAt)
        XCTAssertEqual(model.selectedRefreshStatus?.isStale, false)

        model.update(dataset: nil, error: .analyticsUnavailable, now: day("2026-08-21"))

        XCTAssertEqual(model.selectedRefreshStatus?.label, "Last successful refresh")
        XCTAssertEqual(model.selectedRefreshStatus?.fetchedAt, fetchedAt)
        XCTAssertEqual(model.selectedRefreshStatus?.isStale, true)
    }

    func testDashboardRefreshStatusDoesNotInventTimestampWithoutSuccessfulData() {
        let suiteName = "AnalyticsDashboardModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AnalyticsDashboardModel(defaults: defaults, calendar: utcCalendar())

        model.update(
            dataset: nil,
            error: .analyticsUnavailable,
            profileStats: nil,
            profileError: .profileUnavailable,
            now: day("2026-08-20")
        )

        XCTAssertNil(model.selectedRefreshStatus)
        model.section = .lifetime
        XCTAssertNil(model.selectedRefreshStatus)
    }

    func testDashboardRefreshStatusUsesSelectedLifetimeFetch() {
        let suiteName = "AnalyticsDashboardModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AnalyticsDashboardModel(defaults: defaults, calendar: utcCalendar())
        let fetchedAt = day("2026-08-20")
        model.section = .lifetime

        model.update(
            dataset: nil,
            error: nil,
            profileStats: makeProfile(total: 100, fetchedAt: fetchedAt),
            profileError: nil,
            now: fetchedAt
        )

        XCTAssertEqual(model.selectedRefreshStatus?.label, "Fetched")
        XCTAssertEqual(model.selectedRefreshStatus?.fetchedAt, fetchedAt)
        XCTAssertEqual(model.selectedRefreshStatus?.isStale, false)
    }

    func testAnalyticsWindowControllerForwardsInjectedRefreshAction() {
        let suiteName = "AnalyticsDashboardModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var refreshCount = 0
        let controller = AnalyticsWindowController(
            defaults: defaults,
            calendar: utcCalendar(),
            onRefresh: { refreshCount += 1 }
        )

        controller.requestRefresh()

        XCTAssertEqual(refreshCount, 1)
    }

    func testDashboardCSVUsesCurrentSelectedRange() throws {
        let suiteName = "AnalyticsDashboardModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AnalyticsDashboardModel(defaults: defaults, calendar: utcCalendar())
        let now = day("2026-08-20")
        model.update(dataset: makeDashboardDataset(total: 100), error: nil, now: now)
        model.range = .days7

        XCTAssertTrue(try model.csvString().hasPrefix("Vibe View analytics,7d\r\n"))
        XCTAssertEqual(
            model.suggestedCSVFilename,
            "codex-watch-analytics-7d-2026-08-20.csv"
        )
    }

    func testDashboardKeepsProfileAndMarksOnlyProfileSurfaceStale() {
        let suiteName = "AnalyticsDashboardModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AnalyticsDashboardModel(defaults: defaults, calendar: utcCalendar())
        let now = day("2026-08-20")
        let profile = makeProfile(total: 30_300_000_000, fetchedAt: now)

        model.update(
            dataset: makeDashboardDataset(total: 100),
            error: nil,
            profileStats: profile,
            profileError: nil,
            now: now
        )
        model.update(
            dataset: makeDashboardDataset(total: 200),
            error: nil,
            profileStats: nil,
            profileError: .profileUnavailable,
            now: now
        )

        XCTAssertEqual(model.projection?.totalTokens, 200)
        XCTAssertFalse(model.isStale)
        XCTAssertEqual(model.lifetime?.lifetimeTokens, "30.3B")
        XCTAssertTrue(model.profileIsStale)
        XCTAssertEqual(model.profileErrorState, .profileUnavailable)
    }

    func testQuotaOnlyUpdatesDoNotPublishUnchangedAnalytics() {
        let suiteName = "AnalyticsDashboardModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AnalyticsDashboardModel(defaults: defaults, calendar: utcCalendar())
        let now = day("2026-08-20")
        let dataset = makeDashboardDataset(total: 100)
        let profile = makeProfile(total: 200, fetchedAt: now)
        model.update(dataset: dataset, error: nil, profileStats: profile, now: now)
        var changes = 0
        let observation = model.objectWillChange.sink { changes += 1 }
        defer { observation.cancel() }

        model.update(
            dataset: dataset, error: nil, profileStats: profile,
            now: now.addingTimeInterval(300)
        )
        XCTAssertEqual(changes, 0)

        model.update(dataset: dataset, error: .analyticsUnavailable, profileStats: profile, now: now)
        XCTAssertTrue(model.isStale)
        XCTAssertFalse(model.profileIsStale)
        XCTAssertGreaterThan(changes, 0)
        XCTAssertEqual(model.projection?.totalTokens, 100)

        // The timestamp may be unchanged even when a corrected response has new values.
        model.update(dataset: makeDashboardDataset(total: 300), error: nil, now: now)
        XCTAssertFalse(model.isStale)
        XCTAssertEqual(model.projection?.totalTokens, 300)
    }

    func testProjectionCacheInvalidatesForRangeDayCalendarAndCorrectedData() {
        var cache = UsageAnalyticsProjectionCache()
        let dataset = makeDashboardDataset(total: 100)
        let calendar = utcCalendar()
        let now = day("2026-08-20")
        let first = cache.projection(dataset: dataset, range: .days30, referenceDate: now, calendar: calendar)
        XCTAssertEqual(
            cache.projection(dataset: dataset, range: .days30, referenceDate: now.addingTimeInterval(60), calendar: calendar),
            first
        )
        XCTAssertEqual(cache.projection(dataset: dataset, range: .days7, referenceDate: now, calendar: calendar)?.range, .days7)
        XCTAssertEqual(
            cache.projection(dataset: dataset, range: .days30, referenceDate: day("2026-08-19"), calendar: calendar)?.periodEnd,
            day("2026-08-19")
        )
        var shifted = calendar
        shifted.timeZone = TimeZone(secondsFromGMT: 3_600)!
        XCTAssertEqual(
            cache.projection(dataset: dataset, range: .days30, referenceDate: now, calendar: shifted),
            UsageAnalyticsProjection.make(dataset: dataset, range: .days30, referenceDate: now, calendar: shifted)
        )
        XCTAssertEqual(
            cache.projection(dataset: makeDashboardDataset(total: 200), range: .days30, referenceDate: now, calendar: calendar)?.totalTokens,
            200
        )
    }

    private func makeDashboardDataset(total: Int64) -> UsageAnalyticsDataset {
        let end = day("2026-08-20")
        let start = utcCalendar().date(byAdding: .day, value: -364, to: end)!
        return UsageAnalyticsDataset(
            requestedStart: start,
            requestedEnd: end,
            days: [UsageAnalyticsDay(
                date: end,
                totals: UsageTokenTotals(
                    totalTokens: total,
                    uncachedInputTokens: total,
                    cachedInputTokens: 0,
                    outputTokens: 0,
                    turns: 1,
                    chats: 1
                ),
                models: [],
                clients: []
            )],
            fetchedAt: end,
            modelBreakdownIsPartial: false,
            clientBreakdownIsPartial: false
        )
    }

    private func makeProfile(total: Int64, fetchedAt: Date) -> CodexProfileStats {
        CodexProfileStats(
            lifetimeTokens: total,
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
            fetchedAt: fetchedAt
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
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
