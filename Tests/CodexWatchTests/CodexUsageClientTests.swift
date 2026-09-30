import Foundation
import XCTest
@testable import CodexWatch

final class CodexUsageClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testWeeklyOnlyResponseCreatesOneWeeklyWindow() async throws {
        let responseData = try Data(contentsOf: fixtureURL("usage-weekly-only.json"))
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-access-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "acct_fixture")
            return (self.response(status: 200), responseData)
        }

        let snapshot = try await makeClient().fetch()

        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.plan, .plus)
        XCTAssertEqual(snapshot.creditsRemaining, .balance("100"))
        XCTAssertEqual(snapshot.windows.first?.kind, .weekly)
        XCTAssertEqual(snapshot.windows.first?.usedPercent, 5)
        XCTAssertEqual(snapshot.windows.first?.durationSeconds, 604_800)
        XCTAssertEqual(snapshot.availableResetCredits, 2)
    }

    func testAnalyticsDatasetRequestUsesTrailingThreeHundredSixtyFiveDays() async throws {
        let responseData = try Data(contentsOf: fixtureURL("usage-analytics-365-partial.json"))
        let referenceDate = ISO8601DateFormatter().date(from: "2026-08-20T12:00:00Z")!
        let calendar = utcCalendar()
        MockURLProtocol.requestHandler = { request in
            let query = Dictionary(
                uniqueKeysWithValues: URLComponents(
                    url: try XCTUnwrap(request.url),
                    resolvingAgainstBaseURL: false
                )?.queryItems?.compactMap { item in
                    item.value.map { (item.name, $0) }
                } ?? []
            )
            XCTAssertEqual(query["start_date"], "2025-08-21")
            XCTAssertEqual(query["end_date"], "2026-08-20")
            XCTAssertEqual(query["group_by"], "day")
            XCTAssertEqual(query["workspace_user"], "true")
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-access-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "acct_fixture")
            return (self.response(status: 200, url: request.url), responseData)
        }

        let dataset = try await makeClient().fetchAnalyticsDataset(
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(dataset.requestedStart, day("2025-08-21", calendar: calendar))
        XCTAssertEqual(dataset.requestedEnd, day("2026-08-20", calendar: calendar))
        XCTAssertEqual(dataset.days.count, 2)
    }

    func testAnalyticsEndpointOnAnotherHostIsRejectedBeforeSendingCredentials() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.requestHandler = { _ in
            XCTFail("An analytics request to another host must not be sent")
            return (self.response(status: 500), Data())
        }
        let client = CodexUsageClient(
            credentials: CodexCredentials(accessToken: "fixture-access-token", accountID: nil),
            session: URLSession(configuration: configuration),
            endpoint: URL(string: "https://example.test/backend-api/wham/usage")!,
            analyticsEndpoint: URL(string: "https://other.example/analytics")!
        )

        do {
            _ = try await client.fetchAnalyticsDataset()
            XCTFail("Expected an invalid response error")
        } catch let error as CodexUsageError {
            XCTAssertEqual(error, .invalidHTTPResponse)
        }
    }

    func testProfileRequestUsesSameHostEndpointAndExistingCredentials() async throws {
        let responseData = try Data(contentsOf: fixtureURL("profile-stats-complete.json"))
        let fetchedAt = ISO8601DateFormatter().date(from: "2026-08-20T12:00:00Z")!
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/backend-api/wham/profiles/me")
            XCTAssertNil(request.url?.query)
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer fixture-access-token"
            )
            XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "acct_fixture")
            return (self.response(status: 200, url: request.url), responseData)
        }

        let profile = try await makeClient().fetchProfileStats(referenceDate: fetchedAt)

        XCTAssertEqual(profile.lifetimeTokens, 30_300_000_000)
        XCTAssertEqual(profile.fetchedAt, fetchedAt)
    }

    func testProfileEndpointOnAnotherHostIsRejectedBeforeSendingCredentials() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.requestHandler = { _ in
            XCTFail("A profile request to another host must not be sent")
            return (self.response(status: 500), Data())
        }
        let client = CodexUsageClient(
            credentials: CodexCredentials(accessToken: "fixture-access-token", accountID: nil),
            session: URLSession(configuration: configuration),
            endpoint: URL(string: "https://example.test/backend-api/wham/usage")!,
            profileEndpoint: URL(string: "https://other.example/profiles/me")!
        )

        do {
            _ = try await client.fetchProfileStats()
            XCTFail("Expected an invalid response error")
        } catch let error as CodexUsageError {
            XCTAssertEqual(error, .invalidHTTPResponse)
        }
    }

    func testOversizedProfileResponseIsRejectedBeforeDecoding() async throws {
        let oversizedResponse = Data(repeating: 0x20, count: 1_048_577)
        MockURLProtocol.requestHandler = { request in
            (self.response(status: 200, url: request.url), oversizedResponse)
        }

        do {
            _ = try await makeClient().fetchProfileStats()
            XCTFail("Expected an oversized response error")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .dataLengthExceedsMaximum)
        }
    }

    func testOversizedAnalyticsResponseIsRejectedBeforeDecoding() async throws {
        let oversizedResponse = Data(repeating: 0x20, count: 1_048_577)
        MockURLProtocol.requestHandler = { request in
            (self.response(status: 200, url: request.url), oversizedResponse)
        }

        do {
            _ = try await makeClient().fetchAnalyticsDataset()
            XCTFail("Expected an oversized response error")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .dataLengthExceedsMaximum)
        }
    }

    func testMissingNewAnalyticsPreservesLastSuccessfulInMemoryDataset() {
        let calendar = utcCalendar()
        let end = day("2026-08-20", calendar: calendar)
        let previous = UsageAnalyticsDataset(
            requestedStart: day("2025-08-21", calendar: calendar),
            requestedEnd: end,
            days: [],
            fetchedAt: end,
            modelBreakdownIsPartial: false,
            clientBreakdownIsPartial: false
        )
        let snapshot = UsageSnapshot(windows: [], analyticsDataset: previous)

        XCTAssertEqual(snapshot.adding(analyticsDataset: nil).analyticsDataset, previous)
    }

    func testMissingNewProfilePreservesLastSuccessfulInMemoryProfile() {
        let previous = CodexProfileStats(
            lifetimeTokens: 30_300_000_000,
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
        let snapshot = UsageSnapshot(windows: [], profileStats: previous)

        XCTAssertEqual(snapshot.adding(profileStats: nil).profileStats, previous)
    }

    func testMultipleWindowsAreClassifiedIndependently() async throws {
        let responseData = try Data(contentsOf: fixtureURL("usage-multiple-windows.json"))
        MockURLProtocol.requestHandler = { _ in
            (self.response(status: 200), responseData)
        }

        let snapshot = try await makeClient().fetch()

        XCTAssertEqual(snapshot.windows.map(\.kind), [.rolling(hours: 5), .weekly])
        XCTAssertEqual(snapshot.plan, .plus)
        XCTAssertEqual(snapshot.windows.map(\.id), ["primary", "secondary"])
        XCTAssertEqual(snapshot.availableResetCredits, 1)
    }

    func testCurrentResponseReadsWindowsNestedUnderRateLimit() async throws {
        let responseData = try Data(contentsOf: fixtureURL("usage-nested-rate-limit.json"))
        MockURLProtocol.requestHandler = { _ in
            (self.response(status: 200), responseData)
        }

        let snapshot = try await makeClient().fetch()

        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.plan, .plus)
        XCTAssertEqual(snapshot.windows.first?.kind, .weekly)
        XCTAssertEqual(snapshot.windows.first?.usedPercent, 20)
        XCTAssertEqual(snapshot.windows.first?.remainingPercent, 80)
    }

    func testUnknownOrMissingPlanIsNotExposed() throws {
        let unknown = try JSONDecoder().decode(
            UsageResponseDTO.self,
            from: Data(#"{"plan_type":"unreleased-tier"}"#.utf8)
        ).snapshot()
        let missing = try JSONDecoder().decode(
            UsageResponseDTO.self,
            from: Data("{}".utf8)
        ).snapshot()

        XCTAssertNil(unknown.plan)
        XCTAssertNil(missing.plan)
    }

    func testProLitePlanIsRecognized() throws {
        let snapshot = try JSONDecoder().decode(
            UsageResponseDTO.self,
            from: Data(#"{"plan_type":"prolite"}"#.utf8)
        ).snapshot()

        XCTAssertEqual(snapshot.plan, .proLite)
    }

    func testCurrentBusinessPlanVariantsNormalizeToBusiness() throws {
        for apiValue in [
            "team",
            "self_serve_business_prolite",
            "self_serve_business_usage_based"
        ] {
            let snapshot = try JSONDecoder().decode(
                UsageResponseDTO.self,
                from: Data("{\"plan_type\":\"\(apiValue)\"}".utf8)
            ).snapshot()

            XCTAssertEqual(snapshot.plan, .business, apiValue)
        }
    }

    func testCurrentEnterprisePlanVariantsNormalizeToEnterprise() throws {
        for apiValue in [
            "ent26",
            "enterprise_cbp_automation",
            "enterprise_cbp_usage_based"
        ] {
            let snapshot = try JSONDecoder().decode(
                UsageResponseDTO.self,
                from: Data("{\"plan_type\":\"\(apiValue)\"}".utf8)
            ).snapshot()

            XCTAssertEqual(snapshot.plan, .enterprise, apiValue)
        }
    }

    func testCurrentEducationPlanVariantsNormalizeToEdu() throws {
        for apiValue in ["edu_plus", "edu_pro"] {
            let snapshot = try JSONDecoder().decode(
                UsageResponseDTO.self,
                from: Data("{\"plan_type\":\"\(apiValue)\"}".utf8)
            ).snapshot()

            XCTAssertEqual(snapshot.plan, .edu, apiValue)
        }
    }

    func testMissingEntitlementOrInvalidCreditsBalanceIsNotFabricated() throws {
        for json in [
            #"{}"#,
            #"{"credits":{}}"#,
            #"{"credits":{"has_credits":"yes","unlimited":false,"balance":"10"}}"#,
            #"{"credits":{"has_credits":false,"unlimited":false,"balance":"10"}}"#,
            #"{"credits":{"has_credits":true,"unlimited":false,"balance":""}}"#,
            #"{"credits":{"has_credits":true,"unlimited":false,"balance":"NaN"}}"#,
            #"{"credits":{"has_credits":true,"unlimited":false,"balance":"not-a-number"}}"#
        ] {
            let snapshot = try JSONDecoder().decode(
                UsageResponseDTO.self,
                from: Data(json.utf8)
            ).snapshot()
            XCTAssertNil(snapshot.creditsRemaining)
        }
    }

    func testNumericAndNegativeCreditsBalancesAreAccepted() throws {
        let positive = try JSONDecoder().decode(
            UsageResponseDTO.self,
            from: Data(#"{"credits":{"has_credits":true,"unlimited":false,"balance":2.5}}"#.utf8)
        ).snapshot()
        let negative = try JSONDecoder().decode(
            UsageResponseDTO.self,
            from: Data(#"{"credits":{"has_credits":true,"unlimited":false,"balance":"-1.25"}}"#.utf8)
        ).snapshot()

        XCTAssertEqual(positive.creditsRemaining, .balance("2.5"))
        XCTAssertEqual(negative.creditsRemaining, .balance("-1.25"))
    }

    func testReportedZeroUsageCreditsRemainVisibleAfterDepletion() throws {
        let snapshot = try JSONDecoder().decode(
            UsageResponseDTO.self,
            from: Data(#"{"credits":{"has_credits":false,"unlimited":false,"balance":"0"}}"#.utf8)
        ).snapshot(fetchedAt: .now)
        XCTAssertEqual(snapshot.creditsRemaining, .balance("0"))
    }

    func testUnlimitedCreditsTakePrecedenceOverBalance() throws {
        let snapshot = try JSONDecoder().decode(
            UsageResponseDTO.self,
            from: Data(#"{"credits":{"has_credits":true,"unlimited":true,"balance":"10"}}"#.utf8)
        ).snapshot()

        XCTAssertEqual(snapshot.creditsRemaining, .unlimited)
    }

    func testResetCreditDetailsAddNextSupportedAvailableExpiry() async throws {
        let usageData = try Data(contentsOf: fixtureURL("usage-weekly-only.json"))
        let detailsData = try Data(contentsOf: fixtureURL("reset-credits-details.json"))
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == CodexUsageClient.resetCreditsPath {
                XCTAssertNil(request.value(forHTTPHeaderField: "OpenAI-Beta"))
                XCTAssertNil(request.value(forHTTPHeaderField: "originator"))
                return (self.response(status: 200, url: request.url), detailsData)
            }
            return (self.response(status: 200, url: request.url), usageData)
        }

        let snapshot = try await makeClient().fetch()

        XCTAssertEqual(snapshot.availableResetCredits, 2)
        XCTAssertEqual(snapshot.resetCredits.count, 4)
        XCTAssertEqual(snapshot.resetCredits.filter { $0.status == "available" }.count, 3)
        XCTAssertEqual(
            snapshot.nextResetCreditGrantedAt,
            ISO8601DateFormatter().date(from: "2029-12-03T08:30:45Z")
        )
        XCTAssertEqual(
            snapshot.nextResetCreditExpiry,
            ISO8601DateFormatter().date(from: "2030-01-02T08:30:45Z")
        )
    }

    func testResetCreditDetailFailurePreservesUsageAndCount() async throws {
        let usageData = try Data(contentsOf: fixtureURL("usage-weekly-only.json"))
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == CodexUsageClient.resetCreditsPath {
                return (self.response(status: 503, url: request.url), Data())
            }
            return (self.response(status: 200, url: request.url), usageData)
        }

        let snapshot = try await makeClient().fetch()

        XCTAssertEqual(snapshot.availableResetCredits, 2)
        XCTAssertNil(snapshot.nextResetCreditGrantedAt)
        XCTAssertNil(snapshot.nextResetCreditExpiry)
        XCTAssertEqual(snapshot.windows.count, 1)
    }

    func testZeroResetCreditsDoesNotRequestDetails() async throws {
        let responseData = Data(
            """
            {
              "secondary_window": {
                "used_percent": 5,
                "limit_window_seconds": 604800
              },
              "rate_limit_reset_credits": {
                "available_count": 0
              }
            }
            """.utf8
        )
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/backend-api/wham/usage")
            return (self.response(status: 200, url: request.url), responseData)
        }

        let snapshot = try await makeClient().fetch()

        XCTAssertEqual(snapshot.availableResetCredits, 0)
        XCTAssertNil(snapshot.nextResetCreditGrantedAt)
        XCTAssertNil(snapshot.nextResetCreditExpiry)
    }

    func testRequestDisablesCaching() async throws {
        let responseData = try Data(contentsOf: fixtureURL("usage-weekly-only.json"))
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            return (self.response(status: 200), responseData)
        }

        _ = try await makeClient().fetch()
    }

    func testOversizedUsageResponseIsRejectedBeforeDecoding() async throws {
        let oversizedResponse = Data(repeating: 0x20, count: 1_048_577)
        MockURLProtocol.requestHandler = { request in
            (self.response(status: 200, url: request.url), oversizedResponse)
        }

        do {
            _ = try await makeClient().fetch()
            XCTFail("Expected an oversized response error")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .dataLengthExceedsMaximum)
        } catch {
            XCTFail("Expected an oversized response error, got \(error)")
        }
    }

    func testExtremeResetTimestampIsDiscarded() throws {
        let snapshot = try JSONDecoder().decode(
            UsageResponseDTO.self,
            from: Data(
                #"{"secondary_window":{"used_percent":5,"limit_window_seconds":604800,"reset_at":1e300}}"#.utf8
            )
        ).snapshot()

        XCTAssertNil(snapshot.weeklyWindow?.resetAt)
    }

    func testUnauthorizedResponseRequiresReauthentication() async throws {
        MockURLProtocol.requestHandler = { _ in
            (self.response(status: 401), Data())
        }

        do {
            _ = try await makeClient().fetch()
            XCTFail("Expected a reauthentication error")
        } catch let error as CodexUsageError {
            XCTAssertEqual(error, .reauthenticationRequired)
        }
    }

    func testCancelledRefreshDoesNotCreateTaskInInvalidatedSession() async {
        let session = URLSession(configuration: .ephemeral)
        session.invalidateAndCancel()
        let client = CodexUsageClient(
            credentials: CodexCredentials(accessToken: "fixture-access-token", accountID: nil),
            session: session
        )
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await client.fetch()
                XCTFail("A cancelled refresh must not start network work")
            } catch {
                XCTAssertTrue(error is CancellationError)
            }
        }
        await cancelled.value
    }

    func testPlainHTTPIsRejectedBeforeSendingCredentials() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.requestHandler = { _ in
            XCTFail("An insecure request must not be sent")
            return (self.response(status: 500), Data())
        }
        let client = CodexUsageClient(
            credentials: CodexCredentials(accessToken: "fixture-access-token", accountID: nil),
            session: URLSession(configuration: configuration),
            endpoint: URL(string: "http://example.test/backend-api/wham/usage")!
        )

        do {
            _ = try await client.fetch()
            XCTFail("Expected an invalid response error")
        } catch let error as CodexUsageError {
            XCTAssertEqual(error, .invalidHTTPResponse)
        }
    }

    func testRedirectRequiresTheSameEffectiveHTTPSPort() {
        let original = URL(string: "https://example.test/backend-api/wham/usage")!

        XCTAssertTrue(SameHostHTTPSRedirectDelegate.allowsRedirect(
            from: original,
            to: URL(string: "https://example.test:443/next")!
        ))
        XCTAssertFalse(SameHostHTTPSRedirectDelegate.allowsRedirect(
            from: original,
            to: URL(string: "https://example.test:8443/next")!
        ))
        XCTAssertFalse(SameHostHTTPSRedirectDelegate.allowsRedirect(
            from: original,
            to: URL(string: "http://example.test/next")!
        ))
    }

    func testResetCreditEndpointOnAnotherHostIsRejectedWithoutBreakingUsage() async throws {
        let usageData = try Data(contentsOf: fixtureURL("usage-weekly-only.json"))
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.host, "example.test")
            return (self.response(status: 200, url: request.url), usageData)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let client = CodexUsageClient(
            credentials: CodexCredentials(accessToken: "fixture-access-token", accountID: nil),
            session: URLSession(configuration: configuration),
            endpoint: URL(string: "https://example.test/backend-api/wham/usage")!,
            resetCreditsEndpoint: URL(string: "https://other.example/reset-credits")!
        )

        let snapshot = try await client.fetch()

        XCTAssertEqual(snapshot.availableResetCredits, 2)
        XCTAssertNil(snapshot.nextResetCreditExpiry)
    }

    private func makeClient() -> CodexUsageClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return CodexUsageClient(
            credentials: CodexCredentials(
                accessToken: "fixture-access-token",
                accountID: "acct_fixture"
            ),
            session: URLSession(configuration: configuration),
            endpoint: URL(string: "https://example.test/backend-api/wham/usage")!
        )
    }

    private func response(status: Int, url: URL? = nil) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url ?? URL(string: "https://example.test/backend-api/wham/usage")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func day(_ text: String, calendar: Calendar) -> Date {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(
            year: parts[0],
            month: parts[1],
            day: parts[2]
        ))!
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
    }
}

private final class MockURLProtocol: URLProtocol {
    private static let requestHandlerStore = RequestHandlerStore()

    static var requestHandler: RequestHandlerStore.Handler? {
        get { requestHandlerStore.get() }
        set { requestHandlerStore.set(newValue) }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.requestHandler else {
                throw URLError(.badServerResponse)
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class RequestHandlerStore: @unchecked Sendable {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    private let lock = NSLock()
    private var handler: Handler?

    func get() -> Handler? {
        lock.lock()
        defer { lock.unlock() }
        return handler
    }

    func set(_ handler: Handler?) {
        lock.lock()
        defer { lock.unlock() }
        self.handler = handler
    }
}
