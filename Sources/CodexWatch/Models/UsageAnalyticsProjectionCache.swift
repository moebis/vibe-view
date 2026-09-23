import Foundation

/// One in-memory projection per surface; quota-only refreshes reuse the same dataset.
struct UsageAnalyticsProjectionCache {
    private struct Key: Equatable {
        let dataset: UsageAnalyticsDataset
        let range: AnalyticsRange
        let referenceDay: Date
        let calendar: Calendar
    }

    private var key: Key?
    private var value: UsageAnalyticsProjection?

    mutating func projection(
        dataset: UsageAnalyticsDataset,
        range: AnalyticsRange,
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> UsageAnalyticsProjection? {
        let nextKey = Key(
            dataset: dataset,
            range: range,
            referenceDay: calendar.startOfDay(for: referenceDate),
            calendar: calendar
        )
        if key != nextKey {
            value = UsageAnalyticsProjection.make(
                dataset: dataset,
                range: range,
                referenceDate: referenceDate,
                calendar: calendar
            )
            key = nextKey
        }
        return value
    }
}
