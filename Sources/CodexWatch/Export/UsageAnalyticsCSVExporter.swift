import Foundation

enum UsageAnalyticsCSVExporter {
    enum ExportError: Error, Equatable {
        case invalidNumericValue
    }

    static func string(
        projection: UsageAnalyticsProjection,
        calendar: Calendar = .current
    ) throws -> String {
        var rows: [[String]] = [
            ["Vibe View analytics", projection.range.title],
            ["Data through", projection.dataThrough.map { dateText($0, calendar: calendar) } ?? "Unavailable"],
            ["Coverage", "\(projection.observedDayCount)/\(projection.requestedDayCount) days"],
            [],
            ["Daily usage"],
            [
                "Date", "Status", "Total tokens", "Input tokens", "Cached input",
                "Output tokens", "Turns", "Chats"
            ]
        ]

        for day in projection.days {
            switch day.state {
            case let .observed(totals):
                rows.append([
                    dateText(day.date, calendar: calendar),
                    "Observed",
                    String(totals.totalTokens),
                    String(totals.uncachedInputTokens),
                    String(totals.cachedInputTokens),
                    String(totals.outputTokens),
                    String(totals.turns),
                    String(totals.chats)
                ])
            case let .activityOnly(turns, chats):
                rows.append([
                    dateText(day.date, calendar: calendar), "Activity only", "", "", "", "",
                    String(turns), String(chats)
                ])
            case .missing:
                rows.append([dateText(day.date, calendar: calendar), "Missing", "", "", "", "", "", ""])
            }
        }

        rows.append(contentsOf: [
            [],
            ["Model activity"],
            ["Model", "Turns", "Chats", "Credits", "Turn share"]
        ])
        for model in projection.models {
            guard !model.credits.isNaN else { throw ExportError.invalidNumericValue }
            rows.append([
                spreadsheetSafe(model.model),
                String(model.turns),
                String(model.chats),
                NSDecimalNumber(decimal: model.credits).stringValue,
                try percentText(model.turnShare)
            ])
        }

        rows.append(contentsOf: [
            [],
            ["Client tokens"],
            [
                "Client", "Total tokens", "Input tokens", "Cached input",
                "Output tokens", "Turns", "Chats"
            ]
        ])
        for client in projection.clients {
            rows.append([
                spreadsheetSafe(client.clientID),
                String(client.totalTokens),
                String(client.uncachedInputTokens),
                String(client.cachedInputTokens),
                String(client.outputTokens),
                String(client.turns),
                String(client.chats)
            ])
        }
        rows.append([])

        return rows
            .map { $0.map(escape).joined(separator: ",") }
            .joined(separator: "\r\n") + "\r\n"
    }

    static func suggestedFilename(
        range: AnalyticsRange,
        dataThrough: Date?,
        calendar: Calendar = .current
    ) -> String {
        let suffix = dataThrough.map { dateText($0, calendar: calendar) } ?? "unavailable"
        return "codex-watch-analytics-\(range.title)-\(suffix).csv"
    }

    static func escape(_ value: String) -> String {
        guard value.contains(",")
                || value.contains("\"")
                || value.contains("\r")
                || value.contains("\n") else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    static func spreadsheetSafe(_ value: String) -> String {
        let firstSignificant = value.first { !$0.isWhitespace }
        guard let firstSignificant,
              "=+-@".contains(firstSignificant) else { return value }
        return "'\(value)"
    }

    private static func percentText(_ value: Double?) throws -> String {
        guard let value else { return "" }
        guard value.isFinite else { throw ExportError.invalidNumericValue }
        var text = String(
            format: "%.1f",
            locale: Locale(identifier: "en_US_POSIX"),
            value * 100
        )
        if text.hasSuffix(".0") {
            text.removeLast(2)
        }
        return "\(text)%"
    }

    private static func dateText(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            locale: Locale(identifier: "en_US_POSIX"),
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
