import Foundation

/// Trims server-provided labels to whole characters within a UTF-8 byte budget.
enum BoundedText {
    static func trimmed(_ value: String, maximumUTF8Bytes: Int = 128) -> String {
        var result = ""
        var byteCount = 0
        for character in value.trimmingCharacters(in: .whitespacesAndNewlines) {
            byteCount += character.utf8.count
            guard byteCount <= maximumUTF8Bytes else { break }
            result.append(character)
        }
        return result
    }

    static func trimmedNonEmpty(_ value: String?, maximumUTF8Bytes: Int = 128) -> String? {
        guard let value else { return nil }
        let result = trimmed(value, maximumUTF8Bytes: maximumUTF8Bytes)
        return result.isEmpty ? nil : result
    }
}
