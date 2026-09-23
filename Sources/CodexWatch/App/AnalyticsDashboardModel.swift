import Combine
import Foundation

enum AnalyticsDashboardErrorState: Equatable, Sendable {
    case analyticsUnavailable
    case profileUnavailable

    var message: String {
        switch self {
        case .analyticsUnavailable:
            "Analytics refresh unavailable"
        case .profileUnavailable:
            "Lifetime refresh unavailable"
        }
    }
}

enum AnalyticsDashboardSection: String, CaseIterable, Identifiable, Sendable {
    case usage
    case lifetime

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct AnalyticsDashboardRefreshStatus: Equatable, Sendable {
    let fetchedAt: Date
    let isStale: Bool

    var label: String { isStale ? "Last successful refresh" : "Fetched" }
}

@MainActor
final class AnalyticsDashboardModel: ObservableObject {
    enum ModelError: Error, Equatable {
        case dataUnavailable
    }

    static let rangePreferenceKey = "codexWatch.analyticsRange"
    static let sectionPreferenceKey = "codexWatch.analyticsSection"

    @Published var section: AnalyticsDashboardSection {
        didSet {
            guard section != oldValue else { return }
            defaults.set(section.rawValue, forKey: Self.sectionPreferenceKey)
        }
    }

    @Published var range: AnalyticsRange {
        didSet {
            guard range != oldValue else { return }
            defaults.set(range.rawValue, forKey: Self.rangePreferenceKey)
            reproject()
        }
    }
    @Published private(set) var projection: UsageAnalyticsProjection?
    @Published private(set) var isStale = false
    @Published private(set) var errorState: AnalyticsDashboardErrorState?
    @Published private(set) var lifetime: LifetimeDashboardModel?
    @Published private(set) var profileIsStale = false
    @Published private(set) var profileErrorState: AnalyticsDashboardErrorState?

    private let defaults: UserDefaults
    private let calendar: Calendar
    private var dataset: UsageAnalyticsDataset?
    private var projectionCache = UsageAnalyticsProjectionCache()
    private var profileStats: CodexProfileStats?
    private var referenceDate = Date.now

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
        if let rawSection = defaults.string(forKey: Self.sectionPreferenceKey),
           let restoredSection = AnalyticsDashboardSection(rawValue: rawSection) {
            section = restoredSection
        } else {
            section = .usage
            defaults.set(AnalyticsDashboardSection.usage.rawValue, forKey: Self.sectionPreferenceKey)
        }
        let stored = defaults.integer(forKey: Self.rangePreferenceKey)
        if defaults.object(forKey: Self.rangePreferenceKey) != nil,
           let restored = AnalyticsRange(rawValue: stored) {
            range = restored
        } else {
            range = .days30
            defaults.set(AnalyticsRange.days30.rawValue, forKey: Self.rangePreferenceKey)
        }
    }

    func update(
        dataset newDataset: UsageAnalyticsDataset?,
        error: AnalyticsDashboardErrorState?,
        profileStats newProfileStats: CodexProfileStats? = nil,
        profileError: AnalyticsDashboardErrorState? = nil,
        now: Date
    ) {
        referenceDate = now
        if let newDataset {
            dataset = newDataset
            if isStale != (error != nil) { isStale = error != nil }
        } else if error != nil, dataset != nil, !isStale {
            isStale = true
        }
        if errorState != error { errorState = error }
        if let newProfileStats {
            if profileStats != newProfileStats {
                profileStats = newProfileStats
                lifetime = LifetimeDashboardModel(profile: newProfileStats)
            }
            if profileIsStale != (profileError != nil) { profileIsStale = profileError != nil }
        } else if profileError != nil, profileStats != nil, !profileIsStale {
            profileIsStale = true
        }
        if profileErrorState != profileError { profileErrorState = profileError }
        reproject()
    }

    func csvString() throws -> String {
        guard let projection else { throw ModelError.dataUnavailable }
        return try UsageAnalyticsCSVExporter.string(projection: projection, calendar: calendar)
    }

    var suggestedCSVFilename: String {
        UsageAnalyticsCSVExporter.suggestedFilename(
            range: range,
            dataThrough: projection?.dataThrough,
            calendar: calendar
        )
    }

    var heatmapLayout: UsageHeatmapLayout? {
        projection.map { UsageHeatmapLayout(days: $0.days, calendar: calendar) }
    }

    var selectedRefreshStatus: AnalyticsDashboardRefreshStatus? {
        let fetchedAt: Date?
        let stale: Bool
        switch section {
        case .usage:
            fetchedAt = projection?.fetchedAt
            stale = isStale
        case .lifetime:
            fetchedAt = profileStats?.fetchedAt
            stale = profileIsStale
        }
        guard let fetchedAt else { return nil }
        return AnalyticsDashboardRefreshStatus(
            fetchedAt: fetchedAt,
            isStale: stale
        )
    }

    private func reproject() {
        let nextProjection = dataset.flatMap {
            projectionCache.projection(
                dataset: $0,
                range: range,
                referenceDate: referenceDate,
                calendar: calendar
            )
        }
        if projection != nextProjection { projection = nextProjection }
    }
}
