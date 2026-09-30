import Foundation

@MainActor
final class RefreshCoordinator {
    typealias Now = @MainActor () -> Date
    typealias Sleep = @Sendable (TimeInterval) async throws -> Void
    typealias Fetch = @MainActor @Sendable (RefreshRequest) async -> RefreshResult
    typealias Publish = @MainActor @Sendable (RefreshResult) -> Void

    private let now: Now
    private let sleep: Sleep
    private let fetch: Fetch
    private let publish: Publish
    private let lowPowerMode: @MainActor () -> Bool
    private let thermalConstrained: @MainActor () -> Bool
    private var activeTask: Task<Void, Never>?
    private var scheduledTask: Task<Void, Never>?
    private var generation = 0
    private var stopped = false
    private var lastAnalyticsAttempt: Date?
    private var lastSuccessfulQuotaAt: Date?
    private(set) var lastMenuOpenAt: Date?
    private(set) var frequency: RefreshFrequency

    init(
        frequency: RefreshFrequency,
        now: @escaping Now = { .now },
        sleep: @escaping Sleep = { interval in
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        },
        lowPowerMode: @escaping @MainActor () -> Bool = {
            ProcessInfo.processInfo.isLowPowerModeEnabled
        },
        thermalConstrained: @escaping @MainActor () -> Bool = {
            switch ProcessInfo.processInfo.thermalState {
            case .serious, .critical: true
            default: false
            }
        },
        fetch: @escaping Fetch,
        publish: @escaping Publish
    ) {
        self.frequency = frequency
        self.now = now
        self.sleep = sleep
        self.lowPowerMode = lowPowerMode
        self.thermalConstrained = thermalConstrained
        self.fetch = fetch
        self.publish = publish
    }

    func trigger(_ trigger: RefreshTrigger) {
        guard !stopped else { return }
        let currentTime = now()
        if trigger == .menuOpened {
            lastMenuOpenAt = currentTime
            if let lastSuccessfulQuotaAt,
               currentTime.timeIntervalSince(lastSuccessfulQuotaAt) <= RefreshPolicy.menuOpenFreshness {
                if frequency == .adaptive {
                    scheduledTask?.cancel()
                    scheduledTask = nil
                    if activeTask == nil {
                        scheduleNext(after: generation)
                    }
                }
                return
            }
        }

        if activeTask != nil, !trigger.replacesActiveWork {
            return
        }

        scheduledTask?.cancel()
        scheduledTask = nil
        if trigger.replacesActiveWork {
            activeTask?.cancel()
        }

        generation += 1
        let requestGeneration = generation
        let includeAnalytics = RefreshPolicy.shouldIncludeAnalytics(
            trigger: trigger,
            lastAttempt: lastAnalyticsAttempt,
            now: currentTime
        )
        if includeAnalytics {
            lastAnalyticsAttempt = currentTime
        }
        let request = RefreshRequest(
            generation: requestGeneration,
            trigger: trigger,
            includeAnalytics: includeAnalytics,
            requestedAt: currentTime
        )

        activeTask = Task { [weak self] in
            guard let self, !Task.isCancelled, !self.stopped,
                  requestGeneration == self.generation else { return }
            let result = await self.fetch(request)
            self.finish(result: result, generation: requestGeneration)
        }
    }

    func setFrequency(_ frequency: RefreshFrequency) {
        guard !stopped else { return }
        self.frequency = frequency
        scheduledTask?.cancel()
        scheduledTask = nil
        if activeTask == nil {
            scheduleNext(after: generation)
        }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        generation += 1
        scheduledTask?.cancel()
        scheduledTask = nil
        activeTask?.cancel()
        activeTask = nil
    }

    func waitUntilIdleForTesting() async {
        while activeTask != nil {
            await Task.yield()
        }
    }

    func publishPartial(_ result: RefreshResult, generation requestGeneration: Int) {
        guard !stopped, activeTask != nil, requestGeneration == generation else { return }
        if let quotaFetchedAt = result.quotaFetchedAt {
            lastSuccessfulQuotaAt = quotaFetchedAt
        }
        publish(result)
    }

    private func finish(result: RefreshResult, generation requestGeneration: Int) {
        guard !stopped, requestGeneration == generation else { return }
        activeTask = nil
        if let quotaFetchedAt = result.quotaFetchedAt {
            lastSuccessfulQuotaAt = quotaFetchedAt
        }
        publish(result)
        scheduleNext(after: requestGeneration)
    }

    private func scheduleNext(after requestGeneration: Int) {
        guard !stopped, requestGeneration == generation else { return }
        let delay: TimeInterval
        switch frequency {
        case .manual:
            return
        case .adaptive:
            delay = AdaptiveRefreshPolicy.nextDelay(
                now: now(),
                lastMenuOpenAt: lastMenuOpenAt,
                lowPowerMode: lowPowerMode(),
                thermalConstrained: thermalConstrained()
            )
        default:
            delay = TimeInterval(frequency.rawValue)
        }

        let sleep = self.sleep
        scheduledTask = Task { [weak self] in
            do {
                try await sleep(delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.scheduledTask = nil
            self?.trigger(.automatic)
        }
    }
}
