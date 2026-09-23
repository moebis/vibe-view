import AppKit
import Foundation

@MainActor
enum MenuBarButtonStyle {
    static let fontSize: CGFloat = 12
    static let imageSize = NSSize(width: 16, height: 16)

    static func apply(to button: NSButton) {
        button.image = makeStatusImage()
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.alignment = .center
        button.font = .monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
        button.toolTip = "Codex Watch weekly quota"
    }

    static func applyRefreshState(to button: NSButton, isStale: Bool) {
        button.contentTintColor = nil
        button.alphaValue = isStale ? 0.62 : 1
    }

    static func makeStatusImage() -> NSImage {
        let description = "Codex Watch usage statistics"
        let symbol = NSImage(
            systemSymbolName: "chart.pie.fill",
            accessibilityDescription: description
        )
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let image = symbol?.withSymbolConfiguration(configuration) ?? symbol ?? NSImage(size: imageSize)
        image.size = imageSize
        image.isTemplate = true
        image.accessibilityDescription = description
        return image
    }
}

enum MenuBarErrorState: Equatable, Sendable {
    case signInRequired
    case quotaUnavailable
}

enum MenuBarText {
    static func statusTitle(snapshot: UsageSnapshot?) -> String {
        guard let remaining = snapshot?.weeklyWindow?.remainingPercent else { return "—" }
        return "\(Int(remaining.rounded()))%"
    }

    static func summary(snapshot: UsageSnapshot?, error: MenuBarErrorState?) -> String {
        if let weekly = snapshot?.weeklyWindow {
            return "Weekly remaining: \(Int(weekly.remainingPercent.rounded()))%"
        }
        switch error {
        case .signInRequired:
            return "Sign in to Codex again"
        case .quotaUnavailable:
            return "Quota unavailable"
        case nil:
            return "Loading quota…"
        }
    }

    static func resetLine(snapshot: UsageSnapshot?) -> String? {
        guard let resetAt = snapshot?.weeklyWindow?.resetAt else { return nil }
        return resetLine(resetAt: resetAt)
    }

    static func resetLine(resetAt: Date) -> String {
        "Resets: \(resetFormatter.string(from: resetAt))"
    }

    static func resetCreditExpiryLine(snapshot: UsageSnapshot?) -> String? {
        guard let count = snapshot?.availableResetCredits,
              count > 0,
              let expiresAt = snapshot?.nextResetCreditExpiry else { return nil }
        let prefix = count == 1 ? "Expires" : "Next expires"
        return "\(prefix): \(resetFormatter.string(from: expiresAt))"
    }

    static func projectedExhaustionLine(_ projectedAt: Date) -> String {
        "Exhaustion: \(resetFormatter.string(from: projectedAt))"
    }

    static func updatedLine(lastUpdated: Date, now: Date) -> String {
        let elapsed = max(0, now.timeIntervalSince(lastUpdated))
        if elapsed < 60 { return "Updated just now" }
        if elapsed < 60 * 60 { return "Updated \(Int(elapsed / 60))m ago" }
        if elapsed < 24 * 60 * 60 { return "Updated \(Int(elapsed / 3_600))h ago" }
        return "Updated \(Int(elapsed / 86_400))d ago"
    }

    static func durationText(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int(interval / 60))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes / 60) % 24
        let minutes = totalMinutes % 60

        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "MMM d, yyyy 'at' HH:mm"
        return formatter
    }()
}

struct QuotaWindowPresentation: Equatable, Identifiable {
    let id: String
    let title: String
    let quotaValue: String
    let quotaProgress: Double
    let resetValue: String
    let resetDetail: String?
    let resetProgress: Double?
    let paceText: String?
    let projectedExhaustionAt: Date?
    let projectedExhaustionText: String?

    init(id: String, title: String, window: UsageWindow, now: Date) {
        self.id = id
        self.title = title
        quotaValue = "\(Int(window.remainingPercent.rounded()))%"
        quotaProgress = Self.clamp(window.remainingPercent / 100)

        if let resetAt = window.resetAt,
           let duration = window.durationSeconds,
           duration.isFinite,
           duration > 0 {
            let remaining = max(0, resetAt.timeIntervalSince(now))
            resetValue = MenuBarText.durationText(remaining)
            resetDetail = MenuBarText.resetLine(resetAt: resetAt)
            resetProgress = Self.clamp(remaining / duration)
        } else {
            resetValue = "Unavailable"
            resetDetail = window.resetAt.map(MenuBarText.resetLine(resetAt:))
            resetProgress = nil
        }

        if let pace = UsagePace.calculate(window: window, now: now) {
            if abs(pace.deltaPercent) <= 2 {
                paceText = "On pace"
            } else if pace.deltaPercent > 0 {
                paceText = "\(Int(abs(pace.deltaPercent).rounded()))% in deficit"
            } else {
                paceText = "\(Int(abs(pace.deltaPercent).rounded()))% in reserve"
            }
            projectedExhaustionAt = pace.projectedExhaustion
            projectedExhaustionText = pace.projectedExhaustion.map(
                MenuBarText.projectedExhaustionLine
            )
        } else {
            paceText = nil
            projectedExhaustionAt = nil
            projectedExhaustionText = nil
        }
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }
}

