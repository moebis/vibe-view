import XCTest
@testable import CodexWatch

final class ClaudeQuotaControllerTests: XCTestCase {
    @MainActor
    func testDisconnectedDoesNotFetchAndRefreshesCoalesce() async throws {
        let defaults = makeDefaults()
        let gate = ClaudeFetchGate()
        let controller = ClaudeQuotaController(defaults: defaults) { interaction in
            await gate.fetch(interaction: interaction)
        }
        controller.refresh(force: true)
        XCTAssertFalse(controller.isRefreshing)
        controller.connect()
        await waitFor { await gate.count == 1 }
        controller.refresh(force: true)
        XCTAssertTrue(controller.isRefreshing)
        let count = await gate.count
        XCTAssertEqual(count, 1)
        let allowed = await gate.interaction
        XCTAssertTrue(allowed)
        await gate.complete()
        await waitFor { await MainActor.run { !controller.isRefreshing } }
        XCTAssertNotNil(controller.snapshot)
        controller.refresh(now: .now)
        XCTAssertFalse(controller.isRefreshing)
        controller.stop()
    }

    @MainActor
    func testDisconnectAndStopRejectLatePublication() async {
        for stop in [false, true] {
            let gate = ClaudeFetchGate()
            let controller = ClaudeQuotaController(defaults: makeDefaults()) { interaction in
                await gate.fetch(interaction: interaction)
            }
            controller.connect()
            await waitFor { await gate.count == 1 }
            if stop { controller.stop() } else { controller.disconnect() }
            await gate.complete()
            for _ in 0..<10 { await Task.yield() }
            XCTAssertNil(controller.snapshot)
            XCTAssertFalse(controller.isRefreshing)
            if !stop { XCTAssertFalse(controller.isEnabled) }
        }
    }

    @MainActor
    func testFailureClearsPriorQuotaAndRateLimitBacksOff() async {
        let controller = ClaudeQuotaController(defaults: makeDefaults()) { _ in
            throw ClaudeConnectionError.rateLimited(300)
        }
        controller.connect()
        await waitFor { await MainActor.run { !controller.isRefreshing } }
        XCTAssertNil(controller.snapshot)
        XCTAssertEqual(controller.error, .rateLimited(300))
        controller.refresh(force: true)
        XCTAssertFalse(controller.isRefreshing)
        controller.disconnect()
    }

    @MainActor
    func testAuthLossClearsLastSuccessfulQuota() async {
        let source = ClaudeSuccessThenAuthLoss()
        let controller = ClaudeQuotaController(defaults: makeDefaults()) { _ in try await source.fetch() }
        controller.connect()
        await waitFor { await MainActor.run { !controller.isRefreshing } }
        XCTAssertNotNil(controller.snapshot)
        controller.refresh(force: true)
        await waitFor { await MainActor.run { !controller.isRefreshing } }
        XCTAssertNil(controller.snapshot)
        XCTAssertEqual(controller.error, .signInRequired)
        controller.disconnect()
    }

    private func makeDefaults() -> UserDefaults {
        let name = "ClaudeQuotaTests.\(UUID().uuidString)"
        let value = UserDefaults(suiteName: name)!
        addTeardownBlock { value.removePersistentDomain(forName: name) }
        return value
    }

    private func waitFor(_ condition: () async -> Bool) async {
        for _ in 0..<500 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for refresh")
    }
}

private actor ClaudeFetchGate {
    var count = 0
    var interaction = false
    private var continuation: CheckedContinuation<ClaudeUsageSnapshot, Never>?
    func fetch(interaction: Bool) async -> ClaudeUsageSnapshot {
        count += 1
        self.interaction = interaction
        return await withCheckedContinuation { continuation = $0 }
    }
    func complete() {
        continuation?.resume(returning: ClaudeUsageSnapshot(windows: [
            .init(title: "Weekly", usedPercent: 40, resetsAt: nil)
        ], fetchedAt: .now))
        continuation = nil
    }
}

private actor ClaudeSuccessThenAuthLoss {
    private var requested = false
    func fetch() throws -> ClaudeUsageSnapshot {
        guard !requested else { throw ClaudeConnectionError.signInRequired }
        requested = true
        return ClaudeUsageSnapshot(windows: [.init(title: "Weekly", usedPercent: 50, resetsAt: nil)], fetchedAt: .now)
    }
}
