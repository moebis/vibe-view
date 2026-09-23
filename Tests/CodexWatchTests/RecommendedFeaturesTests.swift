import Foundation
import XCTest
@testable import CodexWatch

@MainActor
final class RecommendedFeaturesTests: XCTestCase {
    func testQuotaNotificationsFireOnceAtEachCrossedThresholdAndResetForANewWindow() {
        var policy = QuotaNotificationPolicy()

        XCTAssertEqual(policy.consume(remainingPercent: 24, isFresh: true)?.threshold, 25)
        XCTAssertNil(policy.consume(remainingPercent: 20, isFresh: true))
        XCTAssertEqual(policy.consume(remainingPercent: 9, isFresh: true)?.threshold, 10)
        XCTAssertEqual(policy.consume(remainingPercent: 4, isFresh: true)?.threshold, 5)
        XCTAssertEqual(policy.consume(remainingPercent: 0, isFresh: true)?.threshold, 0)
        XCTAssertNil(policy.consume(remainingPercent: 0, isFresh: true))

        XCTAssertNil(policy.consume(remainingPercent: 80, isFresh: true))
        XCTAssertNil(policy.consume(remainingPercent: 24, isFresh: true))
        XCTAssertEqual(policy.consume(
            remainingPercent: 24, isFresh: true,
            windowResetAt: Date(timeIntervalSince1970: 2_000)
        )?.threshold, 25)
    }

    func testCorrectionDoesNotRepeatThresholdInTheSameWindow() {
        var policy = QuotaNotificationPolicy()
        let reset = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(policy.consume(remainingPercent: 24, isFresh: true, windowResetAt: reset)?.threshold, 25)
        XCTAssertNil(policy.consume(remainingPercent: 26, isFresh: true, windowResetAt: reset))
        XCTAssertNil(policy.consume(remainingPercent: 24, isFresh: true, windowResetAt: reset))
        XCTAssertEqual(policy.consume(remainingPercent: 9, isFresh: true, windowResetAt: reset)?.threshold, 10)
    }

    func testQuotaNotificationsIgnoreStaleOrUnavailableQuota() {
        var policy = QuotaNotificationPolicy()

        XCTAssertNil(policy.consume(remainingPercent: nil, isFresh: true))
        XCTAssertNil(policy.consume(remainingPercent: 4, isFresh: false))
        XCTAssertEqual(policy.consume(remainingPercent: 4, isFresh: true)?.threshold, 5)
    }

    func testQuotaNotificationsRecognizeANewWindowEvenWhenItStartsLow() {
        var policy = QuotaNotificationPolicy()
        let firstReset = Date(timeIntervalSince1970: 1_000)
        let nextReset = Date(timeIntervalSince1970: 2_000)

        XCTAssertEqual(
            policy.consume(remainingPercent: 4, isFresh: true, windowResetAt: firstReset)?.threshold,
            5
        )
        XCTAssertNil(policy.consume(
            remainingPercent: 20,
            isFresh: true,
            windowResetAt: firstReset
        ))
        XCTAssertEqual(
            policy.consume(remainingPercent: 20, isFresh: true, windowResetAt: nextReset)?.threshold,
            25
        )
    }

    func testQuotaNotificationCopyDoesNotExposeThePrivateQuotaValue() {
        var policy = QuotaNotificationPolicy()
        let decision = policy.consume(remainingPercent: 9.4, isFresh: true)

        XCTAssertEqual(decision?.identifier, "codex-watch-weekly-10")
        XCTAssertEqual(decision?.title, "Codex weekly quota is low")
        XCTAssertEqual(decision?.body, "Open Codex Watch to review the remaining quota.")
    }

    func testNotificationPreferenceDefaultsOffAndPersistsExplicitChoice() {
        let suiteName = "RecommendedFeaturesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(FeaturePreferences.notificationsEnabled(in: defaults))
        FeaturePreferences.setNotificationsEnabled(true, in: defaults)
        XCTAssertTrue(FeaturePreferences.notificationsEnabled(in: defaults))
    }

