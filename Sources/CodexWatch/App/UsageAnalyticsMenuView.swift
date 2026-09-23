import AppKit
import Foundation

enum MenuAnalyticsSection: Int, Equatable, Sendable {
    case days30
    case lifetime

    static let preferenceKey = "codexWatch.menuAnalyticsSection"

    static func load(from defaults: UserDefaults = .standard) -> MenuAnalyticsSection {
        guard defaults.object(forKey: preferenceKey) != nil,
              let section = MenuAnalyticsSection(rawValue: defaults.integer(forKey: preferenceKey))
        else {
            defaults.set(MenuAnalyticsSection.days30.rawValue, forKey: preferenceKey)
            return .days30
        }
        return section
    }

    func persist(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.preferenceKey)
    }
}

struct UsageAnalyticsPresentation: Equatable {
    let title = "Last 30 days"
    let totalTokens: String
    let inputTokens: String
    let cachedInputTokens: String
    let outputTokens: String
    let turns: String
    let chats: String
    let coverage: String
    let dataThrough: String
    let staleValue: String?

    init(projection: UsageAnalyticsProjection, isStale: Bool = false) {
        totalTokens = Self.compact(projection.totalTokens)
        inputTokens = Self.compact(projection.uncachedInputTokens)
        cachedInputTokens = Self.compact(projection.cachedInputTokens)
        outputTokens = Self.compact(projection.outputTokens)
        turns = Self.compact(projection.turns)
        chats = Self.compact(projection.chats)
        coverage = "\(projection.observedDayCount)/\(projection.requestedDayCount) days"
        dataThrough = projection.dataThrough.map(Self.dateFormatter.string(from:)) ?? "Unavailable"
        staleValue = isStale ? "Stale · refresh unavailable" : nil
    }

    private static func compact(_ value: Int64) -> String {
        let units: [(threshold: Double, suffix: String)] = [
            (1_000_000_000, "B"),
            (1_000_000, "M"),
            (1_000, "K")
        ]
        let numeric = Double(value)
        guard let unit = units.first(where: { numeric >= $0.threshold }) else {
            return String(value)
        }
        let scaled = numeric / unit.threshold
        let text = String(format: scaled >= 100 ? "%.0f" : "%.1f", scaled)
            .replacingOccurrences(of: ".0", with: "")
        return text + unit.suffix
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()
}

struct LifetimeAnalyticsPresentation: Equatable {
    let title = "Lifetime"
    let lifetimeTokens: String
    let peakTokens: String
    let longestChat: String
    let currentStreak: String
    let longestStreak: String
    let dataThrough: String
    let staleValue: String?

    init(model: LifetimeDashboardModel, isStale: Bool = false) {
        lifetimeTokens = model.lifetimeTokens
        peakTokens = model.peakTokens
        longestChat = model.longestChat
        currentStreak = model.currentStreak
        longestStreak = model.longestStreak
        dataThrough = model.dataThrough
        staleValue = isStale ? "Stale · refresh unavailable" : nil
    }
}

final class UsageAnalyticsMenuView: MenuContentView {

    private let sectionControl: NSSegmentedControl
    private let usageContent: NSView
    private let lifetimeContent: NSView
    private let onSelect: (MenuAnalyticsSection) -> Void

    convenience init(presentation: UsageAnalyticsPresentation) {
        self.init(
            usagePresentation: presentation,
            lifetimePresentation: nil,
            selectedSection: .days30,
            onSelect: { _ in }
        )
    }

    init(
        usagePresentation: UsageAnalyticsPresentation?,
        lifetimePresentation: LifetimeAnalyticsPresentation?,
        selectedSection: MenuAnalyticsSection,
        onSelect: @escaping (MenuAnalyticsSection) -> Void
    ) {
        sectionControl = NSSegmentedControl(
            labels: ["30 Days", "Lifetime"],
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        sectionControl.segmentStyle = .rounded
        sectionControl.selectedSegment = selectedSection.rawValue
        sectionControl.translatesAutoresizingMaskIntoConstraints = false
        usageContent = Self.usageContent(presentation: usagePresentation)
        lifetimeContent = Self.lifetimeContent(presentation: lifetimePresentation)
        self.onSelect = onSelect

        super.init(spacing: 8, alignment: .centerX)
        for view in [sectionControl, usageContent, lifetimeContent] {
            stack.addArrangedSubview(view)
        }

        sectionControl.target = self
        sectionControl.action = #selector(sectionChanged)
        sectionControl.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        usageContent.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        lifetimeContent.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        show(selectedSection)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func sectionChanged(_ sender: NSSegmentedControl) {
        guard let section = MenuAnalyticsSection(rawValue: sender.selectedSegment) else { return }
        show(section)
        onSelect(section)
    }

    private func show(_ section: MenuAnalyticsSection) {
        usageContent.isHidden = section != .days30
        lifetimeContent.isHidden = section != .lifetime
        resizeToFitContent()
    }

    private static func usageContent(presentation: UsageAnalyticsPresentation?) -> NSView {
        guard let presentation else {
            return unavailableContent(title: "Last 30 days", message: "Usage statistics unavailable")
        }
        return content(
            title: presentation.title,
            staleValue: presentation.staleValue,
            rows: [
                labelRow(title: "Total tokens", value: presentation.totalTokens),
                labelRow(title: "Input tokens", value: presentation.inputTokens),
                labelRow(title: "Cached input", value: presentation.cachedInputTokens),
                labelRow(title: "Output tokens", value: presentation.outputTokens),
                labelRow(title: "Turns", value: presentation.turns),
                labelRow(title: "Chats", value: presentation.chats),
                labelRow(title: "Token coverage", value: presentation.coverage),
                labelRow(title: "Data through", value: presentation.dataThrough)
            ]
        )
    }

    private static func lifetimeContent(presentation: LifetimeAnalyticsPresentation?) -> NSView {
        guard let presentation else {
            return unavailableContent(title: "Lifetime", message: "Lifetime statistics unavailable")
        }
        return content(
            title: presentation.title,
            staleValue: presentation.staleValue,
            rows: [
                labelRow(title: "Lifetime tokens", value: presentation.lifetimeTokens),
                labelRow(title: "Peak daily tokens", value: presentation.peakTokens),
                labelRow(title: "Longest chat", value: presentation.longestChat),
                labelRow(title: "Current streak", value: presentation.currentStreak),
                labelRow(title: "Longest streak", value: presentation.longestStreak),
                labelRow(title: "Data through", value: presentation.dataThrough)
            ]
        )
    }

    private static func unavailableContent(title: String, message: String) -> NSView {
        let messageLabel = NSTextField(labelWithString: message)
        messageLabel.font = .systemFont(ofSize: 12)
        messageLabel.textColor = .secondaryLabelColor
        return content(title: title, staleValue: nil, rows: [messageLabel])
    }

    private static func content(title: String, staleValue: String?, rows: [NSView]) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor

        var views: [NSView] = [titleLabel]
        if let staleValue {
            let staleLabel = NSTextField(labelWithString: staleValue)
            staleLabel.font = .systemFont(ofSize: 11, weight: .medium)
            staleLabel.textColor = .systemOrange
            views.append(staleLabel)
        }
        views.append(contentsOf: rows)
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        for row in rows {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    private static func labelRow(title: String, value: String) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        titleLabel.textColor = .labelColor

        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView(views: [titleLabel, valueLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }
}
