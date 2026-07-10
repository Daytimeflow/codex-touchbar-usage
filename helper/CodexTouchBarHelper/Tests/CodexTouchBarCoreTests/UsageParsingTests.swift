@testable import CodexTouchBarCore
import XCTest

final class UsageParsingTests: XCTestCase {
    func testAPIUsageShapeNormalizesToBalanceWindows() {
        let store = UsageStore()
        let raw: JSONObject = [
            "plan_type": "plus",
            "rate_limit": [
                "primary_window": [
                    "used_percent": 7,
                    "limit_window_seconds": 18_000,
                    "reset_at": 1_800_000_000
                ],
                "secondary_window": [
                    "used_percent": 63,
                    "limit_window_seconds": 604_800,
                    "reset_at": 1_800_010_000
                ]
            ],
            "token_info": [
                "total_token_usage": ["total_tokens": 6_400_000_000],
                "last_token_usage": ["total_tokens": 1_200]
            ],
            "token_stats": [
                "yesterday_tokens": 81_210_000,
                "cumulative_tokens": 6_400_000_000
            ],
            "profile_usage": [
                "units": "percent",
                "data": [
                    [
                        "date": "2026-06-22",
                        "product_surface_usage_values": [
                            "desktop_app": 11.4,
                            "cli": 0
                        ]
                    ],
                    [
                        "date": dayKey(for: Calendar.current.date(byAdding: .day, value: -1, to: Date())!),
                        "product_surface_usage_values": [
                            "desktop_app": 21.041,
                            "cli": 1.2
                        ]
                    ]
                ]
            ]
        ]

        let snapshot = store.normalizeUsage(raw, source: "test")

        XCTAssertEqual(snapshot.primary?.windowMinutes, 300)
        XCTAssertEqual(snapshot.secondary?.windowMinutes, 10_080)
        XCTAssertEqual(UsageFormatting.balanceLabel(usedPercent: snapshot.primary?.usedPercent), "93%")
        XCTAssertEqual(UsageFormatting.balanceLabel(usedPercent: snapshot.secondary?.usedPercent), "37%")
        XCTAssertEqual(UsageFormatting.tokenRows(snapshot).0, "昨日 8121万")
        XCTAssertEqual(UsageFormatting.tokenRows(snapshot).1, "累计 64亿")
    }

    func testTokenRowsFallBackToLocalTokenStatsWhenProfileUsageIsMissing() {
        let store = UsageStore()
        let raw: JSONObject = [
            "rate_limit": [
                "primary_window": [
                    "used_percent": 7,
                    "limit_window_seconds": 18_000,
                    "reset_at": 1_800_000_000
                ]
            ],
            "token_info": [
                "total_token_usage": ["total_tokens": 6_400_000_000]
            ],
            "token_stats": [
                "yesterday_tokens": 81_210_000,
                "cumulative_tokens": 6_400_000_000
            ]
        ]

        let snapshot = store.normalizeUsage(raw, source: "test")

        XCTAssertEqual(UsageFormatting.tokenRows(snapshot).0, "昨日 8121万")
        XCTAssertEqual(UsageFormatting.tokenRows(snapshot).1, "累计 64亿")
    }

    func testSessionUsageShapeStillWorks() {
        let store = UsageStore()
        let raw: JSONObject = [
            "rate_limits": [
                "primary": [
                    "used_percent": 4,
                    "window_minutes": 300,
                    "resets_at": 1_800_000_000
                ],
                "secondary": [
                    "used_percent": 62,
                    "window_minutes": 10_080,
                    "resets_at": 1_800_010_000
                ],
                "plan_type": "pro"
            ]
        ]

        let snapshot = store.normalizeUsage(raw, source: "test")

        XCTAssertEqual(snapshot.planType, "pro")
        XCTAssertEqual(UsageFormatting.balanceLabel(usedPercent: snapshot.primary?.usedPercent), "96%")
        XCTAssertEqual(UsageFormatting.balanceLabel(usedPercent: snapshot.secondary?.usedPercent), "38%")
    }

    func testAllZeroUsageIsTreatedAsSuspicious() {
        let store = UsageStore()
        let raw: JSONObject = [
            "rate_limits": [
                "primary": [
                    "used_percent": 0,
                    "window_minutes": 300,
                    "resets_at": 1_800_000_000
                ],
                "secondary": [
                    "used_percent": 0,
                    "window_minutes": 10_080,
                    "resets_at": 1_800_010_000
                ]
            ]
        ]

        let snapshot = store.normalizeUsage(raw, source: "test")

        XCTAssertTrue(store.isAllZeroUsage(snapshot))
    }

