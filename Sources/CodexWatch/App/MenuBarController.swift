import AppKit
import Foundation

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let authReader: any CredentialsReading
    private let accountService: (any CodexAccountServing)?
    private let session: URLSession
    private let defaults: UserDefaults
    private let notificationController: QuotaNotificationController
    private let launchAtLoginSetting: LaunchAtLoginSetting
    private let persistRefreshFrequency: (RefreshFrequency) -> Void
    private var coordinator: RefreshCoordinator!
    private var snapshot: UsageSnapshot?
    private var usageProjectionCache = UsageAnalyticsProjectionCache()
    private var menuProfile: CodexProfileStats?
    private var menuLifetime: LifetimeDashboardModel?
    private var errorState: MenuBarErrorState?
    private(set) var analyticsStale = false
    private(set) var profileStale = false
    private var menuAnalyticsSection: MenuAnalyticsSection
    private var analyticsWindowController: AnalyticsWindowController?
    private var rateLimitUpdatesTask: Task<Void, Never>?
    private var resetRedemptionState = ResetCreditRedemptionState()
    private var isResetInFlight = false

    init(
        statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength),
        authReader: any CredentialsReading = CodexAuthReader(),
        accountService: (any CodexAccountServing)? = nil,
        session: URLSession = SecureUsageSession.make(),
        defaults: UserDefaults = .standard,
        notificationController: QuotaNotificationController? = nil,
        launchAtLoginSetting: LaunchAtLoginSetting? = nil,
        refreshFrequency: RefreshFrequency = .adaptive,
        persistRefreshFrequency: @escaping (RefreshFrequency) -> Void = { _ in }
    ) {
        self.statusItem = statusItem
        self.authReader = authReader
        self.accountService = accountService
        self.session = session
        self.defaults = defaults
        defaults.removeObject(forKey: "showCodexSparkStats")
        self.notificationController = notificationController ?? QuotaNotificationController(
            delivery: UnavailableQuotaNotificationDelivery()
        )
        self.launchAtLoginSetting = launchAtLoginSetting ?? LaunchAtLoginSetting(
            service: UnavailableLaunchAtLoginService()
        )
        menuAnalyticsSection = MenuAnalyticsSection.load(from: defaults)
        self.persistRefreshFrequency = persistRefreshFrequency
        super.init()
        coordinator = RefreshCoordinator(
            frequency: refreshFrequency,
            fetch: { [weak self] request in
                guard let self else {
                    return RefreshResult(
                        snapshot: nil,
                        error: nil,
                        analyticsStale: false,
                        profileStale: false
                    )
                }
                return await self.fetch(request: request)
            },
            publish: { [weak self] result in
                self?.apply(result: result)
            }
        )
    }

    func start() {
        configureStatusButton()
        rebuildMenu()
        restoreNotificationPreference()
        observeRateLimitUpdates()
        coordinator.trigger(.manual)
    }

    func stop() {
        coordinator.stop()
        rateLimitUpdatesTask?.cancel()
        rateLimitUpdatesTask = nil
        if let accountService {
            Task { await accountService.stop() }
        }
        session.invalidateAndCancel()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func wake() {
        coordinator.trigger(.wake)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        coordinator.trigger(.menuOpened)
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        MenuBarButtonStyle.apply(to: button)
        button.title = MenuBarText.statusTitle(snapshot: nil)
    }

    @objc private func refreshNow() {
        coordinator.trigger(.manual)
    }

    @objc private func setRefreshFrequency(_ sender: NSMenuItem) {
        guard let rawValue = (sender.representedObject as? NSNumber)?.intValue,
              let frequency = RefreshFrequency(rawValue: rawValue) else { return }
        persistRefreshFrequency(frequency)
        coordinator.setFrequency(frequency)
        rebuildMenu()
    }

    private func fetch(request: RefreshRequest) async -> RefreshResult {
        let authReader = authReader
        let credentials = try? await Task.detached(priority: .utility) {
            try authReader.read()
        }.value
        let legacy = credentials.map {
            CodexUsageClient(credentials: $0, session: session)
        }
        let accountService = accountService
        return await RefreshBatch.execute(
            previousSnapshot: snapshot,
            analyticsWasStale: analyticsStale,
            profileWasStale: profileStale,
            includeAnalytics: request.includeAnalytics,
            requestedAt: request.requestedAt,
            quota: {
                await CodexDataSourceStrategy.fetchQuota(
                    account: accountService,
                    legacy: legacy,
                    fetchedAt: request.requestedAt
                )
            },
            analytics: {
                await CodexDataSourceStrategy.fetchAnalytics(
                    legacy: legacy,
                    referenceDate: request.requestedAt
                )
            },
            profile: {
                await CodexDataSourceStrategy.fetchProfile(
                    account: accountService,
                    legacy: legacy,
                    fetchedAt: request.requestedAt
                )
            },
            onQuota: { [weak self] result in
                await self?.coordinator.publishPartial(result, generation: request.generation)
            }
        )
    }

    func apply(result: RefreshResult) {
        analyticsStale = result.analyticsStale
        profileStale = result.profileStale
        if let value = result.snapshot {
            snapshot = value
        }
        if result.snapshot != nil || result.error != nil {
            errorState = result.error
        }
        updateStatusButton()
        analyticsWindowController?.update(
            dataset: snapshot?.analyticsDataset,
            errorState: dashboardErrorState,
            profileStats: snapshot?.profileStats,
            profileErrorState: profileDashboardErrorState
        )
        rebuildMenu()
        let remaining = result.snapshot?.weeklyWindow?.remainingPercent
        let windowResetAt = result.snapshot?.weeklyWindow?.resetAt
        let isFresh = result.error == nil && result.quotaFetchedAt != nil
        Task {
            await notificationController.consider(
                remainingPercent: remaining,
                isFresh: isFresh,
                windowResetAt: windowResetAt
            )
        }
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }
        button.title = MenuBarText.statusTitle(snapshot: snapshot)
        let isStale = errorState != nil && snapshot != nil
        MenuBarButtonStyle.applyRefreshState(to: button, isStale: isStale)
    }

    private func rebuildMenu(_ existingMenu: NSMenu? = nil) {
        let menu = existingMenu ?? NSMenu()
        menu.removeAllItems()
        menu.delegate = self
        menu.showsStateColumn = false
        let progressItem = NSMenuItem()
        progressItem.view = QuotaProgressMenuView(
            presentation: QuotaProgressPresentation(
                snapshot: snapshot,
                error: errorState,
                now: .now
            )
        )
        menu.addItem(progressItem)

        let usagePresentation = snapshot?.analyticsDataset.flatMap { dataset in
            usageProjectionCache.projection(
                dataset: dataset,
                range: .days30,
                referenceDate: .now
            ).map { projection in
                UsageAnalyticsPresentation(
                    projection: projection,
                    isStale: analyticsStale
                )
            }
        }
        if menuProfile != snapshot?.profileStats {
            menuProfile = snapshot?.profileStats
            menuLifetime = menuProfile.map(LifetimeDashboardModel.init)
        }
        let lifetimePresentation = menuLifetime.map { model in
            LifetimeAnalyticsPresentation(
                model: model,
                isStale: profileStale
            )
        }

        if usagePresentation != nil || lifetimePresentation != nil {
            menu.addItem(.separator())
            let analyticsItem = NSMenuItem()
            analyticsItem.view = UsageAnalyticsMenuView(
                usagePresentation: usagePresentation,
                lifetimePresentation: lifetimePresentation,
                selectedSection: menuAnalyticsSection,
                onSelect: { [weak self] section in
                    guard let self else { return }
                    menuAnalyticsSection = section
                    section.persist(to: defaults)
                }
            )
            menu.addItem(analyticsItem)
        }

        menu.addItem(.separator())
        menu.addItem(actionItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r"))
        menu.addItem(refreshFrequencyItem())
        menu.addItem(toggleItem(
            title: "Quota Notifications",
            action: #selector(toggleQuotaNotifications),
            isOn: FeaturePreferences.notificationsEnabled(in: defaults)
        ))
        menu.addItem(toggleItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            isOn: launchAtLoginSetting.isEnabled
        ))
        if let count = snapshot?.availableResetCredits,
           count > 0,
           accountService != nil {
            let resetItem = actionItem(
                title: "Use Reset Credit…",
                action: #selector(useResetCredit),
                keyEquivalent: ""
            )
            resetItem.isEnabled = !isResetInFlight
            menu.addItem(resetItem)
        }
        menu.addItem(actionItem(title: "Open ChatGPT", action: #selector(openChatGPT), keyEquivalent: "o"))
        menu.addItem(
            actionItem(
                title: "Open Analytics Dashboard…",
                action: #selector(openAnalyticsDashboard),
                keyEquivalent: "d"
            )
        )
        menu.addItem(
            actionItem(
                title: "Open Usage Analytics…",
                action: #selector(openUsageAnalytics),
                keyEquivalent: ""
            )
        )
        menu.addItem(actionItem(
            title: "Copy Diagnostics",
            action: #selector(copyDiagnostics),
            keyEquivalent: ""
        ))
        menu.addItem(.separator())
        let versionItem = NSMenuItem(title: "Version \(AppIdentity.version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(.separator())
        menu.addItem(actionItem(title: "Quit Codex Watch", action: #selector(quit), keyEquivalent: "q"))
        if statusItem.menu !== menu {
            statusItem.menu = menu
        }
    }

    private func refreshFrequencyItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Refresh Frequency", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Refresh Frequency")
        let order: [RefreshFrequency] = [
            .adaptive,
            .manual,
            .oneMinute,
            .twoMinutes,
            .fiveMinutes,
            .fifteenMinutes,
            .thirtyMinutes
        ]
        for frequency in order {
            let item = NSMenuItem(
                title: frequency.displayName,
                action: #selector(setRefreshFrequency),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = NSNumber(value: frequency.rawValue)
            item.state = coordinator.frequency == frequency ? .on : .off
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }

    private func actionItem(title: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func toggleItem(title: String, action: Selector, isOn: Bool) -> NSMenuItem {
        let item = actionItem(title: title, action: action, keyEquivalent: "")
        // An on-state can force the leading checkmark gutter on macOS even
        // when showsStateColumn is false. The trailing badge owns presentation.
        item.toolTip = isOn ? "Enabled" : "Disabled"
        item.badge = isOn ? NSMenuItemBadge(string: "✓") : nil
        return item
    }

    @objc private func openChatGPT() {
        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: AppIdentity.chatGPTCodexBundleIdentifier
        ) else { return }
        NSWorkspace.shared.open(appURL)
    }

    @objc private func openUsageAnalytics() {
        NSWorkspace.shared.open(AppIdentity.usageAnalyticsURL)
    }

    @objc private func openAnalyticsDashboard() {
        let controller: AnalyticsWindowController
        if let analyticsWindowController {
            controller = analyticsWindowController
        } else {
            controller = AnalyticsWindowController(onRefresh: { [weak self] in
                self?.coordinator.trigger(.manual)
            })
            analyticsWindowController = controller
        }
        controller.show(
            dataset: snapshot?.analyticsDataset,
            errorState: dashboardErrorState,
            profileStats: snapshot?.profileStats,
            profileErrorState: profileDashboardErrorState
        )
    }

    private var dashboardErrorState: AnalyticsDashboardErrorState? {
        analyticsStale || snapshot?.analyticsDataset == nil ? .analyticsUnavailable : nil
    }

    private var profileDashboardErrorState: AnalyticsDashboardErrorState? {
        profileStale || snapshot?.profileStats == nil ? .profileUnavailable : nil
    }

    private func restoreNotificationPreference() {
        guard FeaturePreferences.notificationsEnabled(in: defaults) else { return }
        Task { [weak self] in
            guard let self else { return }
            let enabled = await notificationController.requestEnable()
            if !enabled {
                FeaturePreferences.setNotificationsEnabled(false, in: defaults)
                rebuildMenu()
            }
        }
    }

    private func observeRateLimitUpdates() {
        guard let accountService else { return }
        rateLimitUpdatesTask = Task { [weak self] in
            while !Task.isCancelled {
                if let stream = try? await accountService.rateLimitUpdates() {
                    guard !Task.isCancelled else { return }
                    self?.coordinator.trigger(.rateLimitUpdated)
                    for await _ in stream {
                        guard !Task.isCancelled else { return }
                        self?.coordinator.trigger(.rateLimitUpdated)
                    }
                }
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
    }

    @objc private func toggleQuotaNotifications() {
        if FeaturePreferences.notificationsEnabled(in: defaults) {
            FeaturePreferences.setNotificationsEnabled(false, in: defaults)
            Task { await notificationController.disable() }
            rebuildMenu()
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let enabled = await notificationController.requestEnable()
            FeaturePreferences.setNotificationsEnabled(enabled, in: defaults)
            rebuildMenu()
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try launchAtLoginSetting.setEnabled(!launchAtLoginSetting.isEnabled)
            rebuildMenu()
        } catch {
            showAlert(
                title: "Launch at Login could not be changed",
                message: "Review Codex Watch in System Settings and try again."
            )
        }
    }

    @objc private func copyDiagnostics() {
        let diagnostics = SafeDiagnostics(
            version: AppIdentity.version,
            dataSource: diagnosticsDataSource,
            quota: quotaDiagnosticsState,
            usage: snapshot?.analyticsDataset == nil ? .unavailable : (analyticsStale ? .stale : .current),
            lifetime: snapshot?.profileStats == nil ? .unavailable : (profileStale ? .stale : .current),
            notificationsEnabled: FeaturePreferences.notificationsEnabled(in: defaults),
            launchAtLoginEnabled: launchAtLoginSetting.isEnabled
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics.text, forType: .string)
    }

    @objc private func useResetCredit() {
        guard let accountService, !isResetInFlight else { return }
        let confirmation = NSAlert()
        confirmation.alertStyle = .warning
        confirmation.messageText = "Use one reset credit?"
        confirmation.informativeText = "This consumes a server-managed reset credit and may reset your weekly Codex quota."
        confirmation.addButton(withTitle: "Use Reset Credit")
        confirmation.addButton(withTitle: "Cancel")
        guard confirmation.runModal() == .alertFirstButtonReturn else { return }

        let creditID = snapshot?.resetCredits.first {
            $0.status == "available" && $0.isSupportedByPlan != false
        }?.id
        let request = resetRedemptionState.request(creditID: creditID)
        isResetInFlight = true
        rebuildMenu()

        Task { [weak self] in
            guard let self else { return }
            do {
                let outcome = try await accountService.consumeReset(
                    idempotencyKey: request.idempotencyKey,
                    creditID: request.creditID
                )
                resetRedemptionState.complete(outcome: outcome)
                isResetInFlight = false
                showAlert(
                    title: "Reset credit result",
                    message: ResetCreditRedemptionState.message(for: outcome)
                )
                coordinator.trigger(.manual)
            } catch {
                isResetInFlight = false
                showAlert(
                    title: "Reset credit result is uncertain",
                    message: "Try again to safely reuse the same request, or refresh quota before retrying."
                )
                rebuildMenu()
            }
        }
    }

    private var diagnosticsDataSource: DiagnosticsDataSource {
        switch snapshot?.source {
        case .appServer: .appServer
        case .legacyHTTPS: .legacyHTTPS
        case nil: .unavailable
        }
    }

    private var quotaDiagnosticsState: DiagnosticsSurfaceState {
        guard snapshot?.weeklyWindow != nil else { return .unavailable }
        return errorState == nil ? .current : .stale
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
