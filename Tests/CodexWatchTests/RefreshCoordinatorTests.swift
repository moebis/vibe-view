import Foundation
import XCTest
@testable import CodexWatch

final class RefreshCoordinatorTests: XCTestCase {
    func testFailedCapabilityRefreshPreservesLastGoodValueAndMarksItStale() {
        let previous = profile(lifetimeTokens: 30_300_000_000)

        let resolved = CapabilityRefreshState.resolve(
            previous: previous,
            wasStale: false,
            attempt: CapabilityRefreshAttempt<CodexProfileStats>.failure
        )

        XCTAssertEqual(resolved.value, previous)
        XCTAssertTrue(resolved.isStale)
    }

    func testSuccessfulCapabilityRefreshReplacesValueAndClearsStaleState() {
        let previous = profile(lifetimeTokens: 30_300_000_000)
        let replacement = profile(lifetimeTokens: 30_400_000_000)

        let resolved = CapabilityRefreshState.resolve(
            previous: previous,
            wasStale: true,
            attempt: CapabilityRefreshAttempt.success(replacement)
        )
        let notAttempted = CapabilityRefreshState.resolve(
            previous: previous,
            wasStale: true,
            attempt: CapabilityRefreshAttempt<CodexProfileStats>.notAttempted
        )

        XCTAssertEqual(resolved.value, replacement)
        XCTAssertFalse(resolved.isStale)
        XCTAssertEqual(notAttempted.value, previous)
        XCTAssertTrue(notAttempted.isStale)
    }

