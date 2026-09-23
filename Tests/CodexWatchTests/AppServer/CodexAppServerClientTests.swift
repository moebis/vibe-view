import Foundation
import XCTest
@testable import CodexWatch

final class CodexAppServerClientTests: XCTestCase {
    func testInitializeIsSentExactlyOnceWithOfficialShape() async throws {
        let transport = InMemoryAppServerLineTransport()
        let client = makeClient(transport: transport)

        let firstStart = Task { try await client.start() }
        let initialize = try await transport.request(at: 0)
        XCTAssertEqual(initialize.id, 1)
        XCTAssertEqual(initialize.method, "initialize")
        let params = try XCTUnwrap(initialize.params)
        let clientInfo = try XCTUnwrap(params.clientInfo)
        XCTAssertEqual(clientInfo.name, "codex-watch")
        XCTAssertEqual(clientInfo.title, "Vibe View")
        XCTAssertEqual(clientInfo.version, "1.3.0")
        let capabilities = try XCTUnwrap(params.capabilities)
        XCTAssertEqual(capabilities.experimentalApi, false)
        XCTAssertEqual(capabilities.requestAttestation, false)

        await transport.deliver(
            #"{"id":1,"result":{"userAgent":"codex-cli/0.151.0","codexHome":"/private/tmp/codex-home","platformFamily":"unix","platformOs":"macos","future":true}}"#
        )
        try await firstStart.value
        try await client.start()

        let requests = await transport.allSentRequests()
        XCTAssertEqual(requests.filter { $0.method == "initialize" }.count, 1)
        XCTAssertEqual(requests.filter { $0.method == "initialized" }.count, 1)
    }

