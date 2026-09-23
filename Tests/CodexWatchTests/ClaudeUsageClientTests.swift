import XCTest
@testable import CodexWatch

final class ClaudeUsageClientTests: XCTestCase {
    override func tearDown() {
        ClaudeMockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testBoundedReadUsesOnlyAnthropicSubscriptionEndpoint() async throws {
        ClaudeMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url, ClaudeUsageClient.endpoint)
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
            XCTAssertNil(request.httpBody)
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            return (self.response(200), Data(#"{"seven_day":{"utilization":40}}"#.utf8))
        }
        let value = try await fetch()
        XCTAssertEqual(value.windows.first?.remainingPercent, 60)
    }

    func testAuthRateLimitAndMalformedResponsesFailClosed() async {
        for status in [401, 403, 429, 500] {
            ClaudeMockURLProtocol.requestHandler = { _ in (self.response(status), Data()) }
            do {
                _ = try await fetch()
                XCTFail("Unexpected success")
            } catch {
                let expected: ClaudeConnectionError = status == 429 ? .rateLimited(300)
                    : (status == 500 ? .unavailable : .signInRequired)
                XCTAssertEqual(error as? ClaudeConnectionError, expected)
            }
        }
        ClaudeMockURLProtocol.requestHandler = { _ in
            (self.response(200), Data(repeating: 32, count: ClaudeUsageClient.maximumResponseSize + 1))
        }
        do { _ = try await fetch(); XCTFail("Oversized response accepted") } catch { }
    }

    func testRetryAfterAndCrossOriginBoundaries() {
        XCTAssertEqual(ClaudeUsageClient.retryDelay("-10"), 60)
        XCTAssertEqual(ClaudeUsageClient.retryDelay("7200"), 3_600)
        XCTAssertEqual(ClaudeUsageClient.retryDelay("nan"), 300)
        XCTAssertEqual(ClaudeUsageClient.retryDelay("Thu, 01 Jan 1970 00:02:00 GMT", now: Date(timeIntervalSince1970: 0)), 120)
        XCTAssertFalse(SameHostHTTPSRedirectDelegate.allowsRedirect(
            from: ClaudeUsageClient.endpoint, to: URL(string: "https://example.org/api/oauth/usage")))
        XCTAssertFalse(SameHostHTTPSRedirectDelegate.allowsRedirect(
            from: ClaudeUsageClient.endpoint, to: URL(string: "http://api.anthropic.com/api/oauth/usage")))
    }

    private func fetch() async throws -> ClaudeUsageSnapshot {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ClaudeMockURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        return try await ClaudeUsageClient(session: session).fetch(credentials: ClaudeCredentials(accessToken: "fixture-token"))
    }

    private func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: ClaudeUsageClient.endpoint, statusCode: status, httpVersion: nil, headerFields: nil)!
    }
}

private final class ClaudeMockURLProtocol: URLProtocol {
    private static let requestHandlerStore = ClaudeRequestHandlerStore()

    static var requestHandler: ClaudeRequestHandlerStore.Handler? {
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

private final class ClaudeRequestHandlerStore: @unchecked Sendable {
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
