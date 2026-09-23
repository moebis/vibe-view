import Foundation

/// Independent refresh ownership keeps Claude latency/failure out of Codex's path.
@MainActor
final class ClaudeQuotaController {
    static let preferenceKey = "vibeView.claudeQuotaEnabled"
    typealias Fetch = @Sendable (Bool) async throws -> ClaudeUsageSnapshot

    private(set) var isEnabled: Bool
    private(set) var snapshot: ClaudeUsageSnapshot?
    private(set) var error: ClaudeConnectionError?
    private(set) var isRefreshing = false
    var onChange: (() -> Void)?
    private let defaults: UserDefaults
    private let fetch: Fetch
    private var task: Task<Void, Never>?
    private var generation = 0
    private var lastAttempt: Date?
    private var retryAfter: Date?
    private var stopped = false

    init(defaults: UserDefaults = .standard, fetch: @escaping Fetch) {
        self.defaults = defaults
        self.fetch = fetch
        isEnabled = defaults.bool(forKey: Self.preferenceKey)
    }

    func connect() {
        guard !stopped else { return }
        isEnabled = true
        defaults.set(true, forKey: Self.preferenceKey)
        // This explicit action is the only path allowed to show Keychain UI.
        refresh(force: true, allowInteraction: true)
    }

    func disconnect() {
        isEnabled = false
        defaults.set(false, forKey: Self.preferenceKey)
        cancel()
        lastAttempt = nil
        retryAfter = nil
        snapshot = nil
        error = nil
        onChange?()
    }

    func refresh(force: Bool = false, allowInteraction: Bool = false, now: Date = .now) {
        guard isEnabled, !stopped, task == nil,
              retryAfter.map({ now >= $0 }) ?? true,
              force || lastAttempt.map({ now.timeIntervalSince($0) >= 60 }) ?? true else { return }
        lastAttempt = now
        generation += 1
        let current = generation
        isRefreshing = true
        onChange?()
        let fetch = fetch
        task = Task { [weak self] in
            let result: Result<ClaudeUsageSnapshot, ClaudeConnectionError>
            do {
                result = .success(try await fetch(allowInteraction))
            } catch {
                result = .failure(error as? ClaudeConnectionError ?? .unavailable)
            }
            guard let self, !Task.isCancelled, !self.stopped,
                  current == self.generation, self.isEnabled else { return }
            self.task = nil
            self.isRefreshing = false
            switch result {
            case .success(let value):
                self.snapshot = value
                self.error = nil
                self.retryAfter = nil
            case .failure(let error):
                // Do not retain another account's quota after logout/auth changes.
                self.snapshot = nil
                self.error = error
                if case .rateLimited(let delay) = error {
                    self.retryAfter = Date.now.addingTimeInterval(delay)
                }
            }
            self.onChange?()
        }
    }

    func stop() {
        stopped = true
        cancel()
    }

    private func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        isRefreshing = false
    }
}