    func testLocalTokenMergePreservesOfficialAccountTotalsAndRemoteQuotaWindows() {
        let remote = UsageSnapshot(
            primary: LimitWindow(name: "primary", usedPercent: 3, windowMinutes: 300, resetsAt: 1_800_000_000),
            secondary: LimitWindow(name: "secondary", usedPercent: 77, windowMinutes: 10_080, resetsAt: 1_800_010_000),
            contextWindow: nil,
            totalTokens: 100,
            lastTokens: 10,
            yesterdayTokens: 1_000,
            cumulativeTokens: 10_000,
            inputTokens: nil,
            outputTokens: nil,
            tokenUsageSource: "account",
            planType: "prolite",
            source: "remote",
            fetchedAt: 1_700_000_000
        )
        let historicalSession = UsageSnapshot(
            primary: LimitWindow(name: "primary", usedPercent: 41, windowMinutes: 300, resetsAt: 1_700_000_000),
            secondary: LimitWindow(name: "secondary", usedPercent: 12, windowMinutes: 10_080, resetsAt: 1_700_010_000),
            contextWindow: 258_400,
            totalTokens: 200,
            lastTokens: 20,
            yesterdayTokens: 2_000,
            cumulativeTokens: 20_000,
            inputTokens: 11,
            outputTokens: 9,
            planType: "old",
            source: "session",
            fetchedAt: 1_600_000_000
        )

        let merged = remote.mergingLocalTokenUsage(from: historicalSession)

        XCTAssertEqual(merged.primary, remote.primary)
        XCTAssertEqual(merged.secondary, remote.secondary)
        XCTAssertEqual(merged.planType, remote.planType)
        XCTAssertEqual(merged.source, remote.source)
        XCTAssertEqual(merged.fetchedAt, remote.fetchedAt)
        XCTAssertEqual(merged.contextWindow, 258_400)
        XCTAssertEqual(merged.totalTokens, 200)
        XCTAssertEqual(merged.lastTokens, 20)
        XCTAssertEqual(merged.yesterdayTokens, 1_000)
        XCTAssertEqual(merged.cumulativeTokens, 10_000)
        XCTAssertEqual(merged.inputTokens, 11)
        XCTAssertEqual(merged.outputTokens, 9)
        XCTAssertEqual(merged.tokenUsageSource, "account")
    }

    func testAppServerUsageMatchesAccountProfileShape() throws {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()).map { dayKey(for: $0) }!
        let raw = try CodexAppServerClient.combine(
            rateLimits: [
                "rateLimits": [
                    "primary": [
                        "usedPercent": 10,
                        "windowDurationMins": 300,
                        "resetsAt": 1_800_000_000
                    ],
                    "secondary": [
                        "usedPercent": 2,
                        "windowDurationMins": 10_080,
                        "resetsAt": 1_800_010_000
                    ],
                    "planType": "prolite"
                ]
            ],
            tokenUsage: [
                "summary": ["lifetimeTokens": 8_539_541_009],
                "dailyUsageBuckets": [
                    ["startDate": yesterday, "tokens": 18_797_368]
                ]
            ]
        )

        let snapshot = UsageStore().normalizeUsage(raw, source: "app-server")

        XCTAssertEqual(snapshot.primary?.usedPercent, 10)
        XCTAssertEqual(snapshot.secondary?.usedPercent, 2)
        XCTAssertEqual(snapshot.primary?.windowMinutes, 300)
        XCTAssertEqual(snapshot.secondary?.windowMinutes, 10_080)
        XCTAssertEqual(snapshot.yesterdayTokens, 18_797_368)
        XCTAssertEqual(snapshot.cumulativeTokens, 8_539_541_009)
        XCTAssertEqual(snapshot.tokenUsageSource, "account")
        XCTAssertEqual(snapshot.source, "app-server")
    }

    func testAppServerUsageOmitsAccountTotalsWhenProfileSummaryIsUnavailable() throws {
        let raw = try CodexAppServerClient.combine(
            rateLimits: [
                "rateLimits": [
                    "primary": [
                        "usedPercent": 10,
                        "windowDurationMins": 300,
                        "resetsAt": 1_800_000_000
                    ]
                ]
            ],
            tokenUsage: [:]
        )

        XCTAssertNil(raw["token_stats"])
        XCTAssertNotNil(raw["rate_limit"])
    }
}