struct QuotaProgressPresentation: Equatable {
    let planValue: String
    let creditsRemainingValue: String?
    let quotaValue: String
    let quotaProgress: Double?
    let resetValue: String
    let resetDetail: String?
    let resetProgress: Double?
    let resetCreditsValue: String?
    let resetCreditsDetail: String?
    let resetCreditsProgress: Double?
    let quotaWindows: [QuotaWindowPresentation]
    let rateLimitReachedValue: String?
    let statusDetail: String?
    let updatedValue: String?

    init(snapshot: UsageSnapshot?, error: MenuBarErrorState?, now: Date) {
        planValue = snapshot?.plan?.displayName ?? "Unavailable"
        creditsRemainingValue = snapshot?.creditsRemaining?.displayValue
        resetCreditsValue = snapshot?.availableResetCredits.map { "\($0) available" }
        resetCreditsDetail = MenuBarText.resetCreditExpiryLine(snapshot: snapshot)
        resetCreditsProgress = Self.resetCreditProgress(snapshot: snapshot, now: now)
        quotaWindows = Self.makeQuotaWindows(snapshot: snapshot, now: now)
        rateLimitReachedValue = snapshot?.rateLimitReachedReason?.displayName
        statusDetail = error.map { MenuBarText.summary(snapshot: nil, error: $0) }
        updatedValue = error.flatMap { _ in
            guard snapshot?.weeklyWindow != nil else { return nil }
            return snapshot.map { MenuBarText.updatedLine(lastUpdated: $0.fetchedAt, now: now) }
        }

        guard let weekly = snapshot?.weeklyWindow else {
            switch error {
            case .signInRequired:
                quotaValue = "Sign in required"
            case .quotaUnavailable:
                quotaValue = "Unavailable"
            case nil:
                quotaValue = "Loading…"
            }
            quotaProgress = nil
            resetValue = "—"
            resetDetail = nil
            resetProgress = nil
            return
        }

        let weeklyPresentation = QuotaWindowPresentation(
            id: weekly.id,
            title: "Weekly",
            window: weekly,
            now: now
        )
        quotaValue = weeklyPresentation.quotaValue
        quotaProgress = weeklyPresentation.quotaProgress
        resetValue = weeklyPresentation.resetValue
        resetDetail = weeklyPresentation.resetDetail
        resetProgress = weeklyPresentation.resetProgress
    }

    private static func makeQuotaWindows(
        snapshot: UsageSnapshot?,
        now: Date
    ) -> [QuotaWindowPresentation] {
        guard let snapshot else { return [] }
        var result: [QuotaWindowPresentation] = []
        var usedIDs = Set<String>()

        func append(id: String, title: String, window: UsageWindow) {
            guard usedIDs.insert(id).inserted else { return }
            result.append(QuotaWindowPresentation(id: id, title: title, window: window, now: now))
        }

        if let weekly = snapshot.weeklyWindow {
            append(id: weekly.id, title: "Weekly", window: weekly)
        }
        for window in snapshot.windows where window.id != snapshot.weeklyWindow?.id {
            append(id: window.id, title: title(for: window.kind), window: window)
        }
        for named in snapshot.additionalWindows + snapshot.codeReviewWindows
            where !isSpark(named) {
            append(id: named.id, title: named.title, window: named.window)
        }
        return result
    }

    private static func isSpark(_ named: NamedUsageWindow) -> Bool {
        // Retired Spark buckets may still appear in compatibility responses.
        // Never relabel them as a current model or use them as base quota.
        [named.id, named.title].contains { value in
            let words = value.lowercased().split { !$0.isLetter && !$0.isNumber }
            return zip(words, words.dropFirst()).contains { $0 == "codex" && $1 == "spark" }
        }
    }

    private static func title(for kind: UsageWindowKind) -> String {
        switch kind {
        case let .rolling(hours): "\(hours)-hour"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .custom: "Quota"
        }
    }

    private static func resetCreditProgress(snapshot: UsageSnapshot?, now: Date) -> Double? {
        guard let count = snapshot?.availableResetCredits,
              count > 0,
              let grantedAt = snapshot?.nextResetCreditGrantedAt,
              let expiresAt = snapshot?.nextResetCreditExpiry else { return nil }
        let duration = expiresAt.timeIntervalSince(grantedAt)
        guard duration.isFinite, duration > 0 else { return nil }
        let remaining = max(0, expiresAt.timeIntervalSince(now))
        return min(1, max(0, remaining / duration))
    }
}

final class NeutralProgressIndicator: NSProgressIndicator {
    static let fillColor = NSColor.secondaryLabelColor
    static let trackColor = NSColor.separatorColor