    func testTypedOperationsEmitOfficialRequestShapesAndMatchIntegerIDs() async throws {
        let transport = InMemoryAppServerLineTransport()
        let client = makeClient(transport: transport)
        try await start(client, transport: transport)

        let accountTask = Task { try await client.readAccount() }
        let accountRequest = try await transport.request(at: 2)
        XCTAssertEqual(accountRequest.id, 2)
        XCTAssertEqual(accountRequest.method, "account/read")
        XCTAssertEqual(accountRequest.params?.refreshToken, false)

        let rateLimitsTask = Task { try await client.readRateLimits() }
        let rateLimitsRequest = try await transport.request(at: 3)
        XCTAssertEqual(rateLimitsRequest.id, 3)
        XCTAssertEqual(rateLimitsRequest.method, "account/rateLimits/read")
        XCTAssertNil(rateLimitsRequest.params)

        await transport.deliver(rateLimitsResponse(id: 3, usedPercent: 37))
        await transport.deliver(
            #"{"id":2,"result":{"account":{"type":"chatgpt","email":"private@example.com","planType":"pro"},"requiresOpenaiAuth":true,"future":1}}"#
        )

        let account = try await accountTask.value
        let rateLimits = try await rateLimitsTask.value
        XCTAssertEqual(account.account, .chatGPT(planType: .pro))
        XCTAssertTrue(account.requiresOpenAIAuth)
        XCTAssertEqual(rateLimits.rateLimits.primary?.usedPercent, 37)

        let usageTask = Task { try await client.readAccountUsage() }
        let usageRequest = try await transport.request(at: 4)
        XCTAssertEqual(usageRequest.id, 4)
        XCTAssertEqual(usageRequest.method, "account/usage/read")
        XCTAssertNil(usageRequest.params, "Account usage must not request per-thread usage")
        await transport.deliver(
            #"{"id":4,"result":{"summary":{"lifetimeTokens":12,"peakDailyTokens":7,"longestRunningTurnSec":3,"currentStreakDays":2,"longestStreakDays":4},"dailyUsageBuckets":[{"startDate":"2026-08-30","tokens":12}],"threadUsage":{"threadId":"ignored"}}}"#
        )
        let usage = try await usageTask.value
        XCTAssertEqual(usage.summary.lifetimeTokens, 12)

        let resetTask = Task {
            try await client.consumeRateLimitReset(
                idempotencyKey: "02653E00-1B77-483F-9AB0-1A9F20CC2A27",
                creditID: "credit-one"
            )
        }
        let resetRequest = try await transport.request(at: 5)
        XCTAssertEqual(resetRequest.id, 5)
        XCTAssertEqual(
            resetRequest.method,
            "account/rateLimitResetCredit/consume"
        )
        let resetParams = try XCTUnwrap(resetRequest.params)
        XCTAssertEqual(
            resetParams.idempotencyKey,
            "02653E00-1B77-483F-9AB0-1A9F20CC2A27"
        )
        XCTAssertEqual(resetParams.creditID, "credit-one")
        await transport.deliver(#"{"id":5,"result":{"outcome":"reset"}}"#)
        let resetOutcome = try await resetTask.value
        XCTAssertEqual(resetOutcome, .reset)
    }

    func testUnrelatedNotificationIsIgnoredWhileRequestIsPending() async throws {
        let transport = InMemoryAppServerLineTransport()
        let client = makeClient(transport: transport)
        try await start(client, transport: transport)

        let task = Task { try await client.readAccount() }
        await transport.waitForSentLine(at: 2)
        await transport.deliver(#"{"method":"thread/started","params":{"private":"ignored"}}"#)
        await transport.deliver(
            #"{"id":2,"result":{"account":{"type":"apiKey"},"requiresOpenaiAuth":false}}"#
        )

        let account = try await task.value
        XCTAssertEqual(account.account, .apiKey)
    }

    func testRateLimitUpdatedNotificationDecodesOnStream() async throws {
        let transport = InMemoryAppServerLineTransport()
        let client = makeClient(transport: transport)
        try await start(client, transport: transport)
        let stream = await client.rateLimitUpdates()
        let valueTask = Task {
            var iterator = stream.makeAsyncIterator()
            return await iterator.next()
        }

        await transport.deliver(
            #"{"method":"account/rateLimits/updated","params":{"rateLimits":{"limitId":"codex","limitName":null,"primary":{"usedPercent":44,"windowDurationMins":300,"resetsAt":4100},"secondary":null,"credits":null,"individualLimit":null,"spendControlReached":null,"planType":"plus","rateLimitReachedType":null},"future":"ignored"}}"#
        )

        let update = await valueTask.value
        XCTAssertEqual(update?.primary?.usedPercent, 44)
        XCTAssertEqual(update?.planType, .plus)
    }

    func testMalformedLineFailsPendingRequestAndClosesClient() async throws {
        let transport = InMemoryAppServerLineTransport()
        let client = makeClient(transport: transport)
        try await start(client, transport: transport)
        let task = Task { try await client.readAccount() }
        await transport.waitForSentLine(at: 2)

        await transport.deliver("{")

        await assertTask(task, failsWith: .malformedMessage)
        let wasStopped = await transport.wasStopped()
        XCTAssertTrue(wasStopped)
    }

    func testOversizedLineFailsPendingRequestAndClosesClient() async throws {
        let transport = InMemoryAppServerLineTransport()
        let client = makeClient(transport: transport)
        try await start(client, transport: transport)
        let task = Task { try await client.readAccount() }
        await transport.waitForSentLine(at: 2)

        await transport.deliver(Data(repeating: 0x61, count: 1_048_577))

        await assertTask(task, failsWith: .lineTooLarge(maxBytes: 1_048_576))
        let wasStopped = await transport.wasStopped()
        XCTAssertTrue(wasStopped)
    }

    func testNonIntegerResponseIDFailsClosed() async throws {
        let transport = InMemoryAppServerLineTransport()
        let client = makeClient(transport: transport)
        try await start(client, transport: transport)
        let task = Task { try await client.readAccount() }
        await transport.waitForSentLine(at: 2)

        await transport.deliver(
            #"{"id":2.0,"result":{"account":{"type":"apiKey"},"requiresOpenaiAuth":false}}"#
        )

        await assertTask(task, failsWith: .malformedMessage)
        let wasStopped = await transport.wasStopped()
        XCTAssertTrue(wasStopped)
    }

    func testTerminationCancelsEveryPendingContinuation() async throws {
        let transport = InMemoryAppServerLineTransport()
        let client = makeClient(transport: transport)
        try await start(client, transport: transport)
        let accountTask = Task { try await client.readAccount() }
        let usageTask = Task { try await client.readAccountUsage() }
        await transport.waitForSentLine(at: 2)
        await transport.waitForSentLine(at: 3)

        await transport.terminate()

        await assertTask(accountTask, failsWith: .terminated)
        await assertTask(usageTask, failsWith: .terminated)
    }

    func testPendingRequestTimesOutWithoutWaitingForever() async throws {
        let transport = InMemoryAppServerLineTransport()
        let client = CodexAppServerClient(
            transport: transport,
            clientInfo: AppServerClientInfo(
                name: "codex-watch",
                title: "Vibe View",
                version: "1.3.0"
            ),
            requestTimeout: .milliseconds(10)
        )
        try await start(client, transport: transport)

        let task = Task { try await client.readRateLimits() }
        await transport.waitForSentLine(at: 2)

        await assertTask(task, failsWith: .timedOut)
    }

    func testEveryDocumentedResetOutcomeDecodesExactly() async throws {
        let cases: [(String, AppServerResetOutcome)] = [
            ("reset", .reset),
            ("nothingToReset", .nothingToReset),
            ("noCredit", .noCredit),
            ("alreadyRedeemed", .alreadyRedeemed)
        ]

        for (index, testCase) in cases.enumerated() {
            let transport = InMemoryAppServerLineTransport()
            let client = makeClient(transport: transport)
            try await start(client, transport: transport)
            let task = Task {
                try await client.consumeRateLimitReset(
                    idempotencyKey: "00000000-0000-0000-0000-00000000000\(index)"
                )
            }
            await transport.waitForSentLine(at: 2)
            await transport.deliver(
                #"{"id":2,"result":{"outcome":"\#(testCase.0)"}}"#
            )
            let outcome = try await task.value
            XCTAssertEqual(outcome, testCase.1)
        }
    }

    func testResetConsumeRejectsNonUUIDIdempotencyKeyWithoutSending() async throws {
        let transport = InMemoryAppServerLineTransport()
        let client = makeClient(transport: transport)
        try await start(client, transport: transport)

        let task = Task {
            try await client.consumeRateLimitReset(idempotencyKey: "not-a-uuid")
        }
        try await Task.sleep(for: .milliseconds(10))
        task.cancel()

        await assertTask(task, failsWith: .invalidIdempotencyKey)
        let sentCount = await transport.sentCount()
        XCTAssertEqual(sentCount, 2)
    }

    func testReaderFailureCleansTransportEvenAfterClientHasTerminated() async throws {
        let transport = InMemoryAppServerLineTransport()
        let client = makeClient(transport: transport)
        try await start(client, transport: transport)
        await transport.terminate()
        let stopped = await transport.wasStopped()
        XCTAssertTrue(stopped)
        await client.stop()
        let stillStopped = await transport.wasStopped()
        XCTAssertTrue(stillStopped)
    }

    private func makeClient(
        transport: InMemoryAppServerLineTransport
    ) -> CodexAppServerClient {
        CodexAppServerClient(
            transport: transport,
            clientInfo: AppServerClientInfo(
                name: "codex-watch",
                title: "Vibe View",
                version: "1.3.0"
            )
        )
    }

    private func start(
        _ client: CodexAppServerClient,
        transport: InMemoryAppServerLineTransport
    ) async throws {
        let task = Task { try await client.start() }
        await transport.waitForSentLine(at: 0)
        await transport.deliver(
            #"{"id":1,"result":{"userAgent":"codex-cli/0.151.0","codexHome":"/private/tmp/codex-home","platformFamily":"unix","platformOs":"macos"}}"#
        )
        try await task.value
        await transport.waitForSentLine(at: 1)
    }

    private func rateLimitsResponse(id: Int, usedPercent: Int) -> String {
        #"{"id":\#(id),"result":{"rateLimits":{"limitId":"codex","limitName":"Codex","primary":{"usedPercent":\#(usedPercent),"windowDurationMins":300,"resetsAt":4100},"secondary":null,"credits":null,"individualLimit":null,"spendControlReached":null,"planType":"pro","rateLimitReachedType":null},"rateLimitsByLimitId":null,"rateLimitResetCredits":null}}"#
    }

    private func assertTask<Value>(
        _ task: Task<Value, Error>,
        failsWith expected: AppServerError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await task.value
            XCTFail("Expected task to fail", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? AppServerError, expected, file: file, line: line)
        }
    }
}

private actor InMemoryAppServerLineTransport: AppServerLineTransport {
    private var receiveLine: (@Sendable (Data) async -> Void)?
    private var termination: (@Sendable (Error?) async -> Void)?
    private var sentLines: [Data] = []
    private var lineWaiters: [Int: [CheckedContinuation<Data, Never>]] = [:]
    private var stopped = false

    func start(
        receiveLine: @escaping @Sendable (Data) async -> Void,
        termination: @escaping @Sendable (Error?) async -> Void
    ) async throws {
        self.receiveLine = receiveLine
        self.termination = termination
    }

    func send(_ line: Data) async throws {
        let index = sentLines.count
        sentLines.append(line)
        let waiters = lineWaiters.removeValue(forKey: index) ?? []
        for waiter in waiters {
            waiter.resume(returning: line)
        }
    }

    func stop() async {
        stopped = true
    }

    func deliver(_ line: String) async {
        await deliver(Data(line.utf8))
    }

    func deliver(_ line: Data) async {
        await receiveLine?(line)
    }

    func terminate() async {
        await termination?(nil)
    }

    func request(at index: Int) async throws -> SentRequestSnapshot {
        let data = await line(at: index)
        return try JSONDecoder().decode(SentRequestSnapshot.self, from: data)
    }

    func allSentRequests() -> [SentRequestSnapshot] {
        sentLines.compactMap { try? JSONDecoder().decode(SentRequestSnapshot.self, from: $0) }
    }

    func waitForSentLine(at index: Int) async {
        _ = await line(at: index)
    }

    func wasStopped() -> Bool {
        stopped
    }

    func sentCount() -> Int {
        sentLines.count
    }

    private func line(at index: Int) async -> Data {
        if sentLines.indices.contains(index) {
            return sentLines[index]
        }
        return await withCheckedContinuation { continuation in
            lineWaiters[index, default: []].append(continuation)
        }
    }
}

private struct SentRequestSnapshot: Decodable, Equatable, Sendable {
    struct Params: Decodable, Equatable, Sendable {
        struct ClientInfo: Decodable, Equatable, Sendable {
            let name: String
            let title: String?
            let version: String
        }

        struct Capabilities: Decodable, Equatable, Sendable {
            let experimentalApi: Bool
            let requestAttestation: Bool
        }

        let clientInfo: ClientInfo?
        let capabilities: Capabilities?
        let refreshToken: Bool?
        let idempotencyKey: String?
        let creditID: String?

        private enum CodingKeys: String, CodingKey {
            case clientInfo
            case capabilities
            case refreshToken
            case idempotencyKey
            case creditID = "creditId"
        }
    }

    let id: Int?
    let method: String
    let params: Params?
}
