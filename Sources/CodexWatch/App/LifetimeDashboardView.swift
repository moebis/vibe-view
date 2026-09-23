import SwiftUI

struct LifetimeDashboardView: View {
    let model: LifetimeDashboardModel?

    var body: some View {
        if let model {
            ScrollView {
                VStack(spacing: 16) {
                    headlineCards(model)
                    activityHeatmap(model)
                    insightsAndInvocations(model)
                    footer(model)
                }
                .padding(.bottom, 4)
            }
        } else {
            ContentUnavailableView(
                "Lifetime statistics unavailable",
                systemImage: "gauge.with.dots.needle.50percent",
                description: Text("Refresh Vibe View after signing in to ChatGPT.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func headlineCards(_ model: LifetimeDashboardModel) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5),
            spacing: 10
        ) {
            DashboardMetricCard(
                title: "Lifetime tokens",
                value: model.lifetimeTokens,
                detail: "Exact server total"
            )
            DashboardMetricCard(
                title: "Peak tokens",
                value: model.peakTokens,
                detail: "Highest reported day"
            )
            DashboardMetricCard(
                title: "Longest chat",
                value: model.longestChat,
                detail: "Longest running turn"
            )
            DashboardMetricCard(
                title: "Current streak",
                value: model.currentStreak,
                detail: "Consecutive days"
            )
            DashboardMetricCard(
                title: "Longest streak",
                value: model.longestStreak,
                detail: "Personal best"
            )
        }
    }

    private func activityHeatmap(_ model: LifetimeDashboardModel) -> some View {
        DashboardSection(
            title: "Token activity",
            subtitle: model.activityCoverage
        ) {
            if model.activityDays.isEmpty {
                DashboardEmptyRow(text: "No daily token activity reported")
            } else {
                ScrollView(.horizontal) {
                    LazyHGrid(
                        rows: Array(repeating: GridItem(.fixed(12), spacing: 3), count: 7),
                        spacing: 3
                    ) {
                        ForEach(model.activityDays) { day in
                            LifetimeHeatmapCell(
                                day: day,
                                maximumTokens: model.maximumDailyTokens
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .frame(height: 105)
                .accessibilityLabel("Lifetime token activity heatmap")
            }
        }
    }

    private func insightsAndInvocations(_ model: LifetimeDashboardModel) -> some View {
        HStack(alignment: .top, spacing: 16) {
            DashboardSection(
                title: "Activity insights",
                subtitle: "Server-reported"
            ) {
                if model.insights.isEmpty {
                    DashboardEmptyRow(text: "No activity insights reported")
                } else {
                    ForEach(model.insights) { row in
                        HStack(spacing: 12) {
                            Text(row.title).foregroundStyle(.secondary)
                            Spacer()
                            Text(row.value)
                                .font(.body.monospacedDigit())
                                .multilineTextAlignment(.trailing)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)

            DashboardSection(
                title: "Most used Codex tools",
                subtitle: "Plugins and skills"
            ) {
                if model.invocations.isEmpty {
                    DashboardEmptyRow(text: "No plugin or skill activity reported")
                } else {
                    ForEach(model.invocations) { row in
                        HStack(spacing: 9) {
                            Image(systemName: row.kind == .plugin
                                ? "puzzlepiece.extension.fill"
                                : "bolt.fill")
                                .frame(width: 18)
                                .foregroundStyle(.secondary)
                            Text(row.name).lineLimit(1)
                            Spacer()
                            Text(row.usage)
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private func footer(_ model: LifetimeDashboardModel) -> some View {
        HStack {
            Text("Data through \(model.dataThrough)")
            Spacer()
            Text("Fetched \(model.fetchedAt)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 2)
    }
}

private struct LifetimeHeatmapCell: View {
    let day: LifetimeActivityDay
    let maximumTokens: Int64

    var body: some View {
        RoundedRectangle(cornerRadius: 2.75)
            .fill(fillColor)
            .overlay {
                if day.tokens == nil {
                    RoundedRectangle(cornerRadius: 2.75)
                        .stroke(Color.secondary.opacity(0.28), lineWidth: 0.75)
                }
            }
            .frame(width: 12, height: 12)
            .help(LifetimeDashboardModel.accessibilityText(day))
            .accessibilityLabel(LifetimeDashboardModel.accessibilityText(day))
    }

    private var fillColor: Color {
        guard let tokens = day.tokens else { return .clear }
        guard maximumTokens > 0, tokens > 0 else { return Color.cyan.opacity(0.15) }
        let intensity = log1p(Double(tokens)) / log1p(Double(maximumTokens))
        return Color.cyan.opacity(0.2 + 0.8 * intensity)
    }
}
