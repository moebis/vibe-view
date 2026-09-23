import AppKit

final class ClaudeQuotaMenuView: MenuContentView {
    init(snapshot: ClaudeUsageSnapshot?, error: ClaudeConnectionError?, isRefreshing: Bool, now: Date = .now) {
        super.init(spacing: 5, alignment: .leading)
        let title = NSTextField(labelWithString: "Claude · shared plan usage")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(title)
        if let snapshot {
            for window in snapshot.windows {
                let name = NSTextField(labelWithString: "\(window.title) remaining")
                let value = NSTextField(labelWithString: "\(Int(window.remainingPercent.rounded()))%")
                name.font = .systemFont(ofSize: 13, weight: .medium)
                value.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
                value.textColor = .secondaryLabelColor
                let row = NSStackView(views: [name, value])
                row.distribution = .equalSpacing
                row.orientation = .horizontal
                stack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
                let progress = NeutralProgressIndicator()
                progress.controlSize = .small
                progress.translatesAutoresizingMaskIntoConstraints = false
                progress.heightAnchor.constraint(equalToConstant: 6).isActive = true
                progress.isIndeterminate = false
                progress.style = .bar
                progress.minValue = 0
                progress.maxValue = 100
                progress.doubleValue = window.remainingPercent
                progress.setAccessibilityLabel("Claude \(window.title) remaining")
                progress.setAccessibilityValue("\(Int(window.remainingPercent.rounded())) percent")
                stack.addArrangedSubview(progress)
                progress.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
                if let reset = window.resetsAt {
                    addDetail(MenuBarText.resetLine(resetAt: reset))
                }
            }
            let detail = isRefreshing ? "Refreshing…" : MenuBarText.updatedLine(lastUpdated: snapshot.fetchedAt, now: now)
            addDetail(detail)
        } else {
            addDetail(isRefreshing ? "Connecting to Claude…" : error?.message ?? "Connect Claude to show quota")
        }
        resizeToFitContent()
    }

    private func addDetail(_ text: String) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        stack.addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
