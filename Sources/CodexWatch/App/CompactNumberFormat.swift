import Foundation

/// Shared K/M/B token-count formatting for the menu and dashboards.
enum CompactNumberFormat {
    private static let units: [(threshold: Double, suffix: String)] = [
        (1_000_000_000, "B"),
        (1_000_000, "M"),
        (1_000, "K")
    ]
    private static let locale = Locale(identifier: "en_US_POSIX")

    static func string(_ value: Int64) -> String {
        let numeric = Double(value)
        guard var index = units.firstIndex(where: { abs(numeric) >= $0.threshold }) else {
            return String(value)
        }
        var text = format(numeric / units[index].threshold)
        // 999_950 rounds to "1000.0"; promote it to "1M" rather than "1000K".
        if index > 0, abs(Double(text) ?? 0) >= 1_000 {
            index -= 1
            text = format(numeric / units[index].threshold)
        }
        if text.hasSuffix(".0") { text.removeLast(2) }
        return text + units[index].suffix
    }

    private static func format(_ scaled: Double) -> String {
        String(format: abs(scaled) >= 100 ? "%.0f" : "%.1f", locale: locale, scaled)
    }
}
