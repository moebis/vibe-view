import CoreFoundation
import Foundation

actor CodexAppServerClient {
    static let maximumLineBytes = 1_048_576
    private static let integerObjectiveCTypes: Set<String> = [
        "s", "S", "i", "I", "l", "L", "q", "Q"
    ]

    private enum State {
        case idle
        case starting
        case ready
        case terminated
    }

    private struct InitializeParams: Encodable {
        struct Capabilities: Encodable {
            let experimentalApi = false
            let requestAttestation = false
        }

        let clientInfo: AppServerClientInfo
        let capabilities = Capabilities()
    }

    private struct AccountReadParams: Encodable {
        let refreshToken: Bool
    }

    private struct ResetParams: Encodable {
        let idempotencyKey: String
        let creditId: String?
    }

    private struct Request<Params: Encodable>: Encodable {
        let id: Int
        let method: String
        let params: Params
    }

    private struct RequestWithoutParams: Encodable {
        let id: Int
        let method: String
    }

    private struct Notification: Encodable {
        let method: String
    }

    private let transport: any AppServerLineTransport
    private let clientInfo: AppServerClientInfo
    private let requestTimeout: Duration
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var state = State.idle
    private var nextRequestID = 1
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var startupWaiters: [CheckedContinuation<Void, Error>] = []
    private var accountRevision: UInt64 = 0
    private var updateStreams: [UUID: AsyncStream<AppServerAccountUpdate>.Continuation] = [:]
    private var requestTimeoutTasks: [Int: Task<Void, Never>] = [:]

    init(
        transport: any AppServerLineTransport,
        clientInfo: AppServerClientInfo,
        requestTimeout: Duration = .seconds(20)
    ) {
        self.transport = transport
        self.clientInfo = clientInfo
        self.requestTimeout = requestTimeout
        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    func start() async throws {
        switch state {
        case .ready:
            return
        case .terminated:
            throw AppServerError.terminated
        case .starting:
            return try await withCheckedThrowingContinuation { continuation in
                startupWaiters.append(continuation)
            }
        case .idle:
            state = .starting
        }

        do {
            try await transport.start(
                receiveLine: { [weak self] line in
                    await self?.receive(line)
                },
                termination: { [weak self] error in
                    await self?.transportTerminated(error)
                }
            )
            let _: AppServerInitializeResponse = try await request(
                method: "initialize",
                params: InitializeParams(clientInfo: clientInfo),
                allowedWhileStarting: true
            )
            try await transport.send(try encoder.encode(Notification(method: "initialized")))
            guard state != .terminated else {
                throw AppServerError.terminated
            }
            state = .ready
            completeStartup(with: .success(()))
        } catch {
            let sanitized = sanitize(error)
            await terminate(with: sanitized, stopTransport: true)
            throw sanitized
        }
    }

    func readAccount() async throws -> AppServerAccountResponse {
        try requireReady()
        return try await request(
            method: "account/read",
            params: AccountReadParams(refreshToken: false)
        )
    }

    func readRateLimits() async throws -> AppServerRateLimitsResponse {
        try requireReady()
        return try await requestWithoutParams(method: "account/rateLimits/read")
    }

    func readAccountUsage() async throws -> AppServerAccountUsageResponse {
        try requireReady()
        return try await requestWithoutParams(method: "account/usage/read")
    }

    func consumeRateLimitReset(
        idempotencyKey: String,
        creditID: String? = nil
    ) async throws -> AppServerResetOutcome {
        try requireReady()
        guard UUID(uuidString: idempotencyKey) != nil else {
            throw AppServerError.invalidIdempotencyKey
        }
        let response: AppServerResetResponse = try await request(
            method: "account/rateLimitResetCredit/consume",
            params: ResetParams(idempotencyKey: idempotencyKey, creditId: creditID)
        )
        return response.outcome
    }

    func accountUpdates() -> AsyncStream<AppServerAccountUpdate> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(10)) { continuation in
            // terminate() has already finished known streams; do not strand a new one.
            guard state != .terminated else {
                continuation.finish()
                return
            }
            updateStreams[id] = continuation
            if accountRevision != 0 {
                continuation.yield(AppServerAccountUpdate(
                    accountRevision: accountRevision, rateLimits: nil
                ))
            }
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeUpdateStream(id: id)
                }
            }
        }
    }

    func stop() async {
        await terminate(with: .terminated, stopTransport: true)
        // Cleanup remains idempotent even when a prior callback ended the client.
        await transport.stop()
    }

    private func request<Response: Decodable, Params: Encodable>(
        method: String,
        params: Params,
        allowedWhileStarting: Bool = false
    ) async throws -> Response {
        if !allowedWhileStarting {
            try requireReady()
        }
        let id = allocateRequestID()
        let line: Data
        do {
            line = try encoder.encode(Request(id: id, method: method, params: params))
        } catch {
            throw AppServerError.transportFailure
        }
        let responseData = try await sendAndWait(id: id, line: line)
        return try decodeResponse(Response.self, from: responseData)
    }

    private func requestWithoutParams<Response: Decodable>(
        method: String
    ) async throws -> Response {
        try requireReady()
        let id = allocateRequestID()
        let line: Data
        do {
            line = try encoder.encode(RequestWithoutParams(id: id, method: method))
        } catch {
            throw AppServerError.transportFailure
        }
        let responseData = try await sendAndWait(id: id, line: line)
        return try decodeResponse(Response.self, from: responseData)
    }

    private func sendAndWait(id: Int, line: Data) async throws -> Data {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                let requestTimeout = self.requestTimeout
                requestTimeoutTasks[id] = Task { [weak self] in
                    do {
                        try await Task.sleep(for: requestTimeout)
                    } catch {
                        return
                    }
                    await self?.timeoutRequest(id: id)
                }
                Task { [weak self] in
                    await self?.send(line, for: id)
                }
            }
        } onCancel: { [weak self] in
            Task {
                await self?.cancelRequest(id: id)
            }
        }
    }

    private func send(_ line: Data, for id: Int) async {
        guard pending[id] != nil else { return }
        do {
            try await transport.send(line)
        } catch {
            guard pending[id] != nil else { return }
            await terminate(with: .transportFailure, stopTransport: true)
        }
    }

    private func decodeResponse<Response: Decodable>(
        _ type: Response.Type,
        from data: Data
    ) throws -> Response {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw AppServerError.invalidResponse
        }
    }

    private func receive(_ line: Data) async {
        guard line.count <= Self.maximumLineBytes else {
            await terminate(
                with: .lineTooLarge(maxBytes: Self.maximumLineBytes),
                stopTransport: true
            )
            return
        }

        let object: [String: Any]
        do {
            guard let decoded = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                throw AppServerError.malformedMessage
            }
            object = decoded
        } catch {
            await terminate(with: .malformedMessage, stopTransport: true)
            return
        }

        if let method = object["method"] as? String {
            await receiveNotification(method: method, object: object)
            return
        }

        guard let id = integerRequestID(object["id"]) else {
            await terminate(with: .malformedMessage, stopTransport: true)
            return
        }
        guard let continuation = pending.removeValue(forKey: id) else {
            return
        }
        requestTimeoutTasks.removeValue(forKey: id)?.cancel()

        if let error = object["error"] as? [String: Any],
           let code = integerRequestID(error["code"]) {
            continuation.resume(throwing: AppServerError.remoteError(code: code))
            return
        }

        guard let result = object["result"] else {
            continuation.resume(throwing: AppServerError.invalidResponse)
            return
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: result, options: [.fragmentsAllowed])
            continuation.resume(returning: data)
        } catch {
            continuation.resume(throwing: AppServerError.invalidResponse)
        }
    }

    private func receiveNotification(method: String, object: [String: Any]) async {
        guard method == "account/rateLimits/updated" || method == "account/updated" else {
            return
        }
        do {
            guard let params = object["params"] else {
                throw AppServerError.malformedMessage
            }
            let data = try JSONSerialization.data(withJSONObject: params)
            let rateLimits: AppServerRateLimitSnapshot?
            if method == "account/updated" {
                _ = try decoder.decode(AppServerAccountUpdatedNotification.self, from: data)
                accountRevision &+= 1
                rateLimits = nil
            } else {
                rateLimits = try decoder.decode(
                    AppServerRateLimitsUpdatedNotification.self, from: data
                ).rateLimits
            }
            let update = AppServerAccountUpdate(
                accountRevision: accountRevision, rateLimits: rateLimits
            )
            for continuation in updateStreams.values {
                continuation.yield(update)
            }
        } catch {
            await terminate(with: .malformedMessage, stopTransport: true)
        }
    }

    private func transportTerminated(_ error: Error?) async {
        await terminate(
            with: error.map(sanitize) ?? .terminated,
            stopTransport: true
        )
    }

    private func terminate(with error: AppServerError, stopTransport: Bool) async {
        guard state != .terminated else { return }
        state = .terminated

        let requestContinuations = pending.values
        pending.removeAll()
        let timeoutTasks = requestTimeoutTasks.values
        requestTimeoutTasks.removeAll()
        for task in timeoutTasks {
            task.cancel()
        }
        for continuation in requestContinuations {
            continuation.resume(throwing: error)
        }
        completeStartup(with: .failure(error))

        let streamContinuations = updateStreams.values
        updateStreams.removeAll()
        for continuation in streamContinuations {
            continuation.finish()
        }

        if stopTransport {
            await transport.stop()
        }
    }

    private func completeStartup(with result: Result<Void, Error>) {
        let waiters = startupWaiters
        startupWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(with: result)
        }
    }

    private func cancelRequest(id: Int) {
        requestTimeoutTasks.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }

    private func timeoutRequest(id: Int) {
        requestTimeoutTasks.removeValue(forKey: id)
        pending.removeValue(forKey: id)?.resume(throwing: AppServerError.timedOut)
    }

    private func removeUpdateStream(id: UUID) {
        updateStreams.removeValue(forKey: id)
    }

    private func requireReady() throws {
        switch state {
        case .ready:
            return
        case .terminated:
            throw AppServerError.terminated
        case .idle, .starting:
            throw AppServerError.notStarted
        }
    }

    private func allocateRequestID() -> Int {
        let id = nextRequestID
        nextRequestID += 1
        return id
    }

    private func integerRequestID(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        guard Self.integerObjectiveCTypes.contains(String(cString: number.objCType)) else {
            return nil
        }
        let double = number.doubleValue
        guard double.isFinite,
              double.rounded(.towardZero) == double,
              double >= Double(Int.min),
              double <= Double(Int.max) else {
            return nil
        }
        return number.intValue
    }

    private func sanitize(_ error: Error) -> AppServerError {
        if let appServerError = error as? AppServerError {
            return appServerError
        }
        if error is CancellationError {
            return .terminated
        }
        return .transportFailure
    }
}
