import Foundation

/// Reused parsers for server timestamps with or without fractional seconds.
/// ISO8601DateFormatter is documented as thread-safe.
enum ISO8601Parsing {
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    nonisolated(unsafe) private static let whole = ISO8601DateFormatter()

    static func date(from text: String) -> Date? {
        fractional.date(from: text) ?? whole.date(from: text)
    }
}
