import Foundation
import XCTest
@testable import CodexWatch

final class AuditRegressionTests: XCTestCase {
    func testExplicitCodexBucketWinsOverLegacySpark() throws {
        let data = Data(#"{"rateLimits":{"limitId":"codex-spark","secondary":{"usedPercent":91,"windowDurationMins":10080}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","secondary":{"usedPercent":20,"windowDurationMins":10080}}}}"#.utf8)
        let response = try JSONDecoder().decode(AppServerRateLimitsResponse.self, from: data)
        XCTAssertEqual(AppServerUsageAdapter.snapshot(from: response, fetchedAt: .now).weeklyWindow?.remainingPercent, 80)
    }

    func testModelBucketAloneNeverBecomesBaseQuota() throws {
        for identifier in ["codex-spark", "codex-other"] {
            let data = Data("{\"rateLimits\":{\"limitId\":\"\(identifier)\",\"secondary\":{\"usedPercent\":91,\"windowDurationMins\":10080}}}".utf8)
            let response = try JSONDecoder().decode(AppServerRateLimitsResponse.self, from: data)
            XCTAssertNil(AppServerUsageAdapter.snapshot(from: response, fetchedAt: .now).weeklyWindow)
        }
    }

    func testWholeNumericStringsAreRequiredAcrossBothSources() throws {
        for value in ["12garbage", "1.2.3", "1e", "1e+", "NaN", "∞", "--2", "12\n34", "0x12"] {
            XCTAssertNil(ValidatedDecimal.parse(value), value)
            let encoded = try JSONSerialization.data(withJSONObject: ["has_credits": true, "unlimited": false, "balance": value])
            let credits = try JSONDecoder().decode(CreditsDTO.self, from: encoded)
            XCTAssertNil(credits.validatedRemaining, value)
            let payload = try JSONSerialization.data(withJSONObject: ["rateLimits": ["credits": ["hasCredits": true, "unlimited": false, "balance": value]]])
            let limits = try JSONDecoder().decode(AppServerRateLimitsResponse.self, from: payload)
            XCTAssertNil(AppServerUsageAdapter.snapshot(from: limits, fetchedAt: .now).creditsRemaining, value)
        }
        for value in ["-1.25", "0", "+12.5", ".5", "1.", "1.25e-3", " 12.5 "] {
            XCTAssertNotNil(ValidatedDecimal.parse(value), value)
        }
    }

    func testSignInFailureMarksRetainedCapabilitiesStaleButQuotaFailureDoesNot() async throws {
        let profile = try JSONDecoder().decode(CodexProfileResponseDTO.self, from: Data(#"{"stats":{"lifetime_tokens":123}}"#.utf8)).profileStats()!
        let dataset = UsageAnalyticsDataset(requestedStart: .now, requestedEnd: .now, days: [], fetchedAt: .now, modelBreakdownIsPartial: false, clientBreakdownIsPartial: false)
        let previous = UsageSnapshot(windows: [], analyticsDataset: dataset, profileStats: profile)
        for error in [MenuBarErrorState.signInRequired, .quotaUnavailable] {
            let result = await RefreshBatch.execute(
                previousSnapshot: previous, analyticsWasStale: false, profileWasStale: false,
                includeAnalytics: false, requestedAt: .now,
                quota: { .failure(error) }, analytics: { .notAttempted }, profile: { .notAttempted }
            )
            XCTAssertEqual(result.snapshot?.analyticsDataset, dataset)
            XCTAssertEqual(result.snapshot?.profileStats, profile)
            XCTAssertEqual(result.analyticsStale, error == .signInRequired)
            XCTAssertEqual(result.profileStale, error == .signInRequired)
        }
    }

    func testQuotaPublishesBeforeAnalyticsIsAllowedToFinish() async {
        let gate = AuditGate()
        let published = expectation(description: "Quota published while analytics is pending")
        let quota = UsageSnapshot(windows: [UsageWindow(id: "weekly", kind: .weekly, usedPercent: 20)])
        let batch = Task {
            await RefreshBatch.execute(
                previousSnapshot: nil, analyticsWasStale: false, profileWasStale: false,
                includeAnalytics: true, requestedAt: .now,
                quota: { .success(quota) },
                analytics: { await gate.wait(); return .failure },
                profile: { await gate.wait(); return .failure },
                onQuota: { result in
                    XCTAssertEqual(result.snapshot?.weeklyWindow?.remainingPercent, 80)
                    published.fulfill()
                }
            )
        }
        await fulfillment(of: [published], timeout: 2)
        await gate.release()
        _ = await batch.value
    }

    func testConnectionFailureRecreatesClientAndSubscription() async throws {
        let first = RecoveryClient(quotaError: .terminated)
        let second = RecoveryClient()
        let factory = RecoveryFactory([first, second])
        let service = CodexAccountService(retryDelay: .zero, makeClient: { factory.make() })
        let originalStream = try await service.accountUpdates()
        do { _ = try await service.fetchQuota(fetchedAt: .now); XCTFail("Expected failure") } catch {}
        var iterator = originalStream.makeAsyncIterator()
        let end = await iterator.next()
        XCTAssertNil(end)
        let quota = try await service.fetchQuota(fetchedAt: .now)
        XCTAssertEqual(quota.weeklyWindow?.remainingPercent, 80)
        let stream = try await service.accountUpdates()
        try await second.emitUpdate()
        var newIterator = stream.makeAsyncIterator()
        let update = await newIterator.next()
        XCTAssertEqual(update?.rateLimits?.limitID, "codex")
        XCTAssertEqual(factory.count, 2)
        let stopped = await first.stopCount
        XCTAssertEqual(stopped, 1)
        await service.stop()
    }

    func testFailedHandshakeCanRecoverEvenWhenFailureIsAnInvalidResponse() async throws {
        let factory = RecoveryFactory([RecoveryClient(startupError: .invalidResponse), RecoveryClient()])
        let service = CodexAccountService(retryDelay: .zero, makeClient: { factory.make() })
        _ = try? await service.fetchQuota(fetchedAt: .now)
        let quota = try await service.fetchQuota(fetchedAt: .now)
        XCTAssertNotNil(quota.weeklyWindow)
        XCTAssertEqual(factory.count, 2)
        await service.stop()
    }

    func testReconnectCooldownAndShutdownPreventProcessChurn() async {
        let factory = RecoveryFactory([RecoveryClient(quotaError: .terminated)])
        let service = CodexAccountService(retryDelay: .seconds(30), makeClient: { factory.make() })
        for _ in 0..<5 { _ = try? await service.fetchQuota(fetchedAt: .now) }
        XCTAssertEqual(factory.count, 1)
        await service.stop()
        _ = try? await service.fetchQuota(fetchedAt: .now)
        XCTAssertEqual(factory.count, 1)
    }

    func testOptionalUnsupportedMethodKeepsQuotaConnectionAndAccountIsRevalidated() async throws {
        let client = RecoveryClient(usageError: .remoteError(code: -32601))
        let factory = RecoveryFactory([client])
        let service = CodexAccountService(retryDelay: .zero, makeClient: { factory.make() })
        _ = try? await service.fetchProfile(fetchedAt: .now)
        _ = try await service.fetchQuota(fetchedAt: .now)
        XCTAssertEqual(factory.count, 1)
        await client.setAPIKeyAccount()
        do {
            _ = try await service.fetchQuota(fetchedAt: .now)
            XCTFail("Must revalidate account after sign-out")
        } catch {
            XCTAssertEqual(error as? CodexAccountServiceError, .signInRequired)
        }
        await service.stop()
    }

    func testUncertainResetIsNotAutomaticallyRetriedAcrossReconnect() async throws {
        let first = RecoveryClient(resetError: .timedOut)
        let second = RecoveryClient()
        let factory = RecoveryFactory([first, second])
        let service = CodexAccountService(retryDelay: .zero, makeClient: { factory.make() })
        let key = UUID().uuidString
        do { _ = try await service.consumeReset(idempotencyKey: key, creditID: nil); XCTFail("Expected timeout") } catch {}
        XCTAssertEqual(factory.count, 1)
        let retry = try await service.consumeReset(idempotencyKey: key, creditID: nil)
        XCTAssertEqual(retry, .alreadyRedeemed)
        let firstKeys = await first.resetKeys
        let secondKeys = await second.resetKeys
        XCTAssertEqual(firstKeys, [key])
        XCTAssertEqual(secondKeys, [key])
        await service.stop()
    }
}

private actor AuditGate {
    var released = false
    var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if released { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        released = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private final class RecoveryFactory: @unchecked Sendable {
    private let lock = NSLock()
    private let clients: [RecoveryClient]
    private var created = 0
    init(_ clients: [RecoveryClient]) { self.clients = clients }
    func make() -> RecoveryClient {
        lock.withLock {
            let client = clients[min(created, clients.count - 1)]
            created += 1
            return client
        }
    }
    var count: Int { lock.withLock { created } }
}

private actor RecoveryClient: AppServerAccountServing {
    let startupError: AppServerError?
    let quotaError: AppServerError?
    let usageError: AppServerError?
    let resetError: AppServerError?
    var apiKey = false
    var stopCount = 0
    var resetKeys: [String] = []
    var updates: [AsyncStream<AppServerAccountUpdate>.Continuation] = []
    init(startupError: AppServerError? = nil, quotaError: AppServerError? = nil, usageError: AppServerError? = nil, resetError: AppServerError? = nil) {
        self.startupError = startupError; self.quotaError = quotaError; self.usageError = usageError; self.resetError = resetError
    }
    func start() async throws { if let startupError { throw startupError } }
    func readAccount() async throws -> AppServerAccountResponse {
        AppServerAccountResponse(account: apiKey ? .apiKey : .chatGPT(planType: .plus), requiresOpenAIAuth: true)
    }
    func setAPIKeyAccount() { apiKey = true }
    func readRateLimits() async throws -> AppServerRateLimitsResponse {
        if let quotaError { throw quotaError }
        return try limits()
    }
    func readAccountUsage() async throws -> AppServerAccountUsageResponse {
        if let usageError { throw usageError }
        return try JSONDecoder().decode(AppServerAccountUsageResponse.self, from: Data(#"{"summary":{}}"#.utf8))
    }
    func consumeRateLimitReset(idempotencyKey: String, creditID: String?) async throws -> AppServerResetOutcome {
        resetKeys.append(idempotencyKey)
        if let resetError { throw resetError }
        return .alreadyRedeemed
    }
    func accountUpdates() async -> AsyncStream<AppServerAccountUpdate> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { updates.append($0) }
    }
    func emitUpdate() throws {
        let value = try limits().rateLimits
        updates.forEach { $0.yield(AppServerAccountUpdate(accountRevision: 0, rateLimits: value)) }
    }
    func stop() async {
        stopCount += 1
        updates.forEach { $0.finish() }
        updates.removeAll()
    }
    private func limits() throws -> AppServerRateLimitsResponse {
        try JSONDecoder().decode(AppServerRateLimitsResponse.self, from: Data(#"{"rateLimits":{"limitId":"codex","secondary":{"usedPercent":20,"windowDurationMins":10080}}}"#.utf8))
    }
}
