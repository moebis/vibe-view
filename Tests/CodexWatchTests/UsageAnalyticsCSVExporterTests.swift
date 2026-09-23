import Foundation
import XCTest
@testable import CodexWatch

final class UsageAnalyticsCSVExporterTests: XCTestCase {
    func testCSVContainsMetadataDailyModelsAndClients() throws {
        let projection = makeCSVProjection()

        let csv = try UsageAnalyticsCSVExporter.string(projection: projection)
        let expectedRows = [
            "Vibe View analytics,30d",
            "Data through,2026-08-19",
            "Coverage,1/30 days",
            "",
            "Daily usage",
            "Date,Status,Total tokens,Input tokens,Cached input,Output tokens,Turns,Chats",
            "2026-08-19,Observed,100,20,30,50,4,2",
            "2026-08-20,Missing,,,,,,",
            "",
            "Model activity",
            "Model,Turns,Chats,Credits,Turn share",
            "\"gpt-5.6-sol, preview\",4,2,1.5,100%",
            "",
            "Client tokens",
            "Client,Total tokens,Input tokens,Cached input,Output tokens,Turns,Chats",
            "CODEX_DESKTOP_APP,100,20,30,50,4,2",
            ""
        ]

        XCTAssertEqual(csv, expectedRows.joined(separator: "\r\n") + "\r\n")
    }

    func testCSVQuotesQuotesCommasCarriageReturnsAndNewlines() {
        XCTAssertEqual(
            UsageAnalyticsCSVExporter.escape("a,\"b\"\nc"),
            "\"a,\"\"b\"\"\nc\""
        )
        XCTAssertEqual(UsageAnalyticsCSVExporter.escape("a\rb"), "\"a\rb\"")
        XCTAssertEqual(UsageAnalyticsCSVExporter.escape("plain"), "plain")
    }

    func testServerSuppliedLabelsCannotBecomeSpreadsheetFormulas() {
        XCTAssertEqual(UsageAnalyticsCSVExporter.spreadsheetSafe("=1+1"), "'=1+1")
        XCTAssertEqual(UsageAnalyticsCSVExporter.spreadsheetSafe("  @SUM(A1)"), "'  @SUM(A1)")
        XCTAssertEqual(UsageAnalyticsCSVExporter.spreadsheetSafe("gpt-5.6"), "gpt-5.6")
    }

    func testSuggestedFilenameUsesRangeAndDataThroughDate() {
        XCTAssertEqual(
            UsageAnalyticsCSVExporter.suggestedFilename(
                range: .days30,
                dataThrough: makeDate(year: 2026, month: 8, day: 19)
            ),
            "codex-watch-analytics-30d-2026-08-19.csv"
        )
    }

    func testActivityOnlyCSVRowLeavesTokenFieldsBlank() throws {
        let date = makeDate(year: 2026, month: 1, day: 15)
        let projection = UsageAnalyticsProjection(
            range: .days7,
            periodStart: date,
            periodEnd: date,
            totals: UsageTokenTotals(
                totalTokens: 0,
                uncachedInputTokens: 0,
                cachedInputTokens: 0,
                outputTokens: 0,
                turns: 5,
                chats: 2
            ),
            days: [UsageDayCell(date: date, state: .activityOnly(turns: 5, chats: 2))],
            models: [],
            clients: [],
            comparison: nil,
            dataThrough: nil,
            fetchedAt: date,
            modelBreakdownIsPartial: false,
            clientBreakdownIsPartial: false
        )

        let csv = try UsageAnalyticsCSVExporter.string(projection: projection)

        XCTAssertTrue(csv.contains("2026-01-15,Activity only,,,,,5,2\r\n"))
        XCTAssertFalse(csv.contains("2026-01-15,Observed,0,0,0,0,5,2"))
    }

    func testCSVPreservesProjectionDatesInPositiveOffsetCalendar() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Bratislava")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 19))!
        let projection = UsageAnalyticsProjection(
            range: .days7,
            periodStart: date,
            periodEnd: date,
            totals: .zero,
            days: [UsageDayCell(date: date, state: .activityOnly(turns: 1, chats: 1))],
            models: [],
            clients: [],
            comparison: nil,
            dataThrough: date,
            fetchedAt: date,
            modelBreakdownIsPartial: false,
            clientBreakdownIsPartial: false
        )

        let csv = try UsageAnalyticsCSVExporter.string(
            projection: projection,
            calendar: calendar
        )

        XCTAssertTrue(csv.contains("Data through,2026-08-19\r\n"))
        XCTAssertTrue(csv.contains("2026-08-19,Activity only,,,,,1,1\r\n"))
        XCTAssertEqual(
            UsageAnalyticsCSVExporter.suggestedFilename(
                range: .days7,
                dataThrough: date,
                calendar: calendar
            ),
            "codex-watch-analytics-7d-2026-08-19.csv"
        )
    }

    private func makeCSVProjection() -> UsageAnalyticsProjection {
        let observedDate = makeDate(year: 2026, month: 8, day: 19)
        let missingDate = makeDate(year: 2026, month: 8, day: 20)
        let totals = UsageTokenTotals(
            totalTokens: 100,
            uncachedInputTokens: 20,
            cachedInputTokens: 30,
            outputTokens: 50,
            turns: 4,
            chats: 2
        )
        return UsageAnalyticsProjection(
            range: .days30,
            periodStart: makeDate(year: 2026, month: 7, day: 22),
            periodEnd: missingDate,
            totals: totals,
            days: [
                UsageDayCell(date: observedDate, state: .observed(totals)),
                UsageDayCell(date: missingDate, state: .missing)
            ],
            models: [UsageModelRow(
                model: "gpt-5.6-sol, preview",
                turns: 4,
                chats: 2,
                credits: Decimal(string: "1.5")!,
                turnShare: 1
            )],
            clients: [UsageClientRow(clientID: "CODEX_DESKTOP_APP", totals: totals)],
            comparison: nil,
            dataThrough: observedDate,
            fetchedAt: missingDate,
            modelBreakdownIsPartial: false,
            clientBreakdownIsPartial: false
        )
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
