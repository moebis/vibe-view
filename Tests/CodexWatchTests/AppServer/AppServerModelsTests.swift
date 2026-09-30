import Foundation
import XCTest
@testable import CodexWatch

final class AppServerModelsTests: XCTestCase {
    func testNonChatGPTAccountShapesRemainRecognizableWithoutCredentialDetails() throws {
        let shapes = [
            #"{"type":"amazonBedrock","usesCodexManagedCredentials":true}"#,
            #"{"type":"amazonBedrock"}"#,
            #"{"type":"amazonBedrock","credentialSource":"codexManaged"}"#,
            #"{"type":"amazonBedrock","credentialSource":"awsManaged"}"#
        ]
        for shape in shapes {
            let account = try JSONDecoder().decode(AppServerAccount.self, from: Data(shape.utf8))
            XCTAssertEqual(account, .amazonBedrock)
        }
        let unknown = try JSONDecoder().decode(
            AppServerAccount.self, from: Data(#"{"type":"futureProvider","privateField":"ignored"}"#.utf8)
        )
        XCTAssertEqual(unknown, .unsupported)
        XCTAssertThrowsError(try JSONDecoder().decode(
            AppServerAccount.self, from: Data(#"{"type":"chatgpt","planType":false}"#.utf8)
        ))
    }

    func testEveryCodex01510PlanVariantDecodes() throws {
        let rawValues = [
            "free", "go", "plus", "pro", "prolite", "team",
            "self_serve_business_prolite", "self_serve_business_usage_based",
            "business", "ent26", "enterprise_cbp_automation",
            "enterprise_cbp_usage_based", "enterprise", "edu", "edu_plus",
            "edu_pro", "unknown"
        ]

        let decoded = try rawValues.map { rawValue in
            try JSONDecoder().decode(
                AppServerPlanType.self,
                from: Data("\"\(rawValue)\"".utf8)
            )
        }

        XCTAssertEqual(decoded.map(\.rawValue), rawValues)
        XCTAssertEqual(Set(decoded), Set(AppServerPlanType.allCases))
    }

    func testRateLimitsIgnoreUnknownFieldsAndDecodeCurrentSurfaces() throws {
        let data = Data(
            #"""
            {
              "rateLimits": {
                "limitId": "codex",
                "limitName": "Codex",
                "primary": {"usedPercent": 12, "windowDurationMins": 300, "resetsAt": 4100, "future": true},
                "secondary": {"usedPercent": 25, "windowDurationMins": 10080, "resetsAt": 4200},
                "credits": {"hasCredits": true, "unlimited": false, "balance": "7.25"},
                "individualLimit": {"limit": "10", "used": "2", "remainingPercent": 80, "resetsAt": 4300},
                "spendControlReached": false,
                "planType": "self_serve_business_usage_based",
                "rateLimitReachedType": "workspace_member_usage_limit_reached",
                "futureTopLevel": {"value": 1}
              },
              "rateLimitsByLimitId": {},
              "rateLimitResetCredits": {
                "availableCount": 1,
                "credits": [{
                  "id": "credit-one",
                  "resetType": "codexRateLimits",
                  "status": "available",
                  "grantedAt": 4000,
                  "expiresAt": 5000,
                  "title": "Reset",
                  "description": null,
                  "future": "ignored"
                }]
              },
              "futureResponseField": 99
            }
            """#.utf8
        )

        let response = try JSONDecoder().decode(AppServerRateLimitsResponse.self, from: data)

        XCTAssertEqual(response.rateLimits.primary?.usedPercent, 12)
        XCTAssertEqual(response.rateLimits.secondary?.windowDurationMinutes, 10_080)
        XCTAssertEqual(response.rateLimits.credits?.balance, "7.25")
        XCTAssertEqual(response.rateLimits.individualLimit?.remainingPercent, 80)
        XCTAssertEqual(response.rateLimits.planType, .selfServeBusinessUsageBased)
        XCTAssertEqual(
            response.rateLimits.reachedReason,
            .workspaceMemberUsageLimitReached
        )
        XCTAssertEqual(response.resetCredits?.availableCount, 1)
        XCTAssertEqual(response.resetCredits?.credits?.first?.id, "credit-one")
    }

    func testAccountUsageDecodesLifetimeAndDailyBucketsButNotPerThreadUsage() throws {
        let data = Data(
            #"""
            {
              "summary": {
                "lifetimeTokens": 30300000000,
                "peakDailyTokens": 123456,
                "longestRunningTurnSec": 900,
                "currentStreakDays": 4,
                "longestStreakDays": 12
              },
              "dailyUsageBuckets": [
                {"startDate": "2026-08-29", "tokens": 1000},
                {"startDate": "2026-08-30", "tokens": 2000}
              ],
              "threadUsage": {
                "threadId": "must-not-be-retained",
                "estimatedUsageCreditsMicros": 1,
                "groups": []
              },
              "future": true
            }
            """#.utf8
        )

        let response = try JSONDecoder().decode(AppServerAccountUsageResponse.self, from: data)

        XCTAssertEqual(response.summary.lifetimeTokens, 30_300_000_000)
        XCTAssertEqual(response.summary.peakDailyTokens, 123_456)
        XCTAssertEqual(response.summary.longestRunningTurnSeconds, 900)
        XCTAssertEqual(response.dailyUsageBuckets?.map(\.tokens), [1_000, 2_000])
    }

    func testFutureOptionalEnumValuesFailClosedWithoutDiscardingQuota() throws {
        let data = Data(
            #"""
            {
              "rateLimits": {
                "limitId": "codex",
                "limitName": null,
                "primary": {"usedPercent": 12, "windowDurationMins": 300, "resetsAt": null},
                "secondary": null,
                "credits": null,
                "individualLimit": null,
                "spendControlReached": null,
                "planType": "future_plan",
                "rateLimitReachedType": "future_reason"
              },
              "rateLimitsByLimitId": null,
              "rateLimitResetCredits": {
                "availableCount": 1,
                "credits": [{
                  "id": "credit-one",
                  "resetType": "future_type",
                  "status": "future_status",
                  "grantedAt": 4000,
                  "expiresAt": null,
                  "title": null,
                  "description": null
                }]
              }
            }
            """#.utf8
        )

        let response = try JSONDecoder().decode(AppServerRateLimitsResponse.self, from: data)

        XCTAssertEqual(response.rateLimits.primary?.usedPercent, 12)
        XCTAssertEqual(response.rateLimits.planType, .unknown)
        XCTAssertEqual(response.rateLimits.reachedReason, .unknown)
        XCTAssertEqual(response.resetCredits?.credits?.first?.resetType, .unknown)
        XCTAssertEqual(response.resetCredits?.credits?.first?.status, .unknown)
    }
}
