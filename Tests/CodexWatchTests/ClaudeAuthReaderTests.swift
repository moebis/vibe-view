import XCTest
import Darwin
@testable import CodexWatch

final class ClaudeAuthReaderTests: XCTestCase {
    func testOnlySubscriptionProfileCredentialsAreAccepted() throws {
        let data = fixture()
        let result = try ClaudeAuthReader.parse(data, now: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(result.accessToken, "fixture-token")
        XCTAssertThrowsError(try ClaudeAuthReader.parse(fixture(scopes: ["user:inference"])))
        XCTAssertThrowsError(try ClaudeAuthReader.parse(Data(#"{"apiKey":"fixture"}"#.utf8)))
        XCTAssertThrowsError(try ClaudeAuthReader.parse(Data(repeating: 32, count: ClaudeAuthReader.maximumSize + 1)))
    }

    func testExpiredAndHeaderUnsafeTokensAreRejected() {
        XCTAssertThrowsError(try ClaudeAuthReader.parse(fixture(expires: 1_000), now: Date(timeIntervalSince1970: 2))) { error in
            XCTAssertEqual(error as? ClaudeConnectionError, .signInRequired)
        }
        for token in ["", "a\nb", "a b", String(repeating: "x", count: 16_385)] {
            XCTAssertThrowsError(try ClaudeAuthReader.parse(fixture(token: token)))
        }
    }

    func testCustomConfigurationDoesNotReadDefaultAccount() {
        let reader = ClaudeAuthReader(environment: ["CLAUDE_CONFIG_DIR": "/another-account"])
        XCTAssertThrowsError(try reader.read()) { error in
            XCTAssertEqual(error as? ClaudeConnectionError, .unsupportedConfiguration)
        }
    }

    func testFallbackBoundsAndNonRegularFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("credentials")
        let valid = fixture()
        try valid.write(to: file)
        XCTAssertEqual(try ClaudeAuthReader.readFallback(at: file), valid)
        try Data(repeating: 32, count: ClaudeAuthReader.maximumSize + 1).write(to: file)
        XCTAssertThrowsError(try ClaudeAuthReader.readFallback(at: file))
        let pipe = root.appendingPathComponent("pipe")
        XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)
        XCTAssertThrowsError(try ClaudeAuthReader.readFallback(at: pipe))
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertThrowsError(try ClaudeAuthReader.readFallback(at: link))
        XCTAssertThrowsError(try ClaudeAuthReader.readFallback(at: root))
    }

    private func fixture(token: String = "fixture-token", expires: Double = 9_000_000_000_000,
                         scopes: [String] = ["user:profile"]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["claudeAiOauth": [
            "accessToken": token, "expiresAt": expires, "scopes": scopes,
            "refreshToken": "ignored-fixture", "subscriptionType": "ignored"
        ]])
    }
}
