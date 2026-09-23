import Foundation

/// Subscription utilization, shared by Claude desktop, web, and Claude Code.
/// Deliberately excludes account metadata, conversations, and API billing.
struct ClaudeUsageSnapshot: Equatable, Sendable {
    struct Window: Equatable, Sendable {
        let title: String
        let usedPercent: Double
        let resetsAt: Date?
        var remainingPercent: Double { 100 - usedPercent }
    }

    let windows: [Window]
    let fetchedAt: Date

    enum ParseError: Error { case invalidResponse }

    static func parse(_ data: Data, fetchedAt: Date = .now) throws -> Self {
        guard data.count <= 65_536,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.invalidResponse
        }
        let dates = ISO8601DateFormatter()
        let fractionalDates = ISO8601DateFormatter()
        fractionalDates.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fields = [("five_hour", "Five-hour"), ("seven_day", "Weekly"),
                      ("seven_day_sonnet", "Sonnet weekly"), ("seven_day_opus", "Opus weekly")]
        let windows = fields.compactMap { key, title -> Window? in
            guard let value = root[key] as? [String: Any],
                  let number = value["utilization"] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite,
                  (0...100).contains(number.doubleValue) else { return nil }
            let reset = (value["resets_at"] as? String).flatMap {
                fractionalDates.date(from: $0) ?? dates.date(from: $0)
            }
            return Window(title: title, usedPercent: number.doubleValue, resetsAt: reset)
        }
        guard !windows.isEmpty else { throw ParseError.invalidResponse }
        return Self(windows: windows, fetchedAt: fetchedAt)
    }
}
