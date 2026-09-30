import Foundation

enum ValidatedDecimal {
    private static let locale = Locale(identifier: "en_US_POSIX")

    static func parse(_ text: String) -> Decimal? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.utf8.count <= 128,
              text.range(
                  of: #"\A[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?\z"#,
                  options: .regularExpression
              ) != nil,
              let value = Decimal(string: text, locale: locale),
              !value.isNaN else { return nil }
        return value
    }
}