    func testAdaptivePolicyUsesInteractionAndConstrainedDelays() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        XCTAssertEqual(AdaptiveRefreshPolicy.nextDelay(
            now: now,
            lastMenuOpenAt: now.addingTimeInterval(-60),
            lowPowerMode: false,
            thermalConstrained: false
        ), 120)
        XCTAssertEqual(AdaptiveRefreshPolicy.nextDelay(
            now: now,
            lastMenuOpenAt: nil,
            lowPowerMode: true,
            thermalConstrained: false
        ), 1_800)
        XCTAssertEqual(AdaptiveRefreshPolicy.nextDelay(
            now: now,
            lastMenuOpenAt: now.addingTimeInterval(-30 * 60),
            lowPowerMode: false,
            thermalConstrained: false
        ), 300)
        XCTAssertEqual(AdaptiveRefreshPolicy.nextDelay(
            now: now,
            lastMenuOpenAt: now.addingTimeInterval(-2 * 60 * 60),
            lowPowerMode: false,
            thermalConstrained: false
        ), 900)
        XCTAssertEqual(AdaptiveRefreshPolicy.nextDelay(
            now: now,
            lastMenuOpenAt: now.addingTimeInterval(-5 * 60 * 60),
            lowPowerMode: false,
            thermalConstrained: false
        ), 1_800)
    }

    func testUnconfiguredPreferencePersistsAdaptive() {
        let suiteName = "RefreshCoordinatorTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(RefreshFrequency.load(from: defaults), .adaptive)
        XCTAssertEqual(defaults.integer(forKey: RefreshFrequency.preferenceKey), -1)
    }

    func testAutomaticAnalyticsRequestsRespectFifteenMinuteFloor() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        XCTAssertFalse(RefreshPolicy.shouldIncludeAnalytics(
            trigger: .automatic,
            lastAttempt: now.addingTimeInterval(-899),
            now: now
        ))
        XCTAssertTrue(RefreshPolicy.shouldIncludeAnalytics(
            trigger: .automatic,
            lastAttempt: now.addingTimeInterval(-900),
            now: now
        ))
        XCTAssertTrue(RefreshPolicy.shouldIncludeAnalytics(
            trigger: .manual,
            lastAttempt: now,
            now: now
        ))
        XCTAssertFalse(RefreshPolicy.shouldIncludeAnalytics(
            trigger: .menuOpened,
            lastAttempt: nil,
            now: now
        ))
        XCTAssertFalse(RefreshPolicy.shouldIncludeAnalytics(
            trigger: .menuOpened,
            lastAttempt: now.addingTimeInterval(-1_800),
            now: now
        ))
        XCTAssertFalse(RefreshPolicy.shouldIncludeAnalytics(
            trigger: .rateLimitUpdated,
            lastAttempt: nil,
            now: now
        ))
    }

    @MainActor
    func testRateLimitUpdateTriggersCoalesceIntoOneQuotaOnlyFetch() async {
        let gate = FetchGate()
        let coordinator = makeCoordinator(gate: gate)

        coordinator.trigger(.rateLimitUpdated)
        coordinator.trigger(.rateLimitUpdated)
        await gate.waitForFetchCount(1)

        let request = await gate.lastRequest()
        XCTAssertEqual(request?.trigger, .rateLimitUpdated)
        XCTAssertFalse(request?.includeAnalytics ?? true)

        await gate.release(trigger: .rateLimitUpdated)
        await coordinator.waitUntilIdleForTesting()
        let fetchCount = await gate.fetchCountValue()
        XCTAssertEqual(fetchCount, 1)
        coordinator.stop()
    }

    func testEligibleRefreshStartsCapabilitiesTogetherAndPublishesThemWhenQuotaFails() async {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let previous = UsageSnapshot(
            windows: [UsageWindow(id: "weekly", kind: .weekly, usedPercent: 20)],
            analyticsDataset: analytics(total: 10),
            profileStats: profile(lifetimeTokens: 10),
            fetchedAt: now.addingTimeInterval(-300)
        )
        let gate = CapabilityStartGate()
        let refreshedAnalytics = analytics(total: 20)
        let refreshedProfile = profile(lifetimeTokens: 30)
        let task = Task {
            await RefreshBatch.execute(
                previousSnapshot: previous,
                analyticsWasStale: true,
                profileWasStale: true,
                includeAnalytics: true,
                requestedAt: now,
                quota: {
                    await gate.start("quota")
                    return .failure(.quotaUnavailable)
                },
                analytics: {
                    await gate.start("analytics")
                    return .success(refreshedAnalytics)
                },
                profile: {
                    await gate.start("profile")
                    return .success(refreshedProfile)
                }
            )
        }

        await gate.waitForStartCount(3)
        let startedNames = await gate.startedNames()
        XCTAssertEqual(startedNames, Set(["quota", "analytics", "profile"]))
        await gate.releaseAll()
        let result = await task.value

        XCTAssertEqual(result.snapshot?.weeklyWindow?.usedPercent, 20)
        XCTAssertEqual(result.snapshot?.analyticsDataset?.days.first?.totals.totalTokens, 20)
        XCTAssertEqual(result.snapshot?.profileStats?.lifetimeTokens, 30)
        XCTAssertEqual(result.error, .quotaUnavailable)
        XCTAssertFalse(result.analyticsStale)
        XCTAssertFalse(result.profileStale)
        XCTAssertNil(result.quotaFetchedAt)
    }

    func testStaleQuotaCopyUsesLastSuccessfulFetchTime() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        XCTAssertEqual(
            MenuBarText.updatedLine(lastUpdated: now.addingTimeInterval(-125), now: now),
            "Updated 2m ago"
        )
    }

    @MainActor
    func testAutomaticTriggersCoalesceIntoOneFetch() async {
        let gate = FetchGate()
        let coordinator = makeCoordinator(gate: gate)

        coordinator.trigger(.automatic)
        coordinator.trigger(.automatic)
        await gate.waitForFetchCount(1)
        await gate.release(trigger: .automatic)
        await coordinator.waitUntilIdleForTesting()

        let fetchCount = await gate.fetchCountValue()
        XCTAssertEqual(fetchCount, 1)
        coordinator.stop()
    }

    @MainActor
    func testManualAndAccountReplacementPreventOldGenerationPublishing() async {
        for trigger in [RefreshTrigger.manual, .accountUpdated] {
            let gate = FetchGate()
            var publishedIDs: [String] = []
            let coordinator = makeCoordinator(gate: gate, publish: { result in
                if let id = result.snapshot?.windows.first?.id {
                    publishedIDs.append(id)
                }
            })
            coordinator.trigger(.automatic)
            await gate.waitForFetchCount(1)
            coordinator.trigger(trigger)
            await gate.waitForFetchCount(2)
            await gate.release(trigger: trigger)
            await coordinator.waitUntilIdleForTesting()
            await gate.release(trigger: .automatic)
            for _ in 0 ..< 10 { await Task.yield() }
            XCTAssertEqual(publishedIDs, [String(describing: trigger)])
            coordinator.stop()
        }
    }

    @MainActor
    func testMenuOpenOnlyRefreshesSnapshotOlderThanSixtySeconds() async {
        let gate = FetchGate()
        let clock = TestClock(Date(timeIntervalSince1970: 2_000_000_000))
        let coordinator = makeCoordinator(gate: gate, now: { clock.now })

        coordinator.trigger(.automatic)
        await gate.waitForFetchCount(1)
        await gate.release(trigger: .automatic)
        await coordinator.waitUntilIdleForTesting()

        clock.now.addTimeInterval(60)
        coordinator.trigger(.menuOpened)
        for _ in 0 ..< 10 { await Task.yield() }
        let freshFetchCount = await gate.fetchCountValue()
        XCTAssertEqual(freshFetchCount, 1)

        clock.now.addTimeInterval(1)
        coordinator.trigger(.menuOpened)
        await gate.waitForFetchCount(2)
        let lastTrigger = await gate.lastTrigger()
        XCTAssertEqual(lastTrigger, .menuOpened)
        await gate.release(trigger: .menuOpened)
        await coordinator.waitUntilIdleForTesting()
        coordinator.stop()
    }

    @MainActor
    func testStopBeforeScheduledFetchStartsDoesNotEnterFetcher() async {
        var fetches = 0
        let coordinator = RefreshCoordinator(
            frequency: .manual,
            fetch: { _ in
                fetches += 1
                return RefreshResult(snapshot: nil, error: nil, analyticsStale: false)
            },
            publish: { _ in XCTFail("Stopped work cannot publish") }
        )
        coordinator.trigger(.automatic)
        coordinator.stop()
        for _ in 0 ..< 10 { await Task.yield() }
        XCTAssertEqual(fetches, 0)
    }

    @MainActor
    func testStopPreventsPendingPublication() async {
        let gate = FetchGate()
        var publicationCount = 0
        let coordinator = makeCoordinator(
            gate: gate,
            publish: { _ in publicationCount += 1 }
        )

        coordinator.trigger(.automatic)
        await gate.waitForFetchCount(1)
        coordinator.stop()
        await gate.release(trigger: .automatic)
        for _ in 0 ..< 10 { await Task.yield() }

        XCTAssertEqual(publicationCount, 0)
    }

    @MainActor
    func testFixedScheduleDelayStartsOnlyAfterFetchCompletes() async {
        let gate = FetchGate()
        let sleeps = SleepRecorder()
        let coordinator = makeCoordinator(
            gate: gate,
            frequency: .oneMinute,
            sleep: { delay in
                await sleeps.record(delay)
                try await Task.sleep(nanoseconds: UInt64.max)
            }
        )

        coordinator.trigger(.automatic)
        await gate.waitForFetchCount(1)
        let sleepsBeforeCompletion = await sleeps.countValue()
        XCTAssertEqual(sleepsBeforeCompletion, 0)

        await gate.release(trigger: .automatic)
        await coordinator.waitUntilIdleForTesting()
        await sleeps.waitForCount(1)
        let delays = await sleeps.delaysValue()
        XCTAssertEqual(delays, [60])
        coordinator.stop()
    }

    @MainActor
    func testFreshMenuOpenReschedulesAdaptiveDelayFromInteractionTime() async {
        let gate = FetchGate()
        let sleeps = SleepRecorder()
        let clock = TestClock(Date(timeIntervalSince1970: 2_000_000_000))
        let coordinator = makeCoordinator(
            gate: gate,
            frequency: .adaptive,
            now: { clock.now },
            sleep: { delay in
                await sleeps.record(delay)
                try await Task.sleep(nanoseconds: UInt64.max)
            }
        )

        coordinator.trigger(.automatic)
        await gate.waitForFetchCount(1)
        await gate.release(trigger: .automatic)
        await coordinator.waitUntilIdleForTesting()
        await sleeps.waitForCount(1)

        clock.now.addTimeInterval(30)
        coordinator.trigger(.menuOpened)
        for _ in 0 ..< 100 { await Task.yield() }

        let fetchCount = await gate.fetchCountValue()
        let delays = await sleeps.delaysValue()
        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(delays, [1_800, 120])
        coordinator.stop()
    }

    @MainActor
    func testPartialResultsObeyGenerationAndShutdownOwnership() async throws {
        let gate = FetchGate()
        var publications = 0
        let coordinator = makeCoordinator(gate: gate, publish: { _ in publications += 1 })
        let result = RefreshResult(snapshot: nil, error: nil, analyticsStale: false)
        coordinator.trigger(.automatic)
        await gate.waitForFetchCount(1)
        let first = await gate.lastRequest()!
        coordinator.publishPartial(result, generation: first.generation)
        XCTAssertEqual(publications, 1)
        coordinator.trigger(.manual)
        await gate.waitForFetchCount(2)
        let second = await gate.lastRequest()!
        coordinator.publishPartial(result, generation: first.generation)
        XCTAssertEqual(publications, 1)
        coordinator.publishPartial(result, generation: second.generation)
        XCTAssertEqual(publications, 2)
        coordinator.stop()
        coordinator.publishPartial(result, generation: second.generation)
        XCTAssertEqual(publications, 2)
        await gate.release(trigger: .automatic)
        await gate.release(trigger: .manual)
    }

    @MainActor
    private func makeCoordinator(
        gate: FetchGate,
        frequency: RefreshFrequency = .manual,
        now: @escaping @MainActor () -> Date = { Date(timeIntervalSince1970: 2_000_000_000) },
        sleep: @escaping RefreshCoordinator.Sleep = { _ in },
        publish: @escaping @MainActor @Sendable (RefreshResult) -> Void = { _ in }
    ) -> RefreshCoordinator {
        RefreshCoordinator(
            frequency: frequency,
            now: now,
            sleep: sleep,
            fetch: { request in await gate.fetch(request) },
            publish: publish
        )
    }

    private func profile(lifetimeTokens: Int64) -> CodexProfileStats {
        CodexProfileStats(
            lifetimeTokens: lifetimeTokens,
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

    private func analytics(total: Int64) -> UsageAnalyticsDataset {
        let day = Date(timeIntervalSince1970: 2_000_000_000)
        return UsageAnalyticsDataset(
            requestedStart: day,
            requestedEnd: day,
            days: [UsageAnalyticsDay(
                date: day,
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
            fetchedAt: day,
            modelBreakdownIsPartial: false,
            clientBreakdownIsPartial: false
        )
    }
}

@MainActor
private final class TestClock {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }
}

private actor SleepRecorder {
    private var delays: [TimeInterval] = []

    func record(_ delay: TimeInterval) {
        delays.append(delay)
    }

    func countValue() -> Int { delays.count }

    func delaysValue() -> [TimeInterval] { delays }

    func waitForCount(_ count: Int) async {
        while delays.count < count { await Task.yield() }
    }
}

private actor FetchGate {
    private(set) var requests: [RefreshRequest] = []
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]

    var fetchCount: Int { requests.count }

    func fetchCountValue() -> Int { requests.count }

    func lastTrigger() -> RefreshTrigger? { requests.last?.trigger }

    func lastRequest() -> RefreshRequest? { requests.last }

    func fetch(_ request: RefreshRequest) async -> RefreshResult {
        requests.append(request)
        await withCheckedContinuation { continuation in
            continuations[request.generation] = continuation
        }
        let id = String(describing: request.trigger)
        return RefreshResult(
            snapshot: UsageSnapshot(
                windows: [UsageWindow(id: id, kind: .weekly, usedPercent: 0)],
                fetchedAt: Date(timeIntervalSince1970: 2_000_000_000)
            ),
            error: nil,
            analyticsStale: false,
            quotaFetchedAt: Date(timeIntervalSince1970: 2_000_000_000)
        )
    }

    func waitForFetchCount(_ count: Int) async {
        while requests.count < count { await Task.yield() }
    }

    func release(trigger: RefreshTrigger) {
        guard let request = requests.last(where: { $0.trigger == trigger }),
              let continuation = continuations.removeValue(forKey: request.generation) else { return }
        continuation.resume()
    }
}

private actor CapabilityStartGate {
    private var started: Set<String> = []
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func start(_ name: String) async {
        started.insert(name)
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func startedNames() -> Set<String> { started }

    func waitForStartCount(_ count: Int) async {
        while started.count < count { await Task.yield() }
    }

    func releaseAll() {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}
