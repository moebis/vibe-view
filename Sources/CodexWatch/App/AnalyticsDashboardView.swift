import Charts
import SwiftUI

struct AnalyticsDashboardView: View {
    @ObservedObject var model: AnalyticsDashboardModel
    let onRefresh: () -> Void
    let onExport: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            header

            Picker("Dashboard", selection: $model.section) {
                ForEach(AnalyticsDashboardSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Analytics section")
            .frame(maxWidth: 300)

            switch model.section {
            case .usage:
                Picker("Range", selection: $model.range) {
                    ForEach(AnalyticsRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Analytics range")

                usageContent
            case .lifetime:
                LifetimeDashboardView(model: model.lifetime)
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vibe View Analytics")
                        .font(.title2.weight(.semibold))
                    Text("Codex usage reported by ChatGPT")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") {
                    onRefresh()
                }
                .accessibilityHint("Refresh quota and analytics from ChatGPT")
                if model.section == .usage {
                    Button("Export CSV…", systemImage: "square.and.arrow.up") {
                        onExport()
                    }
                    .disabled(model.projection == nil)
                    .accessibilityHint("Choose where to save the selected analytics range")
                }
            }

            HStack(spacing: 10) {
                if let status = model.selectedRefreshStatus {
                    Text("\(status.label) \(Self.dateTimeText(status.fetchedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selectedSurfaceIsStale {
                    Label("Stale data", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.orange.opacity(0.12), in: Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private var usageContent: some View {
        if let projection = model.projection {
            ScrollView {
                VStack(spacing: 16) {
                    summaryCards(projection)
                    tokenChart(projection)
                    if let layout = model.heatmapLayout {
                        activityHeatmap(projection, layout: layout)
                    }
                    modelActivityTable(projection)
                    clientTokenTable(projection)
                    footer(projection)
                }
                .padding(.bottom, 4)
            }
        } else {
            ContentUnavailableView(
                "Analytics unavailable",
                systemImage: "chart.xyaxis.line",
                description: Text("Refresh Vibe View after signing in to ChatGPT.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var selectedSurfaceIsStale: Bool {
        switch model.section {
        case .usage: model.isStale
        case .lifetime: model.profileIsStale
        }
    }

    private func summaryCards(_ projection: UsageAnalyticsProjection) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
            spacing: 10
        ) {
            DashboardMetricCard(
                title: "Total tokens",
                value: Self.compact(projection.totalTokens),
                detail: comparisonText(projection.comparison)
            )
            DashboardMetricCard(
                title: "Input tokens",
                value: Self.compact(projection.uncachedInputTokens),
                detail: "Uncached"
            )
            DashboardMetricCard(
                title: "Cached input",
                value: Self.compact(projection.cachedInputTokens),
                detail: "Server-reported"
            )
            DashboardMetricCard(
                title: "Output tokens",
                value: Self.compact(projection.outputTokens),
                detail: "Generated"
            )
            DashboardMetricCard(
                title: "Turns",
                value: Self.compact(projection.turns),
                detail: "Codex activity"
            )
            DashboardMetricCard(
                title: "Chats",
                value: Self.compact(projection.chats),
                detail: "Active threads"
            )
            DashboardMetricCard(
                title: "Token coverage",
                value: "\(projection.observedDayCount)/\(projection.requestedDayCount)",
                detail: "Observed days"
            )
            DashboardMetricCard(
                title: "Missing",
                value: String(projection.missingDayCount),
                detail: projection.activityOnlyDayCount == 0
                    ? "Shown as gaps"
                    : "\(projection.activityOnlyDayCount) activity-only"
            )
        }
    }

    private func tokenChart(_ projection: UsageAnalyticsProjection) -> some View {
        DashboardSection(title: "Daily token usage", subtitle: "Missing dates remain gaps") {
            Chart {
                ForEach(projection.days) { day in
                    if case let .observed(totals) = day.state {
                        BarMark(
                            x: .value("Date", day.date, unit: .day),
                            y: .value("Tokens", totals.totalTokens)
                        )
                        .foregroundStyle(Color.accentColor.gradient)
                        .accessibilityLabel(UsageHeatmapPresentation.accessibilityText(day))
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let tokens = value.as(Int64.self) {
                            Text(Self.compact(tokens))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: projection.range == .days365 ? 12 : 7))
            }
            .frame(height: 190)
            .accessibilityLabel("Daily token usage chart")
        }
    }

    private func activityHeatmap(
        _ projection: UsageAnalyticsProjection,
        layout: UsageHeatmapLayout
    ) -> some View {
        let maximum = projection.days.compactMap { day -> Int64? in
            if case let .observed(totals) = day.state { return totals.totalTokens }
            return nil
        }.max() ?? 0

        return DashboardSection(
            title: "Token activity",
            subtitle: "Filled observed · muted activity-only · outlined missing"
        ) {
            ScrollView(.horizontal) {
                LazyHGrid(
                    rows: Array(repeating: GridItem(.fixed(11), spacing: 3), count: 7),
                    spacing: 3
                ) {
                    ForEach(layout.slots) { slot in
                        if let day = slot.day {
                            UsageHeatmapCell(day: day, maximumTokens: maximum)
                        } else {
                            Color.clear
                                .frame(width: 11, height: 11)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .frame(height: 101)
            .accessibilityLabel("Token activity heatmap")
        }
    }

    private func modelActivityTable(_ projection: UsageAnalyticsProjection) -> some View {
        let layout = DashboardTableLayout.modelActivity
        return DashboardSection(
            title: "Model activity",
            subtitle: projection.modelBreakdownIsPartial
                ? "Partial server detail · activity, not token counts"
                : "Turns, chats, credits, and share · not token counts"
        ) {
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 10) {
                    DashboardTableHeader(layout: layout)
                    if projection.models.isEmpty {
                        DashboardEmptyRow(text: "No model activity reported")
                    } else {
                        ForEach(projection.models) { row in
                            HStack(spacing: layout.spacing) {
                                Text(row.model)
                                    .frame(width: layout.columns[0].width, alignment: .leading)
                                Text(Self.compact(row.turns))
                                    .frame(width: layout.columns[1].width, alignment: .trailing)
                                Text(Self.compact(row.chats))
                                    .frame(width: layout.columns[2].width, alignment: .trailing)
                                Text(NSDecimalNumber(decimal: row.credits).stringValue)
                                    .frame(width: layout.columns[3].width, alignment: .trailing)
                                Text(Self.percent(row.turnShare))
                                    .frame(width: layout.columns[4].width, alignment: .trailing)
                            }
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .frame(minWidth: layout.contentWidth, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func clientTokenTable(_ projection: UsageAnalyticsProjection) -> some View {
        let layout = DashboardTableLayout.clientTokens
        return DashboardSection(
            title: "Client tokens",
            subtitle: projection.clientBreakdownIsPartial
                ? "Partial server detail"
                : "Token totals by Codex client"
        ) {
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 10) {
                    DashboardTableHeader(layout: layout)
                    if projection.clients.isEmpty {
                        DashboardEmptyRow(text: "No client token detail reported")
                    } else {
                        ForEach(projection.clients) { row in
                            HStack(spacing: layout.spacing) {
                                Text(row.clientID)
                                    .frame(width: layout.columns[0].width, alignment: .leading)
                                Text(Self.compact(row.totalTokens))
                                    .frame(width: layout.columns[1].width, alignment: .trailing)
                                Text(Self.compact(row.uncachedInputTokens))
                                    .frame(width: layout.columns[2].width, alignment: .trailing)
                                Text(Self.compact(row.cachedInputTokens))
                                    .frame(width: layout.columns[3].width, alignment: .trailing)
                                Text(Self.compact(row.outputTokens))
                                    .frame(width: layout.columns[4].width, alignment: .trailing)
                                Text(Self.compact(row.turns))
                                    .frame(width: layout.columns[5].width, alignment: .trailing)
                                Text(Self.compact(row.chats))
                                    .frame(width: layout.columns[6].width, alignment: .trailing)
                            }
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .frame(minWidth: layout.contentWidth, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func footer(_ projection: UsageAnalyticsProjection) -> some View {
        HStack {
            Text("Data through \(projection.dataThrough.map(Self.dateText) ?? "Unavailable")")
            Spacer()
            Text("Fetched \(Self.dateTimeText(projection.fetchedAt))")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 2)
    }

    private func comparisonText(_ comparison: UsageComparison?) -> String {
        guard case let .percent(value) = comparison else { return "Comparison unavailable" }
        let sign = value > 0 ? "+" : ""
        return "\(sign)\(Self.percent(value)) vs prior"
    }

    static func compact(_ value: Int64) -> String {
        let units: [(Double, String)] = [(1_000_000_000, "B"), (1_000_000, "M"), (1_000, "K")]
        let numeric = Double(value)
        guard let unit = units.first(where: { abs(numeric) >= $0.0 }) else { return String(value) }
        var text = String(
            format: abs(numeric / unit.0) >= 100 ? "%.0f" : "%.1f",
            locale: Locale(identifier: "en_US_POSIX"),
            numeric / unit.0
        )
        if text.hasSuffix(".0") { text.removeLast(2) }
        return text + unit.1
    }

    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "Unavailable" }
        var text = String(
            format: "%.1f",
            locale: Locale(identifier: "en_US_POSIX"),
            value * 100
        )
        if text.hasSuffix(".0") { text.removeLast(2) }
        return "\(text)%"
    }

    static func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.abbreviated).day().locale(Locale(identifier: "en_US_POSIX")))
    }

    static func dateTimeText(_ date: Date) -> String {
        date.formatted(
            .dateTime.year().month(.abbreviated).day().hour().minute().locale(Locale(identifier: "en_US_POSIX"))
        )
    }
}

struct DashboardMetricCard: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit().weight(.semibold))
            Text(detail).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
    }
}

struct DashboardSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            content
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }
}

private struct UsageHeatmapCell: View {
    let day: UsageDayCell
    let maximumTokens: Int64

    var body: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(fillColor)
            .overlay {
                if case .missing = day.state {
                    RoundedRectangle(cornerRadius: 2.5)
                        .stroke(Color.secondary.opacity(0.45), lineWidth: 1)
                }
            }
            .frame(width: 11, height: 11)
            .help(UsageHeatmapPresentation.accessibilityText(day))
            .accessibilityLabel(UsageHeatmapPresentation.accessibilityText(day))
    }

    private var fillColor: Color {
        switch day.state {
        case .missing:
            return .clear
        case .activityOnly:
            return Color.secondary.opacity(0.2)
        case let .observed(totals):
            guard maximumTokens > 0, totals.totalTokens > 0 else {
                return Color.accentColor.opacity(0.12)
            }
            let intensity = log1p(Double(totals.totalTokens)) / log1p(Double(maximumTokens))
            return Color.accentColor.opacity(0.2 + 0.75 * intensity)
        }
    }
}

private struct DashboardTableHeader: View {
    let layout: DashboardTableLayout

    var body: some View {
        HStack(spacing: layout.spacing) {
            ForEach(Array(layout.columns.enumerated()), id: \.offset) { index, column in
                Text(column.title)
                    .frame(width: column.width, alignment: index == 0 ? .leading : .trailing)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

struct DashboardEmptyRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }
}
