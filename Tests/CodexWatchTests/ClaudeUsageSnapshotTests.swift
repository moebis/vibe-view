import XCTest
@testable import CodexWatch

final class ClaudeUsageSnapshotTests: XCTestCase {
    func testIndependentSubscriptionWindowsAndFractionalResets() throws {
        let value = try ClaudeUsageSnapshot.parse(Data(#"{"five_hour":{"utilization":23.5,"resets_at":"2026-09-24T01:00:00.123Z"},"seven_day":{"utilization":70,"resets_at":"2026-09-29T01:00:00Z"},"seven_day_sonnet":null,"unknown":{"utilization":4}}"#.utf8))
        XCTAssertEqual(value.windows.map(\.title), ["Five-hour", "Weekly"])
        XCTAssertEqual(value.windows.map(\.remainingPercent), [76.5, 30])
        XCTAssertTrue(value.windows.allSatisfy { $0.resetsAt != nil })
    }

    func testMissingAndMalformedQuotaIsNeverReportedAsUnused() {
        for payload in ["{}", "[]", #"{"five_hour":{"utilization":true}}"#,
                        #"{"seven_day":{"utilization":-1}}"#,
                        #"{"seven_day":{"utilization":101}}"#,
                        #"{"seven_day":{"utilization":"30"}}"#] {
            XCTAssertThrowsError(try ClaudeUsageSnapshot.parse(Data(payload.utf8)))
        }
        XCTAssertThrowsError(try ClaudeUsageSnapshot.parse(Data(repeating: 32, count: 65_537)))
    }

    func testBadOptionalWindowDoesNotHideValidQuotaAndMissingResetStaysUnknown() throws {
        let value = try ClaudeUsageSnapshot.parse(Data(#"{"five_hour":{"utilization":0},"seven_day":{"utilization":false},"seven_day_opus":{"utilization":100,"resets_at":"invalid"}}"#.utf8))
        XCTAssertEqual(value.windows.map(\.remainingPercent), [100, 0])
        XCTAssertTrue(value.windows.allSatisfy { $0.resetsAt == nil })
    }
}
