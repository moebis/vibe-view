import AppKit
import Foundation
import XCTest
@testable import CodexWatch

@MainActor
final class MenuBarTextTests: XCTestCase {
    func testMenuDoesNotOfferRepositoryUpdateChecks() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let controller = MenuBarController(
            statusItem: statusItem,
            authReader: CodexAuthReader(
                environment: [:],
                homeDirectory: URL(fileURLWithPath: "/definitely/not/the-test-home")
            ),
            session: URLSession(configuration: .ephemeral)
        )
        controller.start()
        defer { controller.stop() }

        let menuTitles = statusItem.menu?.items.map(\.title) ?? []

        XCTAssertFalse(menuTitles.contains { $0.localizedCaseInsensitiveContains("update") })
    }

    func testMenuOffersOfficialUsageAnalyticsWithoutRestoringUpdates() {
        let suiteName = "RetiredSparkTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "showCodexSparkStats")
        defaults.set("lifetime", forKey: "codexWatch.analyticsSection")
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let controller = MenuBarController(
            statusItem: statusItem,
            authReader: CodexAuthReader(
                environment: [:],
                homeDirectory: URL(fileURLWithPath: "/definitely/not/the-test-home")
            ),
            session: URLSession(configuration: .ephemeral),
            defaults: defaults
        )
        controller.start()
        defer { controller.stop() }

        XCTAssertNil(defaults.object(forKey: "showCodexSparkStats"))
        XCTAssertEqual(defaults.string(forKey: "codexWatch.analyticsSection"), "lifetime")
        if let menu = statusItem.menu {
            controller.menuNeedsUpdate(menu)
            XCTAssertTrue(statusItem.menu === menu)
        }
        let menuTitles = statusItem.menu?.items.map(\.title) ?? []

        XCTAssertTrue(menuTitles.contains("Open Usage Analytics…"))
        XCTAssertTrue(menuTitles.contains("Open Analytics Dashboard…"))
        XCTAssertTrue(menuTitles.contains("Refresh Frequency"))
        XCTAssertFalse(menuTitles.contains { $0.contains("Spark") })
        XCTAssertEqual(statusItem.menu?.showsStateColumn, false)
        for item in statusItem.menu?.items ?? [] where item.title == "Quota Notifications" || item.title == "Launch at Login" {
            XCTAssertEqual(item.badge?.stringValue, item.state == .on ? "✓" : nil)
        }
        XCTAssertTrue(menuTitles.contains("Quota Notifications"))
        XCTAssertTrue(menuTitles.contains("Launch at Login"))
        XCTAssertTrue(menuTitles.contains("Copy Diagnostics"))
        XCTAssertFalse(menuTitles.contains { $0.localizedCaseInsensitiveContains("update") })
        XCTAssertEqual(
            AppIdentity.usageAnalyticsURL.absoluteString,
            "https://chatgpt.com/codex/cloud/settings/analytics#usage"
        )
    }

    func testQuotaPresentationExplainsWorkspaceLimitReason() {
        let presentation = QuotaProgressPresentation(
            snapshot: UsageSnapshot(
                windows: [UsageWindow(id: "weekly", kind: .weekly, usedPercent: 100)],
                rateLimitReachedReason: .workspaceCreditsDepleted
            ),
            error: nil,
            now: .now
        )

        XCTAssertEqual(presentation.rateLimitReachedValue, "Workspace credits depleted")
    }

    func testConfirmedResetActionAppearsForOfficialAvailableCredit() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let controller = MenuBarController(
            statusItem: statusItem,
            accountService: MenuAccountServiceFake(),
            refreshFrequency: .manual
        )
        defer { controller.stop() }

        controller.apply(result: RefreshResult(
            snapshot: UsageSnapshot(
                windows: [],
                resetCredits: [ResetCredit(
                    id: "credit-one",
                    status: "available",
                    title: nil,
                    grantedAt: nil,
                    expiresAt: nil,
                    isSupportedByPlan: true
                )],
                availableResetCredits: 1,
                source: .appServer
            ),
            error: nil,
            analyticsStale: false,
            profileStale: false
        ))

        XCTAssertTrue(statusItem.menu?.items.contains { $0.title == "Use Reset Credit…" } == true)
    }

    func testRefreshPolicyLimitsAutomaticAnalyticsButAllowsManualRefresh() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        XCTAssertTrue(RefreshPolicy.shouldIncludeAnalytics(trigger: .automatic, lastAttempt: nil, now: now))
        XCTAssertFalse(
            RefreshPolicy.shouldIncludeAnalytics(
                trigger: .automatic,
                lastAttempt: now.addingTimeInterval(-899),
                now: now
            )
        )
        XCTAssertTrue(
            RefreshPolicy.shouldIncludeAnalytics(
                trigger: .automatic,
                lastAttempt: now.addingTimeInterval(-900),
                now: now
            )
        )
        XCTAssertTrue(
            RefreshPolicy.shouldIncludeAnalytics(
                trigger: .manual,
                lastAttempt: now,
                now: now
            )
        )
    }

    func testUsageAnalyticsPresentationFormatsSixTruthfulThirtyDayMetrics() {
        let projection = makeAnalyticsProjection(
            totalTokens: 30_300_000_000,
            inputTokens: 1_200_000,
            cachedInputTokens: 999,
            outputTokens: 2_345,
            turns: 3_427,
            chats: 42
        )

        let presentation = UsageAnalyticsPresentation(projection: projection)

        XCTAssertEqual(presentation.title, "Last 30 days")
        XCTAssertEqual(presentation.totalTokens, "30.3B")
        XCTAssertEqual(presentation.inputTokens, "1.2M")
        XCTAssertEqual(presentation.cachedInputTokens, "999")
        XCTAssertEqual(presentation.outputTokens, "2.3K")
        XCTAssertEqual(presentation.turns, "3.4K")
        XCTAssertEqual(presentation.chats, "42")
        XCTAssertEqual(presentation.coverage, "1/30 days")
        XCTAssertFalse(presentation.dataThrough.isEmpty)
    }

    func testMenuAnalyticsSectionDefaultsToThirtyDaysAndPersistsLifetime() {
        let suiteName = "CodexWatchTests.MenuAnalyticsSection.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(MenuAnalyticsSection.load(from: defaults), .days30)

        MenuAnalyticsSection.lifetime.persist(to: defaults)

        XCTAssertEqual(MenuAnalyticsSection.load(from: defaults), .lifetime)
    }

    func testLifetimeMenuPresentationUsesExactProfileHeadlineMetrics() {
        let profile = CodexProfileStats(
            lifetimeTokens: 30_300_000_000,
            peakDailyTokens: 1_100_000_000,
            longestRunningTurnSeconds: 56_580,
            currentStreakDays: 42,
            longestStreakDays: 82,
            dailyBuckets: [],
            insights: CodexProfileInsights(
                fastModePercent: nil,
                reasoningEffort: nil,
                reasoningEffortPercent: nil,
                uniqueSkillsUsed: nil,
                totalSkillsUsed: nil,
                totalChats: nil
            ),
            invocations: [],
            fetchedAt: Date(timeIntervalSince1970: 1_776_326_400)
        )

        let presentation = LifetimeAnalyticsPresentation(
            model: LifetimeDashboardModel(profile: profile),
            isStale: true
        )

        XCTAssertEqual(presentation.title, "Lifetime")
        XCTAssertEqual(presentation.lifetimeTokens, "30.3B")
        XCTAssertEqual(presentation.peakTokens, "1.1B")
        XCTAssertEqual(presentation.longestChat, "15h 43m")
        XCTAssertEqual(presentation.currentStreak, "42 days")
        XCTAssertEqual(presentation.longestStreak, "82 days")
        XCTAssertFalse(presentation.dataThrough.isEmpty)
        XCTAssertEqual(presentation.staleValue, "Stale · refresh unavailable")
    }

    func testUsageAnalyticsMenuLabelsPreservedAnalyticsAsStale() {
        let presentation = UsageAnalyticsPresentation(
            projection: makeAnalyticsProjection(
                totalTokens: 100,
                inputTokens: 20,
                cachedInputTokens: 30,
                outputTokens: 50,
                turns: 4,
                chats: 2
            ),
            isStale: true
        )
        let view = UsageAnalyticsMenuView(presentation: presentation)

        XCTAssertEqual(presentation.staleValue, "Stale · refresh unavailable")
        XCTAssertTrue(textValues(in: view).contains("Stale · refresh unavailable"))
        assertContentFits(view)
    }

    func testUsageAnalyticsMenuContainsSixLabeledRows() {
        let view = UsageAnalyticsMenuView(
            presentation: UsageAnalyticsPresentation(
                projection: makeAnalyticsProjection(
                    totalTokens: 14_000,
                    inputTokens: 2_500,
                    cachedInputTokens: 4_500,
                    outputTokens: 7_000,
                    turns: 22,
                    chats: 5
                )
            )
        )
        let values = textValues(in: view)

        XCTAssertTrue(values.contains("Last 30 days"))
        XCTAssertTrue(values.contains("Total tokens"))
        XCTAssertTrue(values.contains("Input tokens"))
        XCTAssertTrue(values.contains("Cached input"))
        XCTAssertTrue(values.contains("Output tokens"))
        XCTAssertTrue(values.contains("Turns"))
        XCTAssertTrue(values.contains("Chats"))
        XCTAssertTrue(values.contains("Token coverage"))
        XCTAssertTrue(values.contains("Data through"))
        XCTAssertEqual(view.frame.width, UsageAnalyticsMenuView.width)
    }

    func testMenuAnalyticsSelectorSwitchesBetweenThirtyDaysAndLifetimeWithoutClosing() throws {
        var selectedSection: MenuAnalyticsSection?
        let view = UsageAnalyticsMenuView(
            usagePresentation: UsageAnalyticsPresentation(
                projection: makeAnalyticsProjection(
                    totalTokens: 12_600_000_000,
                    inputTokens: 559_000_000,
                    cachedInputTokens: 12_000_000_000,
                    outputTokens: 41_800_000,
                    turns: 3_400,
                    chats: 1_300
                )
            ),
            lifetimePresentation: makeLifetimePresentation(),
            selectedSection: .days30,
            onSelect: { selectedSection = $0 }
        )
        let selector = try XCTUnwrap(segmentedControls(in: view).first)

        XCTAssertEqual(selector.segmentCount, 2)
        XCTAssertEqual(selector.label(forSegment: 0), "30 Days")
        XCTAssertEqual(selector.label(forSegment: 1), "Lifetime")
        XCTAssertEqual(selector.selectedSegment, 0)
        XCTAssertTrue(visibleTextValues(in: view).contains("Input tokens"))
        XCTAssertFalse(visibleTextValues(in: view).contains("Lifetime tokens"))

        selector.selectedSegment = 1
        selector.sendAction(selector.action, to: selector.target)

        XCTAssertEqual(selectedSection, .lifetime)
        XCTAssertTrue(visibleTextValues(in: view).contains("Lifetime tokens"))
        XCTAssertTrue(visibleTextValues(in: view).contains("30.3B"))
        XCTAssertFalse(visibleTextValues(in: view).contains("Input tokens"))
    }

    func testMenuControllerRestoresAndPersistsTheAnalyticsSelector() throws {
        let suiteName = "CodexWatchTests.MenuControllerSection.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        MenuAnalyticsSection.lifetime.persist(to: defaults)
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let controller = MenuBarController(
            statusItem: statusItem,
            authReader: CodexAuthReader(
                environment: [:],
                homeDirectory: URL(fileURLWithPath: "/definitely/not/the-test-home")
            ),
            session: URLSession(configuration: .ephemeral),
            defaults: defaults
        )
        defer { controller.stop() }

        controller.apply(result: RefreshResult(
            snapshot: UsageSnapshot(
                windows: [],
                analyticsDataset: makeAnalyticsDataset(
                    totalTokens: 12_600_000_000,
                    inputTokens: 559_000_000,
                    cachedInputTokens: 12_000_000_000,
                    outputTokens: 41_800_000,
                    turns: 3_400,
                    chats: 1_300
                ),
                profileStats: makeLifetimeProfile()
            ),
            error: nil,
            analyticsStale: false,
            profileStale: false
        ))

        let view = try XCTUnwrap(
            statusItem.menu?.items.compactMap { $0.view as? UsageAnalyticsMenuView }.first
        )
        let selector = try XCTUnwrap(segmentedControls(in: view).first)
        XCTAssertEqual(selector.label(forSegment: 0), "30 Days")
        XCTAssertEqual(selector.label(forSegment: 1), "Lifetime")
        XCTAssertEqual(selector.selectedSegment, 1)
        XCTAssertTrue(visibleTextValues(in: view).contains("Lifetime tokens"))

        selector.selectedSegment = 0
        selector.sendAction(selector.action, to: selector.target)

        XCTAssertEqual(MenuAnalyticsSection.load(from: defaults), .days30)
        XCTAssertTrue(visibleTextValues(in: view).contains("Input tokens"))
    }

    func testAuthenticationFailureMarksRetainedCapabilityDataStale() async {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let controller = MenuBarController(
            statusItem: statusItem,
            authReader: CodexAuthReader(
                environment: [:],
                homeDirectory: URL(fileURLWithPath: "/definitely/not/the-test-home")
            ),
            session: URLSession(configuration: .ephemeral),
            refreshFrequency: .manual
        )
        controller.apply(result: RefreshResult(
            snapshot: UsageSnapshot(
                windows: [],
                analyticsDataset: makeAnalyticsDataset(
                    totalTokens: 1_000,
                    inputTokens: 200,
                    cachedInputTokens: 700,
                    outputTokens: 100,
                    turns: 4,
                    chats: 2
                ),
                profileStats: makeLifetimeProfile()
            ),
            error: nil,
            analyticsStale: false,
            profileStale: false
        ))
        controller.start()
        defer { controller.stop() }

        for _ in 0 ..< 100 where !controller.analyticsStale || !controller.profileStale {
            await Task.yield()
        }

        XCTAssertTrue(controller.analyticsStale)
        XCTAssertTrue(controller.profileStale)
    }

    func testCredentialReadDoesNotBlockMainActor() async {
        let reader = BlockingCredentialsReader()
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let controller = MenuBarController(
            statusItem: statusItem,
            authReader: reader,
            session: URLSession(configuration: .ephemeral),
            refreshFrequency: .manual
        )
        let responsivenessProbe = Self.makeMainActorResponsivenessProbe(
            whileReadingWith: reader
        )
        controller.start()
        defer { controller.stop() }

        let isResponsive = await responsivenessProbe.value
        XCTAssertTrue(isResponsive)
    }

    private nonisolated static func probeMainActorResponsiveness(
        whileReadingWith reader: BlockingCredentialsReader
    ) -> Bool {
        guard reader.started.wait(timeout: .now() + 1) == .success else {
            reader.release.signal()
            return false
        }
        let mainActorRan = DispatchSemaphore(value: 0)
        Task { @MainActor in
            mainActorRan.signal()
        }
        let isResponsive = mainActorRan.wait(timeout: .now() + 0.25) == .success
        reader.release.signal()
        return isResponsive
    }

    private nonisolated static func makeMainActorResponsivenessProbe(
        whileReadingWith reader: BlockingCredentialsReader
    ) -> Task<Bool, Never> {
        Task.detached {
            probeMainActorResponsiveness(whileReadingWith: reader)
        }
    }

    func testStatusButtonUsesAdaptivePieTemplateAndCompactTitleLayout() {
        let button = NSButton(frame: .zero)

        MenuBarButtonStyle.apply(to: button)

        let image = button.image
        XCTAssertNotNil(image)
        XCTAssertTrue(button.imageHugsTitle)
        XCTAssertEqual(button.imagePosition, .imageLeading)
        XCTAssertEqual(button.alignment, .center)
        XCTAssertEqual(button.font?.pointSize, MenuBarButtonStyle.fontSize)
        XCTAssertEqual(image?.size, NSSize(width: 16, height: 16))
        XCTAssertTrue(image?.isTemplate ?? false)
        XCTAssertEqual(image?.accessibilityDescription, "Codex Watch usage statistics")
        XCTAssertNotNil(image?.tiffRepresentation)
    }

    func testStatusButtonLetsMacOSChooseAdaptiveIconAndPercentageColor() {
        let button = NSButton(frame: .zero)
        button.title = "89%"
        MenuBarButtonStyle.apply(to: button)

        MenuBarButtonStyle.applyRefreshState(to: button, isStale: false)

        XCTAssertNil(button.contentTintColor)
        XCTAssertEqual(button.alphaValue, 1)

        MenuBarButtonStyle.applyRefreshState(to: button, isStale: true)

        XCTAssertNil(button.contentTintColor)
        XCTAssertEqual(button.alphaValue, 0.62, accuracy: 0.001)
        XCTAssertEqual(button.title, "89%")
    }

    func testStatusTitleShowsRoundedWeeklyRemainingPercent() {
        let snapshot = UsageSnapshot(
            windows: [UsageWindow(id: "weekly", kind: .weekly, usedPercent: 31.6)]
        )

        XCTAssertEqual(MenuBarText.statusTitle(snapshot: snapshot), "68%")
        XCTAssertEqual(MenuBarText.summary(snapshot: snapshot, error: nil), "Weekly remaining: 68%")
    }

    func testUnavailableStatesNeverExposeErrorDetails() {
        XCTAssertEqual(MenuBarText.statusTitle(snapshot: nil), "—")
        XCTAssertEqual(
            MenuBarText.summary(snapshot: nil, error: .signInRequired),
            "Sign in to Codex again"
        )
        XCTAssertEqual(
            MenuBarText.summary(snapshot: nil, error: .quotaUnavailable),
            "Quota unavailable"
        )
    }

    func testStalePresentationShowsErrorAndLastSuccessfulUpdateTime() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let snapshot = UsageSnapshot(
            windows: [UsageWindow(id: "weekly", kind: .weekly, usedPercent: 25)],
            fetchedAt: now.addingTimeInterval(-125)
        )

        let presentation = QuotaProgressPresentation(
            snapshot: snapshot,
            error: .quotaUnavailable,
            now: now
        )
        let values = textValues(in: QuotaProgressMenuView(presentation: presentation))

        XCTAssertEqual(presentation.statusDetail, "Quota unavailable")
        XCTAssertEqual(presentation.updatedValue, "Updated 2m ago")
        XCTAssertTrue(values.contains("Quota unavailable"))
        XCTAssertTrue(values.contains("Updated 2m ago"))
    }

    func testResetLineUsesStableEnglishFormatting() {
        let snapshot = UsageSnapshot(
            windows: [
                UsageWindow(
                    id: "weekly",
                    kind: .weekly,
                    usedPercent: 10,
                    resetAt: Date(timeIntervalSince1970: 1_768_415_045)
                )
            ]
        )

        XCTAssertTrue(MenuBarText.resetLine(snapshot: snapshot)?.hasPrefix("Resets: ") == true)
    }

    func testProgressPresentationUsesRemainingQuotaAndExactWindowDuration() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let snapshot = UsageSnapshot(
            plan: .pro,
            creditsRemaining: .balance("12.50"),
            windows: [
                UsageWindow(
                    id: "weekly",
                    kind: .weekly,
                    usedPercent: 19,
                    resetAt: now.addingTimeInterval(2 * 24 * 60 * 60),
                    durationSeconds: 7 * 24 * 60 * 60
                )
            ]
        )

        let presentation = QuotaProgressPresentation(snapshot: snapshot, error: nil, now: now)

        XCTAssertEqual(presentation.planValue, "Pro")
        XCTAssertEqual(presentation.creditsRemainingValue, "12.50")
        XCTAssertEqual(presentation.quotaValue, "81%")
        XCTAssertEqual(try XCTUnwrap(presentation.quotaProgress), 0.81, accuracy: 0.0001)
        XCTAssertEqual(presentation.resetValue, "2d 0h")
        XCTAssertEqual(try XCTUnwrap(presentation.resetProgress), 2.0 / 7.0, accuracy: 0.0001)
        XCTAssertNotNil(presentation.resetDetail)
    }

    func testProgressPresentationHidesSparkButKeepsOtherQuotaWindowsAndPace() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let weekly = UsageWindow(
            id: "weekly",
            kind: .weekly,
            usedPercent: 60,
            resetAt: now.addingTimeInterval(2 * 86_400),
            durationSeconds: 7 * 86_400
        )
        let fiveHour = UsageWindow(
            id: "primary",
            kind: .rolling(hours: 5),
            usedPercent: 60,
            resetAt: now.addingTimeInterval(2.5 * 3_600),
            durationSeconds: 5 * 3_600
        )
        let spark = UsageWindow(
            id: "codex-spark",
            kind: .rolling(hours: 5),
            usedPercent: 25,
            resetAt: now.addingTimeInterval(2.5 * 3_600),
            durationSeconds: 5 * 3_600
        )
        let sparkWeekly = UsageWindow(
            id: "codex-spark-weekly",
            kind: .weekly,
            usedPercent: 0,
            resetAt: now.addingTimeInterval(6 * 86_400),
            durationSeconds: 7 * 86_400
        )
        let projectLimit = UsageWindow(
            id: "project-limit",
            kind: .daily,
            usedPercent: 25,
            resetAt: now.addingTimeInterval(18 * 3_600),
            durationSeconds: 24 * 3_600
        )
        let codeReview = UsageWindow(
            id: "code-review-primary",
            kind: .daily,
            usedPercent: 50,
            resetAt: now.addingTimeInterval(12 * 3_600),
            durationSeconds: 24 * 3_600
        )
        let snapshot = UsageSnapshot(
            windows: [fiveHour, weekly],
            additionalWindows: [
                NamedUsageWindow(id: spark.id, title: "Codex Spark 5-hour", window: spark),
                NamedUsageWindow(
                    id: sparkWeekly.id,
                    title: "Codex Spark Weekly",
                    window: sparkWeekly
                ),
                NamedUsageWindow(
                    id: projectLimit.id,
                    title: "Project Limit",
                    window: projectLimit
                )
            ],
            codeReviewWindows: [NamedUsageWindow(id: codeReview.id, title: "Code Review", window: codeReview)]
        )

        let presentation = QuotaProgressPresentation(snapshot: snapshot, error: nil, now: now)

        XCTAssertEqual(
            presentation.quotaWindows.map(\.title),
            ["Weekly", "5-hour", "Project Limit", "Code Review"]
        )
        XCTAssertEqual(presentation.quotaWindows[0].paceText, "11% in reserve")
        XCTAssertEqual(presentation.quotaWindows[1].paceText, "10% in deficit")
        XCTAssertEqual(presentation.quotaWindows[2].paceText, "On pace")
        XCTAssertEqual(presentation.quotaWindows[3].paceText, "On pace")
        XCTAssertEqual(presentation.quotaValue, "40%")
    }

    func testProgressPresentationShowsProjectedExhaustionOnlyBeforeReset() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let fastWindow = UsageWindow(
            id: "weekly",
            kind: .weekly,
            usedPercent: 75,
            resetAt: now.addingTimeInterval(3.5 * 86_400),
            durationSeconds: 7 * 86_400
        )
        let onPaceWindow = UsageWindow(
            id: "weekly",
            kind: .weekly,
            usedPercent: 50,
            resetAt: now.addingTimeInterval(3.5 * 86_400),
            durationSeconds: 7 * 86_400
        )

        let fast = QuotaWindowPresentation(
            id: fastWindow.id,
            title: "Weekly",
            window: fastWindow,
            now: now
        )
        let onPace = QuotaWindowPresentation(
            id: onPaceWindow.id,
            title: "Weekly",
            window: onPaceWindow,
            now: now
        )

        XCTAssertEqual(fast.projectedExhaustionAt, now.addingTimeInterval(28 * 3_600))
        XCTAssertTrue(fast.projectedExhaustionText?.hasPrefix("Exhaustion: ") == true)
        XCTAssertNil(onPace.projectedExhaustionAt)
        XCTAssertNil(onPace.projectedExhaustionText)

        let menu = QuotaProgressMenuView(presentation: QuotaProgressPresentation(
            snapshot: UsageSnapshot(windows: [fastWindow]),
            error: nil,
            now: now
        ))
        XCTAssertTrue(textValues(in: menu).contains(fast.projectedExhaustionText!))
    }

    func testProgressPresentationHidesDuplicateSparkWindowIDs() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let duplicateSpark = UsageWindow(
            id: "codex-spark-2",
            kind: .rolling(hours: 5),
            usedPercent: 25
        )
        let duplicateSparkWeekly = UsageWindow(
            id: "codex-spark-weekly-2",
            kind: .weekly,
            usedPercent: 0
        )
        let snapshot = UsageSnapshot(
            windows: [],
            additionalWindows: [
                NamedUsageWindow(
                    id: duplicateSpark.id,
                    title: "Codex Spark 5-hour",
                    window: duplicateSpark
                ),
                NamedUsageWindow(
                    id: duplicateSparkWeekly.id,
                    title: "Codex Spark Weekly",
                    window: duplicateSparkWeekly
                )
            ]
        )

        let presentation = QuotaProgressPresentation(snapshot: snapshot, error: nil, now: now)

        XCTAssertTrue(presentation.quotaWindows.isEmpty)
    }

    func testRetiredSparkRowsStayHiddenWithoutChangingBaseOrCurrentModelQuota() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let sparkNames = [
            ("codex-spark", "Codex Spark 5-hour"),
            ("codex-spark-weekly-2", "Codex Spark Weekly"),
            ("gpt-5-3-codex-spark-primary", "GPT-5.3-Codex-Spark 5-hour"),
            ("gpt-5-3-codex-spark-secondary", "GPT-5.3-Codex-Spark Weekly"),
            ("opaque-model-id", "GPT-5.3-CODEX-SPARK Weekly")
        ]
        let namedWindows = (sparkNames + [("codex-sparkle", "Codex Sparkle"), ("gpt-6-luna", "GPT-6 Luna")]).map { id, title in
            NamedUsageWindow(id: id, title: title, window: UsageWindow(
                id: id, kind: .weekly, usedPercent: 0,
                resetAt: now.addingTimeInterval(6 * 86_400), durationSeconds: 7 * 86_400
            ))
        }
        let snapshot = UsageSnapshot(
            windows: [UsageWindow(id: "weekly", kind: .weekly, usedPercent: 60)],
            additionalWindows: namedWindows
        )
        let hidden = QuotaProgressPresentation(snapshot: snapshot, error: nil, now: now)

        XCTAssertEqual(hidden.quotaWindows.map(\.title), ["Weekly", "Codex Sparkle", "GPT-6 Luna"])
        XCTAssertEqual(hidden.quotaValue, "40%")
        XCTAssertEqual(snapshot.additionalWindows.count, namedWindows.count)

        let hiddenLabels = textValues(in: QuotaProgressMenuView(presentation: hidden))
        for (_, title) in sparkNames {
            XCTAssertFalse(hiddenLabels.contains("\(title) remaining"))
        }
    }

    func testProgressMenuDoesNotRenderSparkQuotaOrPaceLabels() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let spark = UsageWindow(
            id: "codex-spark",
            kind: .rolling(hours: 5),
            usedPercent: 25,
            resetAt: now.addingTimeInterval(2.5 * 3_600),
            durationSeconds: 5 * 3_600
        )
        let view = QuotaProgressMenuView(
            presentation: QuotaProgressPresentation(
                snapshot: UsageSnapshot(
                    windows: [],
                    additionalWindows: [NamedUsageWindow(
                        id: spark.id,
                        title: "Codex Spark 5-hour",
                        window: spark
                    )]
                ),
                error: nil,
                now: now
            )
        )

        let values = textValues(in: view)
        XCTAssertFalse(values.contains("Codex Spark 5-hour remaining"))
        XCTAssertFalse(values.contains("25% in reserve"))
    }

    func testPlanDisplayUsesNormalizedNameAndNeverExposesUnknownValues() {
        let known = QuotaProgressPresentation(
            snapshot: UsageSnapshot(plan: .proLite, windows: []),
            error: nil,
            now: .now
        )
        let missing = QuotaProgressPresentation(
            snapshot: UsageSnapshot(windows: []),
            error: nil,
            now: .now
        )

        XCTAssertEqual(known.planValue, "Pro Lite")
        XCTAssertEqual(missing.planValue, "Unavailable")
    }

    func testResetProgressIsClampedAndUnavailableDataIsNotFabricated() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let expired = UsageSnapshot(
            windows: [
                UsageWindow(
                    id: "weekly",
                    kind: .weekly,
                    usedPercent: 50,
                    resetAt: now.addingTimeInterval(-60),
                    durationSeconds: 604_800
                )
            ]
        )
        let missingDuration = UsageSnapshot(
            windows: [
                UsageWindow(
                    id: "weekly",
                    kind: .weekly,
                    usedPercent: 50,
                    resetAt: now.addingTimeInterval(60)
                )
            ]
        )

        XCTAssertEqual(
            QuotaProgressPresentation(snapshot: expired, error: nil, now: now).resetProgress,
            0
        )
        let unavailable = QuotaProgressPresentation(snapshot: missingDuration, error: nil, now: now)
        XCTAssertNil(unavailable.resetProgress)
        XCTAssertEqual(unavailable.resetValue, "Unavailable")
    }

    func testProgressMenuViewContainsTwoNativeProgressIndicators() {
        let presentation = QuotaProgressPresentation(snapshot: nil, error: nil, now: .now)
        let view = QuotaProgressMenuView(presentation: presentation)
        let progressBars = progressIndicators(in: view)

        XCTAssertEqual(progressBars.count, 2)
        XCTAssertTrue(progressBars.allSatisfy { $0 is NeutralProgressIndicator })
        XCTAssertEqual(NeutralProgressIndicator.fillColor, .secondaryLabelColor)
        XCTAssertEqual(NeutralProgressIndicator.trackColor, .separatorColor)
        XCTAssertEqual(view.frame.size.width, QuotaProgressMenuView.width)
        assertContentFits(view)
        XCTAssertTrue(textValues(in: view).contains("Plan"))
        XCTAssertTrue(textValues(in: view).contains("Unavailable"))
    }

    func testProgressMenuShowsCreditsRemainingOnlyWhenAvailable() {
        let visible = QuotaProgressMenuView(
            presentation: QuotaProgressPresentation(
                snapshot: UsageSnapshot(creditsRemaining: .balance("-1.25"), windows: []),
                error: nil,
                now: .now
            )
        )
        let hidden = QuotaProgressMenuView(
            presentation: QuotaProgressPresentation(
                snapshot: UsageSnapshot(windows: []),
                error: nil,
                now: .now
            )
        )

        XCTAssertTrue(textValues(in: visible).contains("Credits remaining"))
        XCTAssertTrue(textValues(in: visible).contains("-1.25"))
        XCTAssertFalse(textValues(in: hidden).contains("Credits remaining"))
        XCTAssertGreaterThan(visible.frame.height, hidden.frame.height)
        assertContentFits(visible)
        assertContentFits(hidden)
    }

    func testProgressPresentationShowsUnlimitedCredits() {
        let presentation = QuotaProgressPresentation(
            snapshot: UsageSnapshot(creditsRemaining: .unlimited, windows: []),
            error: nil,
            now: .now
        )

        XCTAssertEqual(presentation.creditsRemainingValue, "Unlimited")
    }

    func testResetCreditsShowAvailableCountIncludingZeroAndHideWhenMissing() {
        let twoCredits = UsageSnapshot(windows: [], availableResetCredits: 2)
        let zeroCredits = UsageSnapshot(windows: [], availableResetCredits: 0)
        let missingCredits = UsageSnapshot(windows: [])

        XCTAssertEqual(
            QuotaProgressPresentation(snapshot: twoCredits, error: nil, now: .now).resetCreditsValue,
            "2 available"
        )
        XCTAssertEqual(
            QuotaProgressPresentation(snapshot: zeroCredits, error: nil, now: .now).resetCreditsValue,
            "0 available"
        )
        XCTAssertNil(
            QuotaProgressPresentation(snapshot: missingCredits, error: nil, now: .now).resetCreditsValue
        )
    }

    func testResetCreditExpiryUsesLocalDateAndKeepsWeeklyResetSeparate() {
        let expiry = Date(timeIntervalSince1970: 1_893_561_045)
        let oneCredit = UsageSnapshot(
            windows: [],
            availableResetCredits: 1,
            nextResetCreditExpiry: expiry
        )
        let multipleCredits = UsageSnapshot(
            windows: [],
            availableResetCredits: 2,
            nextResetCreditExpiry: expiry
        )

        XCTAssertTrue(
            QuotaProgressPresentation(snapshot: oneCredit, error: nil, now: .now)
                .resetCreditsDetail?
                .hasPrefix("Expires: ") == true
        )
        XCTAssertTrue(
            QuotaProgressPresentation(snapshot: multipleCredits, error: nil, now: .now)
                .resetCreditsDetail?
                .hasPrefix("Next expires: ") == true
        )
        XCTAssertNil(MenuBarText.resetLine(snapshot: oneCredit))
    }

    func testResetCreditExpiryIsHiddenWithoutAPositiveCount() {
        let expiry = Date(timeIntervalSince1970: 1_893_561_045)

        XCTAssertNil(
            QuotaProgressPresentation(
                snapshot: UsageSnapshot(windows: [], nextResetCreditExpiry: expiry),
                error: nil,
                now: .now
            ).resetCreditsDetail
        )
        XCTAssertNil(
            QuotaProgressPresentation(
                snapshot: UsageSnapshot(
                    windows: [],
                    availableResetCredits: 0,
                    nextResetCreditExpiry: expiry
                ),
                error: nil,
                now: .now
            ).resetCreditsDetail
        )
    }

    func testResetCreditProgressUsesExactGrantToExpiryDuration() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let snapshot = UsageSnapshot(
            windows: [],
            availableResetCredits: 1,
            nextResetCreditGrantedAt: now.addingTimeInterval(-10 * 24 * 60 * 60),
            nextResetCreditExpiry: now.addingTimeInterval(20 * 24 * 60 * 60)
        )

        let presentation = QuotaProgressPresentation(snapshot: snapshot, error: nil, now: now)

        XCTAssertEqual(try XCTUnwrap(presentation.resetCreditsProgress), 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(
            QuotaProgressPresentation(
                snapshot: snapshot,
                error: nil,
                now: now.addingTimeInterval(21 * 24 * 60 * 60)
            ).resetCreditsProgress,
            0
        )
    }

    func testResetCreditProgressDoesNotAssumeMissingOrInvalidDuration() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let missingGrant = UsageSnapshot(
            windows: [],
            availableResetCredits: 1,
            nextResetCreditExpiry: now.addingTimeInterval(60)
        )
        let invalidDuration = UsageSnapshot(
            windows: [],
            availableResetCredits: 1,
            nextResetCreditGrantedAt: now.addingTimeInterval(120),
            nextResetCreditExpiry: now.addingTimeInterval(60)
        )

        XCTAssertNil(
            QuotaProgressPresentation(snapshot: missingGrant, error: nil, now: now).resetCreditsProgress
        )
        XCTAssertNil(
            QuotaProgressPresentation(snapshot: invalidDuration, error: nil, now: now).resetCreditsProgress
        )
    }

    func testProgressMenuShowsResetCreditsRowOnlyWhenAvailable() {
        let visiblePresentation = QuotaProgressPresentation(
            snapshot: UsageSnapshot(windows: [], availableResetCredits: 2),
            error: nil,
            now: .now
        )
        let hiddenPresentation = QuotaProgressPresentation(
            snapshot: UsageSnapshot(windows: []),
            error: nil,
            now: .now
        )

        let visibleView = QuotaProgressMenuView(presentation: visiblePresentation)
        let hiddenView = QuotaProgressMenuView(presentation: hiddenPresentation)

        XCTAssertTrue(textValues(in: visibleView).contains("Reset credits"))
        XCTAssertTrue(textValues(in: visibleView).contains("2 available"))
        XCTAssertFalse(textValues(in: hiddenView).contains("Reset credits"))
        XCTAssertGreaterThan(visibleView.frame.height, hiddenView.frame.height)
        assertContentFits(visibleView)
    }

    func testProgressMenuShowsResetCreditExpiryWhenAvailable() {
        let presentation = QuotaProgressPresentation(
            snapshot: UsageSnapshot(
                windows: [],
                availableResetCredits: 1,
                nextResetCreditGrantedAt: Date(timeIntervalSince1970: 1_890_969_045),
                nextResetCreditExpiry: Date(timeIntervalSince1970: 1_893_561_045)
            ),
            error: nil,
            now: .now
        )

        let view = QuotaProgressMenuView(presentation: presentation)
        let progressBars = progressIndicators(in: view)

        XCTAssertTrue(textValues(in: view).contains { $0.hasPrefix("Expires: ") })
        XCTAssertEqual(progressBars.count, 3)
        XCTAssertEqual(
            progressBars.last?.toolTip,
            "Time remaining until next reset credit expires"
        )
        assertContentFits(view)
    }

    func testAnalyticsSectionChangeRemovesUnusedVerticalSpace() throws {
        let usage = UsageAnalyticsPresentation(projection: makeAnalyticsProjection(
            totalTokens: 100, inputTokens: 20, cachedInputTokens: 30,
            outputTokens: 50, turns: 4, chats: 2
        ))
        let view = UsageAnalyticsMenuView(
            usagePresentation: usage, lifetimePresentation: nil,
            selectedSection: .days30, onSelect: { _ in }
        )
        let fullHeight = view.frame.height
        assertContentFits(view)
        let selector = try XCTUnwrap(segmentedControls(in: view).first)
        selector.selectedSegment = MenuAnalyticsSection.lifetime.rawValue
        selector.sendAction(selector.action, to: selector.target)
        XCTAssertLessThan(view.frame.height, fullHeight)
        assertContentFits(view)
        selector.selectedSegment = MenuAnalyticsSection.days30.rawValue
        selector.sendAction(selector.action, to: selector.target)
        XCTAssertEqual(view.frame.height, fullHeight)
        assertContentFits(view)
    }

    private func assertContentFits(_ view: MenuContentView, file: StaticString = #filePath, line: UInt = #line) {
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.stack.frame.minY, MenuContentView.verticalInset, accuracy: 1, file: file, line: line)
        XCTAssertEqual(view.frame.height - view.stack.frame.maxY, MenuContentView.verticalInset, accuracy: 1, file: file, line: line)
    }

    private func progressIndicators(in view: NSView) -> [NSProgressIndicator] {
        view.subviews.flatMap { child in
            (child as? NSProgressIndicator).map { [$0] } ?? progressIndicators(in: child)
        }
    }

    private func segmentedControls(in view: NSView) -> [NSSegmentedControl] {
        view.subviews.flatMap { child in
            (child as? NSSegmentedControl).map { [$0] } ?? segmentedControls(in: child)
        }
    }

    private func visibleTextValues(in view: NSView) -> [String] {
        guard !view.isHidden else { return [] }
        return view.subviews.flatMap { child in
            (child as? NSTextField).map { [$0.stringValue] } ?? visibleTextValues(in: child)
        }
    }

    private func makeLifetimePresentation() -> LifetimeAnalyticsPresentation {
        LifetimeAnalyticsPresentation(
            model: LifetimeDashboardModel(profile: makeLifetimeProfile())
        )
    }

    private func makeLifetimeProfile() -> CodexProfileStats {
        CodexProfileStats(
            lifetimeTokens: 30_300_000_000,
            peakDailyTokens: 1_100_000_000,
            longestRunningTurnSeconds: 56_580,
            currentStreakDays: 42,
            longestStreakDays: 82,
            dailyBuckets: [],
            insights: CodexProfileInsights(
                fastModePercent: nil,
                reasoningEffort: nil,
                reasoningEffortPercent: nil,
                uniqueSkillsUsed: nil,
                totalSkillsUsed: nil,
                totalChats: nil
            ),
            invocations: [],
            fetchedAt: Date(timeIntervalSince1970: 1_776_326_400)
        )
    }

    private func makeAnalyticsProjection(
        totalTokens: Int64,
        inputTokens: Int64,
        cachedInputTokens: Int64,
        outputTokens: Int64,
        turns: Int64,
        chats: Int64
    ) -> UsageAnalyticsProjection {
        let dataset = makeAnalyticsDataset(
            totalTokens: totalTokens,
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens,
            turns: turns,
            chats: chats
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return UsageAnalyticsProjection.make(
            dataset: dataset,
            range: .days30,
            referenceDate: dataset.requestedEnd,
            calendar: calendar
        )!
    }

    private func makeAnalyticsDataset(
        totalTokens: Int64,
        inputTokens: Int64,
        cachedInputTokens: Int64,
        outputTokens: Int64,
        turns: Int64,
        chats: Int64
    ) -> UsageAnalyticsDataset {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let end = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))!
        let start = calendar.date(byAdding: .day, value: -364, to: end)!
        let day = UsageAnalyticsDay(
            date: end,
            totals: UsageTokenTotals(
                totalTokens: totalTokens,
                uncachedInputTokens: inputTokens,
                cachedInputTokens: cachedInputTokens,
                outputTokens: outputTokens,
                turns: turns,
                chats: chats
            ),
            models: [],
            clients: []
        )
        return UsageAnalyticsDataset(
            requestedStart: start,
            requestedEnd: end,
            days: [day],
            fetchedAt: end,
            modelBreakdownIsPartial: false,
            clientBreakdownIsPartial: false
        )
    }

    private func textValues(in view: NSView) -> [String] {
        view.subviews.flatMap { child in
            (child as? NSTextField).map { [$0.stringValue] } ?? textValues(in: child)
        }
    }
}

private final class BlockingCredentialsReader: CredentialsReading, @unchecked Sendable {
    let started = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)

    func read() throws -> CodexCredentials {
        started.signal()
        release.wait()
        throw CodexAuthError.authFileUnavailable
    }
}

private actor MenuAccountServiceFake: CodexAccountServing {
    func fetchQuota(fetchedAt: Date) async throws -> UsageSnapshot {
        UsageSnapshot(windows: [], fetchedAt: fetchedAt, source: .appServer)
    }

    func fetchProfile(fetchedAt: Date) async throws -> CodexProfileStats {
        throw CodexAccountServiceError.unavailable
    }

    func consumeReset(
        idempotencyKey: String,
        creditID: String?
    ) async throws -> AppServerResetOutcome {
        .reset
    }

    func rateLimitUpdates() async throws -> AsyncStream<AppServerRateLimitSnapshot> {
        AsyncStream { $0.finish() }
    }

    func stop() async {}
}
