import Foundation

struct ClaudeUsageClient: Sendable {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let maximumResponseSize = 65_536
    let session: URLSession

    func fetch(credentials: ClaudeCredentials) async throws -> ClaudeUsageSnapshot {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw ClaudeConnectionError.unavailable
        }
        switch response.statusCode {
        case 200: break
        case 401, 403: throw ClaudeConnectionError.signInRequired
        case 429:
            throw ClaudeConnectionError.rateLimited(Self.retryDelay(response.value(forHTTPHeaderField: "Retry-After")))
        default: throw ClaudeConnectionError.unavailable
        }
        guard response.expectedContentLength <= Self.maximumResponseSize else {
            throw ClaudeConnectionError.unavailable
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < Self.maximumResponseSize else { throw ClaudeConnectionError.unavailable }
            data.append(byte)
        }
        return try ClaudeUsageSnapshot.parse(data)
    }

    static func retryDelay(_ header: String?, now: Date = .now) -> TimeInterval {
        if let header, let seconds = Double(header), seconds.isFinite {
            return min(3_600, max(60, seconds))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let header, let date = formatter.date(from: header) {
            return min(3_600, max(60, date.timeIntervalSince(now)))
        }
        return 300
    }
}
