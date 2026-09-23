import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AnalyticsWindowController: NSObject, NSWindowDelegate {
    static let frameAutosaveName = "CodexWatchAnalyticsWindow"

    private let model: AnalyticsDashboardModel
    private let onRefresh: () -> Void
    private var window: NSWindow?

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        onRefresh: @escaping () -> Void = {}
    ) {
        model = AnalyticsDashboardModel(defaults: defaults, calendar: calendar)
        self.onRefresh = onRefresh
        super.init()
    }

    func requestRefresh() {
        onRefresh()
    }

    func show(
        dataset: UsageAnalyticsDataset?,
        errorState: AnalyticsDashboardErrorState?,
        profileStats: CodexProfileStats?,
        profileErrorState: AnalyticsDashboardErrorState?
    ) {
        model.update(
            dataset: dataset,
            error: errorState,
            profileStats: profileStats,
            profileError: profileErrorState,
            now: .now
        )
        let window = window ?? makeWindow()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func update(
        dataset: UsageAnalyticsDataset?,
        errorState: AnalyticsDashboardErrorState?,
        profileStats: CodexProfileStats?,
        profileErrorState: AnalyticsDashboardErrorState?
    ) {
        guard window != nil else { return }
        model.update(
            dataset: dataset,
            error: errorState,
            profileStats: profileStats,
            profileError: profileErrorState,
            now: .now
        )
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow === window else { return }
        window = nil
    }

    private func makeWindow() -> NSWindow {
        let rootView = AnalyticsDashboardView(
            model: model,
            onRefresh: { [weak self] in self?.requestRefresh() },
            onExport: { [weak self] in self?.exportCSV() }
        )
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Codex Watch Analytics"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 940, height: 720))
        window.minSize = NSSize(width: 760, height: 560)
        window.isReleasedWhenClosed = false
        window.delegate = self
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.frameAutosaveName)
        self.window = window
        return window
    }

    private func exportCSV() {
        do {
            let csv = try model.csvString()
            let panel = NSSavePanel()
            panel.title = "Export Codex Analytics"
            panel.nameFieldStringValue = model.suggestedCSVFilename
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let destination = panel.url else { return }
            try Data(csv.utf8).write(to: destination, options: .atomic)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Analytics export failed"
            alert.informativeText = "Codex Watch could not save the CSV. Choose another destination and try again."
            alert.addButton(withTitle: "OK")
            if let window {
                alert.beginSheetModal(for: window)
            } else {
                alert.runModal()
            }
        }
    }
}