    func testSafeDiagnosticsReportsOnlyOperationalState() {
        let diagnostics = SafeDiagnostics(
            version: "1.2.2",
            dataSource: .appServer,
            quota: .current,
            usage: .stale,
            lifetime: .unavailable,
            notificationsEnabled: true,
            launchAtLoginEnabled: false
        ).text

        XCTAssertEqual(diagnostics, """
        Codex Watch 1.2.2
        Quota source: Codex App Server
        Quota: current
        Usage analytics: stale
        Lifetime: unavailable
        Notifications: enabled
        Launch at Login: disabled
        """)
        XCTAssertFalse(diagnostics.localizedCaseInsensitiveContains("token"))
        XCTAssertFalse(diagnostics.contains("/Users/"))
        XCTAssertFalse(diagnostics.localizedCaseInsensitiveContains("account"))
    }

    func testNotificationControllerEnablesOnlyAfterAuthorizationAndDeliversPolicyDecision() async {
        let delivery = NotificationDeliveryFake(authorizationGranted: true)
        let controller = QuotaNotificationController(delivery: delivery)

        let enabled = await controller.requestEnable()
        XCTAssertTrue(enabled)
        await controller.consider(remainingPercent: 24, isFresh: true)
        await controller.consider(remainingPercent: 20, isFresh: true)

        let delivered = await delivery.delivered()
        XCTAssertEqual(delivered, [
            QuotaNotificationDecision(
                threshold: 25,
                identifier: "codex-watch-weekly-25",
                title: "Codex weekly quota is low",
                body: "Open Codex Watch to review the remaining quota."
            )
        ])
    }

    func testNotificationControllerStaysDisabledWhenAuthorizationIsDenied() async {
        let delivery = NotificationDeliveryFake(authorizationGranted: false)
        let controller = QuotaNotificationController(delivery: delivery)

        let enabled = await controller.requestEnable()
        XCTAssertFalse(enabled)
        await controller.consider(remainingPercent: 4, isFresh: true)

        let delivered = await delivery.delivered()
        XCTAssertEqual(delivered, [])
    }

    func testLaunchAtLoginSettingChangesTheSystemServiceState() throws {
        let service = LaunchAtLoginServiceFake(isEnabled: false)
        let setting = LaunchAtLoginSetting(service: service)

        XCTAssertFalse(setting.isEnabled)
        try setting.setEnabled(true)
        XCTAssertTrue(setting.isEnabled)
        try setting.setEnabled(false)
        XCTAssertFalse(setting.isEnabled)
    }

    func testResetCreditRetryReusesIdempotencyKeyUntilAnExactOutcome() {
        var state = ResetCreditRedemptionState()

        let first = state.request(creditID: "credit-1", makeKey: { "key-1" })
        let retry = state.request(creditID: "credit-2", makeKey: { "key-2" })

        XCTAssertEqual(first, PendingResetRedemption(idempotencyKey: "key-1", creditID: "credit-1"))
        XCTAssertEqual(retry, first)
        state.complete(outcome: .reset)
        XCTAssertNil(state.pending)
        XCTAssertEqual(
            state.request(creditID: "credit-2", makeKey: { "key-2" }),
            PendingResetRedemption(idempotencyKey: "key-2", creditID: "credit-2")
        )
    }

    func testResetCreditOutcomeCopyIsExplicit() {
        XCTAssertEqual(ResetCreditRedemptionState.message(for: .reset), "Weekly quota was reset.")
        XCTAssertEqual(
            ResetCreditRedemptionState.message(for: .alreadyRedeemed),
            "This reset credit was already used. Quota has been refreshed."
        )
        XCTAssertEqual(
            ResetCreditRedemptionState.message(for: .nothingToReset),
            "There is no exhausted quota to reset."
        )
        XCTAssertEqual(
            ResetCreditRedemptionState.message(for: .noCredit),
            "No reset credit is available."
        )
    }
}

private actor NotificationDeliveryFake: QuotaNotificationDelivering {
    private let authorizationGranted: Bool
    private var decisions: [QuotaNotificationDecision] = []

    init(authorizationGranted: Bool) {
        self.authorizationGranted = authorizationGranted
    }

    func requestAuthorization() async -> Bool {
        authorizationGranted
    }

    func deliver(_ decision: QuotaNotificationDecision) async throws {
        decisions.append(decision)
    }

    func delivered() -> [QuotaNotificationDecision] {
        decisions
    }
}

@MainActor
private final class LaunchAtLoginServiceFake: LaunchAtLoginServicing {
    var isEnabled: Bool

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ enabled: Bool) throws {
        isEnabled = enabled
    }
}
