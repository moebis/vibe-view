import Foundation

protocol AppServerAccountServing: Sendable {
    func start() async throws
    func readAccount() async throws -> AppServerAccountResponse
    func readRateLimits() async throws -> AppServerRateLimitsResponse
    func readAccountUsage() async throws -> AppServerAccountUsageResponse
    func consumeRateLimitReset(
        idempotencyKey: String,
        creditID: String?
    ) async throws -> AppServerResetOutcome
    func rateLimitUpdates() async -> AsyncStream<AppServerRateLimitSnapshot>
    func stop() async
}

extension CodexAppServerClient: AppServerAccountServing {}

enum CodexAccountServiceError: Error, Equatable, Sendable {
    case signInRequired
    case unavailable
}

protocol CodexAccountServing: Sendable {
    func fetchQuota(fetchedAt: Date) async throws -> UsageSnapshot
    func fetchProfile(fetchedAt: Date) async throws -> CodexProfileStats
    func consumeReset(
        idempotencyKey: String,
        creditID: String?
    ) async throws -> AppServerResetOutcome
    func rateLimitUpdates() async throws -> AsyncStream<AppServerRateLimitSnapshot>
    func stop() async
}

actor CodexAccountService: CodexAccountServing {
    typealias ClientFactory = @Sendable () throws -> any AppServerAccountServing

    private struct Connection: Sendable {
        let id: UUID
        let client: any AppServerAccountServing
        let startup: Task<Void, Error>
    }

    private let makeClient: ClientFactory
    private let retryDelay: Duration
    private var connection: Connection?
    private var retryAfter: ContinuousClock.Instant?
    private var stopped = false

    init(client: any AppServerAccountServing) {
        makeClient = { client }
        retryDelay = .seconds(30)
    }

    init(retryDelay: Duration = .seconds(30), makeClient: @escaping ClientFactory) {
        self.makeClient = makeClient
        self.retryDelay = retryDelay
    }

    static func makeDefault(clientVersion: String) -> CodexAccountService? {
        CodexAccountService {
            let transport = try ProcessAppServerLineTransport(locator: CodexExecutableLocator())
            return CodexAppServerClient(
                transport: transport,
                clientInfo: AppServerClientInfo(
                    name: "codex-watch", title: "Vibe View", version: clientVersion
                )
            )
        }
    }

    func fetchQuota(fetchedAt: Date) async throws -> UsageSnapshot {
        do {
            return try await withAccount { client in
                let response = try await client.readRateLimits()
                return AppServerUsageAdapter.snapshot(from: response, fetchedAt: fetchedAt)
            }
        } catch let error as CodexAccountServiceError {
            throw error
        } catch {
            throw CodexAccountServiceError.unavailable
        }
    }

    func fetchProfile(fetchedAt: Date) async throws -> CodexProfileStats {
        do {
            return try await withAccount { client in
                let response = try await client.readAccountUsage()
                return AppServerUsageAdapter.profile(from: response, fetchedAt: fetchedAt)
            }
        } catch let error as CodexAccountServiceError {
            throw error
        } catch {
            throw CodexAccountServiceError.unavailable
        }
    }

    func consumeReset(idempotencyKey: String, creditID: String?) async throws -> AppServerResetOutcome {
        // Never retry a mutation here. The confirmed caller owns its pending idempotency key.
        try await withAccount { client in
            try await client.consumeRateLimitReset(idempotencyKey: idempotencyKey, creditID: creditID)
        }
    }

    func rateLimitUpdates() async throws -> AsyncStream<AppServerRateLimitSnapshot> {
        try await withAccount { client in await client.rateLimitUpdates() }
    }

    func stop() async {
        stopped = true
        let previous = connection
        connection = nil
        previous?.startup.cancel()
        await previous?.client.stop()
    }

    private func withAccount<Value: Sendable>(
        _ operation: @Sendable (any AppServerAccountServing) async throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        guard !stopped else { throw CodexAccountServiceError.unavailable }
        if connection == nil {
            if let retryAfter, ContinuousClock.now < retryAfter {
                throw CodexAccountServiceError.unavailable
            }
            do {
                let client = try makeClient()
                connection = Connection(
                    id: UUID(), client: client, startup: Task { try await client.start() }
                )
            } catch {
                retryAfter = .now.advanced(by: retryDelay)
                throw CodexAccountServiceError.unavailable
            }
        }
        guard let current = connection else { throw CodexAccountServiceError.unavailable }
        var startupSucceeded = false
        do {
            try await current.startup.value
            startupSucceeded = true
            try Task.checkCancellation()
            guard !stopped, connection?.id == current.id else {
                throw CodexAccountServiceError.unavailable
            }
            // Account reads are local and do not refresh tokens. Revalidate rather than
            // keeping a ChatGPT authorization decision across login/logout changes.
            let account = try await current.client.readAccount()
            guard case .chatGPT = account.account else {
                throw CodexAccountServiceError.signInRequired
            }
            return try await operation(current.client)
        } catch {
            if (!startupSucceeded || Self.requiresReconnect(error)), connection?.id == current.id {
                connection = nil
                retryAfter = .now.advanced(by: retryDelay)
                current.startup.cancel()
                await current.client.stop()
            }
            throw error
        }
    }

    private static func requiresReconnect(_ error: Error) -> Bool {
        if error is CancellationError || error is CodexAccountServiceError { return false }
        if let error = error as? AppServerError {
            switch error {
            case .remoteError, .invalidIdempotencyKey, .invalidResponse:
                // Unsupported optional methods must not break an otherwise healthy connection.
                return false
            default: return true
            }
        }
        return true
    }
}
