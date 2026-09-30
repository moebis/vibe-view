import Foundation

enum CodexUsageError: Error, Equatable {
    case reauthenticationRequired
    case invalidHTTPResponse
    case httpStatus(Int)
    case decodingFailed
}

enum SecureUsageSession {
    static func make() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        return URLSession(
            configuration: configuration,
            delegate: SameHostHTTPSRedirectDelegate(),
            delegateQueue: nil
        )
    }
}

final class SameHostHTTPSRedirectDelegate: NSObject, URLSessionTaskDelegate {
    static func allowsRedirect(from originalURL: URL?, to redirectURL: URL?) -> Bool {
        guard let originalURL,
              let redirectURL,
              originalURL.scheme?.lowercased() == "https",
              redirectURL.scheme?.lowercased() == "https",
              let originalHost = originalURL.host?.lowercased(),
              redirectURL.host?.lowercased() == originalHost,
              effectivePort(for: redirectURL) == effectivePort(for: originalURL) else {
            return false
        }
        return true
    }

    private static func effectivePort(for url: URL) -> Int? {
        if let port = url.port { return port }
        return url.scheme?.lowercased() == "https" ? 443 : nil
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard Self.allowsRedirect(from: task.originalRequest?.url, to: request.url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

struct CodexUsageClient: Sendable {
    static let defaultEndpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    static let resetCreditsPath = "/backend-api/wham/rate-limit-reset-credits"
    static let analyticsPath = "/backend-api/wham/analytics/daily-workspace-usage-counts"
    static let profilePath = "/backend-api/wham/profiles/me"
    static let maximumResponseSize = 1_048_576

    let credentials: CodexCredentials
    let session: URLSession
    let endpoint: URL
    let resetCreditsEndpoint: URL
    let analyticsEndpoint: URL
    let profileEndpoint: URL

    init(credentials: CodexCredentials,
         session: URLSession = SecureUsageSession.make(),
         endpoint: URL = CodexUsageClient.defaultEndpoint,
         resetCreditsEndpoint: URL? = nil,
         analyticsEndpoint: URL? = nil,
         profileEndpoint: URL? = nil) {
        self.credentials = credentials
        self.session = session
        self.endpoint = endpoint
        self.resetCreditsEndpoint = resetCreditsEndpoint
            ?? endpoint.deletingLastPathComponent().appendingPathComponent("rate-limit-reset-credits")
        self.analyticsEndpoint = analyticsEndpoint ?? Self.defaultAnalyticsEndpoint(from: endpoint)
        self.profileEndpoint = profileEndpoint ?? Self.defaultProfileEndpoint(from: endpoint)
    }

    func fetchProfileStats(referenceDate: Date = .now) async throws -> CodexProfileStats {
        let data = try await fetchData(from: profileEndpoint)
        do {
            let response = try JSONDecoder().decode(CodexProfileResponseDTO.self, from: data)
            guard let profile = response.profileStats(fetchedAt: referenceDate) else {
                throw CodexUsageError.decodingFailed
            }
            return profile
        } catch let error as CodexUsageError {
            throw error
        } catch {
            throw CodexUsageError.decodingFailed
        }
    }

    func fetchAnalyticsDataset(
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) async throws -> UsageAnalyticsDataset {
        let periodEnd = calendar.startOfDay(for: referenceDate)
        guard let periodStart = calendar.date(byAdding: .day, value: -364, to: periodEnd) else {
            throw CodexUsageError.invalidHTTPResponse
        }
        let requestURL = try analyticsRequestURL(
            periodStart: periodStart,
            periodEnd: periodEnd,
            calendar: calendar
        )

        let data = try await fetchData(from: requestURL)
        do {
            let response = try JSONDecoder().decode(UsageAnalyticsResponseDTO.self, from: data)
            guard let dataset = response.dataset(
                requestedStart: periodStart,
                requestedEnd: periodEnd,
                calendar: calendar
            ) else {
                throw CodexUsageError.decodingFailed
            }
            return dataset
        } catch let error as CodexUsageError {
            throw error
        } catch {
            throw CodexUsageError.decodingFailed
        }
    }

    func fetch() async throws -> UsageSnapshot {
        let data = try await fetchData(from: endpoint)
        let snapshot: UsageSnapshot
        do {
            snapshot = try JSONDecoder().decode(UsageResponseDTO.self, from: data).snapshot()
        } catch {
            throw CodexUsageError.decodingFailed
        }

        // Expiry metadata is currently available only from a separate read-only
        // endpoint. Treat it as optional so quota and count display survive an
        // endpoint change, entitlement difference, or transient failure.
        guard let count = snapshot.availableResetCredits,
              count > 0,
              let resetCredits = try? await fetchResetCredits() else {
            return snapshot
        }
        return snapshot.adding(resetCredits: resetCredits)
    }

    private func fetchResetCredits() async throws -> [ResetCredit] {
        let data = try await fetchData(from: resetCreditsEndpoint, timeoutInterval: 5)
        do {
            return try JSONDecoder().decode(ResetCreditDetailsDTO.self, from: data).inventory()
        } catch {
            throw CodexUsageError.decodingFailed
        }
    }

    private func fetchData(
        from endpoint: URL,
        timeoutInterval: TimeInterval = 15
    ) async throws -> Data {
        try Task.checkCancellation()
        guard SameHostHTTPSRedirectDelegate.allowsRedirect(
            from: self.endpoint,
            to: endpoint
        ) else {
            throw CodexUsageError.invalidHTTPResponse
        }
        var request = URLRequest(
            url: endpoint,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: timeoutInterval
        )
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        if let accountID = credentials.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CodexUsageError.invalidHTTPResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw CodexUsageError.reauthenticationRequired
            }
            throw CodexUsageError.httpStatus(httpResponse.statusCode)
        }

        if response.expectedContentLength > Self.maximumResponseSize {
            throw URLError(.dataLengthExceedsMaximum)
        }

        var data = Data()
        if response.expectedContentLength > 0 {
            data.reserveCapacity(min(Int(response.expectedContentLength), Self.maximumResponseSize))
        }
        for try await byte in bytes {
            guard data.count < Self.maximumResponseSize else {
                throw URLError(.dataLengthExceedsMaximum)
            }
            data.append(byte)
        }
        return data
    }

    private func analyticsRequestURL(
        periodStart: Date,
        periodEnd: Date,
        calendar: Calendar
    ) throws -> URL {
        guard var components = URLComponents(
            url: analyticsEndpoint,
            resolvingAgainstBaseURL: false
        ) else {
            throw CodexUsageError.invalidHTTPResponse
        }
        components.queryItems = [
            URLQueryItem(name: "start_date", value: Self.dateText(periodStart, calendar: calendar)),
            URLQueryItem(name: "end_date", value: Self.dateText(periodEnd, calendar: calendar)),
            URLQueryItem(name: "group_by", value: "day"),
            URLQueryItem(name: "workspace_user", value: "true")
        ]
        guard let requestURL = components.url else {
            throw CodexUsageError.invalidHTTPResponse
        }
        return requestURL
    }

    private static func defaultAnalyticsEndpoint(from endpoint: URL) -> URL {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.path = analyticsPath
        components.query = nil
        components.fragment = nil
        return components.url!
    }

    private static func defaultProfileEndpoint(from endpoint: URL) -> URL {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.path = profilePath
        components.query = nil
        components.fragment = nil
        return components.url!
    }

    private static func dateText(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