    override func draw(_ dirtyRect: NSRect) {
        let trackBounds = bounds.integral
        let radius = trackBounds.height / 2

        Self.trackColor.setFill()
        NSBezierPath(roundedRect: trackBounds, xRadius: radius, yRadius: radius).fill()

        let range = maxValue - minValue
        guard range > 0 else { return }
        let fraction = min(1, max(0, (doubleValue - minValue) / range))
        guard fraction > 0 else { return }

        var fillBounds = trackBounds
        fillBounds.size.width *= fraction
        Self.fillColor.setFill()
        NSBezierPath(roundedRect: fillBounds, xRadius: radius, yRadius: radius).fill()
    }
}

final class QuotaProgressMenuView: MenuContentView {
    init(presentation: QuotaProgressPresentation) {
        super.init(spacing: 6, alignment: .leading)

        add(Self.labelRow(title: "Plan", value: presentation.planValue), to: stack)
        if let creditsRemainingValue = presentation.creditsRemainingValue {
            add(Self.labelRow(title: "Credits remaining", value: creditsRemainingValue), to: stack)
        }
        if let statusDetail = presentation.statusDetail {
            add(Self.detailLabel(statusDetail), to: stack)
        }
        if let updatedValue = presentation.updatedValue {
            add(Self.detailLabel(updatedValue), to: stack)
        }
        if let rateLimitReachedValue = presentation.rateLimitReachedValue {
            add(Self.detailLabel(rateLimitReachedValue), to: stack)
        }

        if presentation.quotaWindows.isEmpty {
            addQuota(
                title: "Weekly",
                quotaValue: presentation.quotaValue,
                quotaProgress: presentation.quotaProgress,
                resetValue: presentation.resetValue,
                resetProgress: presentation.resetProgress,
                resetDetail: presentation.resetDetail,
                paceText: nil,
                projectedExhaustionText: nil,
                to: stack,
                includeSeparator: false
            )
        } else {
            for (index, window) in presentation.quotaWindows.enumerated() {
                addQuota(window, to: stack, includeSeparator: index > 0)
            }
        }

        if let creditsValue = presentation.resetCreditsValue {
            add(Self.labelRow(title: "Reset credits", value: creditsValue), to: stack)
        }
        if let creditsProgress = presentation.resetCreditsProgress {
            add(Self.progressBar(
                value: creditsProgress,
                accessibilityLabel: "Time remaining until next reset credit expires"
            ), to: stack)
        }
        if let creditsDetail = presentation.resetCreditsDetail {
            add(Self.detailLabel(creditsDetail), to: stack)
        }

        resizeToFitContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func addQuota(
        _ window: QuotaWindowPresentation,
        to stack: NSStackView,
        includeSeparator: Bool
    ) {
        addQuota(
            title: window.title,
            quotaValue: window.quotaValue,
            quotaProgress: window.quotaProgress,
            resetValue: window.resetValue,
            resetProgress: window.resetProgress,
            resetDetail: window.resetDetail,
            paceText: window.paceText,
            projectedExhaustionText: window.projectedExhaustionText,
            to: stack,
            includeSeparator: includeSeparator
        )
    }

    private func addQuota(
        title: String,
        quotaValue: String,
        quotaProgress: Double?,
        resetValue: String,
        resetProgress: Double?,
        resetDetail: String?,
        paceText: String?,
        projectedExhaustionText: String?,
        to stack: NSStackView,
        includeSeparator: Bool
    ) {
        if includeSeparator {
            let separator = NSBox()
            separator.boxType = .separator
            add(separator, to: stack)
        }
        add(Self.labelRow(title: "\(title) remaining", value: quotaValue), to: stack)
        add(Self.progressBar(
            value: quotaProgress,
            accessibilityLabel: "\(title) quota remaining"
        ), to: stack)
        add(Self.labelRow(title: "Until reset", value: resetValue), to: stack)
        add(Self.progressBar(
            value: resetProgress,
            accessibilityLabel: "Time remaining until \(title) reset"
        ), to: stack)
        let resetAndPace = [resetDetail, paceText].compactMap { $0 }.joined(separator: " — ")
        if !resetAndPace.isEmpty {
            add(Self.detailLabel(resetAndPace), to: stack)
        }
        if let projectedExhaustionText {
            add(Self.detailLabel(projectedExhaustionText), to: stack)
        }
    }

    private func add(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private static func detailLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private static func labelRow(title: String, value: String) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor

        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
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

    private static func progressBar(value: Double?, accessibilityLabel: String) -> NSProgressIndicator {
        let progress = NeutralProgressIndicator()
        progress.style = .bar
        progress.controlSize = .small
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.doubleValue = value ?? 0
        progress.toolTip = accessibilityLabel
        progress.setAccessibilityLabel(accessibilityLabel)
        progress.setAccessibilityValue(value.map { "\(Int(($0 * 100).rounded())) percent" } ?? "Unavailable")
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.heightAnchor.constraint(equalToConstant: 6).isActive = true
        return progress
    }
}
