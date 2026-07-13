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

    func testAppServerUsageMapsNamedAdditionalLimitIntoSecondRow() throws {
        let mainLimit: JSONObject = [
            "limitId": "codex",
            "primary": [
                "usedPercent": 8,
                "windowDurationMins": 10_080,
                "resetsAt": 1_800_000_000
            ],
            "secondary": NSNull(),
            "planType": "pro"
        ]
        let sparkLimit: JSONObject = [
            "limitId": "codex_bengalfox",
            "limitName": "GPT-5.3-Codex-Spark",
            "primary": [
                "usedPercent": 0,
                "windowDurationMins": 10_080,
                "resetsAt": 1_800_010_000
            ],
            "secondary": NSNull(),
            "planType": "pro"
        ]
        let raw = try CodexAppServerClient.combine(
            rateLimits: [
                "rateLimits": mainLimit,
                "rateLimitsByLimitId": [
                    "codex": mainLimit,
                    "codex_bengalfox": sparkLimit
                ]
            ],
            tokenUsage: [:]
        )

        let snapshot = UsageStore().normalizeUsage(raw, source: "app-server")

        XCTAssertEqual(snapshot.primary?.name, "codex")
        XCTAssertEqual(snapshot.primary?.windowMinutes, 10_080)
        XCTAssertEqual(snapshot.primary?.usedPercent, 8)
        XCTAssertEqual(snapshot.secondary?.name, "GPT-5.3-Codex-Spark")
        XCTAssertEqual(snapshot.secondary?.windowMinutes, 10_080)
        XCTAssertEqual(snapshot.secondary?.usedPercent, 0)
        XCTAssertEqual(UsageFormatting.windowLabel(snapshot.primary), "1周")
        XCTAssertEqual(UsageFormatting.windowLabel(snapshot.secondary), "Spark")
    }

    func testHTTPUsageMapsAdditionalRateLimitIntoSecondRow() {
        let raw: JSONObject = [
            "plan_type": "pro",
            "rate_limit": [
                "primary_window": [
                    "used_percent": 8,
                    "limit_window_seconds": 604_800,
                    "reset_at": 1_800_000_000
                ],
                "secondary_window": NSNull()
            ],
            "additional_rate_limits": [
                [
                    "limit_name": "GPT-5.3-Codex-Spark",
                    "metered_feature": "codex_bengalfox",
                    "rate_limit": [
                        "primary_window": [
                            "used_percent": 0,
                            "limit_window_seconds": 604_800,
                            "reset_at": 1_800_010_000
                        ],
                        "secondary_window": NSNull()
                    ]
                ]
            ]
        ]

        let snapshot = UsageStore().normalizeUsage(raw, source: "remote")

        XCTAssertEqual(snapshot.primary?.windowMinutes, 10_080)
        XCTAssertEqual(snapshot.secondary?.name, "GPT-5.3-Codex-Spark")
        XCTAssertEqual(snapshot.secondary?.windowMinutes, 10_080)
        XCTAssertEqual(UsageFormatting.windowLabel(snapshot.primary), "1周")
        XCTAssertEqual(UsageFormatting.windowLabel(snapshot.secondary), "Spark")
    }

    func testAppServerRequestsDoNotForceRefreshAuthentication() {
        let methods = CodexAppServerClient.requestMessages().compactMap { stringValue($0["method"]) }

        XCTAssertFalse(methods.contains("account/read"))
        XCTAssertTrue(methods.contains("account/rateLimits/read"))
        XCTAssertTrue(methods.contains("account/usage/read"))
    }

    func testRemoteQuotaStabilizationRejectsRegressionWithinActiveWindow() {
        let current = UsageSnapshot(
            primary: LimitWindow(name: "primary", usedPercent: 30, windowMinutes: 300, resetsAt: 2_000),
            secondary: LimitWindow(name: "secondary", usedPercent: 5, windowMinutes: 10_080, resetsAt: 8_000),
            contextWindow: nil,
            totalTokens: nil,
            lastTokens: nil,
            yesterdayTokens: 100,
            cumulativeTokens: 1_000,
            inputTokens: nil,
            outputTokens: nil,
            tokenUsageSource: "account",
            planType: "pro",
            source: "app-server",
            fetchedAt: 1_000
        )
        let regressed = UsageSnapshot(
            primary: LimitWindow(name: "primary", usedPercent: 8, windowMinutes: 300, resetsAt: 2_001),
            secondary: LimitWindow(name: "secondary", usedPercent: 1, windowMinutes: 10_080, resetsAt: 8_000),
            contextWindow: nil,
            totalTokens: nil,
            lastTokens: nil,
            yesterdayTokens: 120,
            cumulativeTokens: 1_200,
            inputTokens: nil,
            outputTokens: nil,
            tokenUsageSource: "account",
            planType: "pro",
            source: "app-server",
            fetchedAt: 1_100
        )

        let stabilized = current.stabilizingQuota(from: regressed, now: 1_500)

        XCTAssertEqual(stabilized.primary?.usedPercent, current.primary?.usedPercent)
        XCTAssertEqual(stabilized.primary?.resetsAt, regressed.primary?.resetsAt)
        XCTAssertEqual(stabilized.secondary?.usedPercent, current.secondary?.usedPercent)
        XCTAssertEqual(stabilized.secondary?.resetsAt, regressed.secondary?.resetsAt)
        XCTAssertEqual(stabilized.yesterdayTokens, 120)
        XCTAssertEqual(stabilized.cumulativeTokens, 1_200)
        XCTAssertEqual(stabilized.fetchedAt, regressed.fetchedAt)
    }

    func testRemoteQuotaStabilizationRejectsPastResetCorrection() {
        let current = UsageSnapshot(
            primary: LimitWindow(name: "primary", usedPercent: 30, windowMinutes: 300, resetsAt: 2_000),
            secondary: nil,
            contextWindow: nil,
            totalTokens: nil,
            lastTokens: nil,
            yesterdayTokens: nil,
            cumulativeTokens: nil,
            inputTokens: nil,
            outputTokens: nil,
            tokenUsageSource: "account",
            planType: "pro",
            source: "app-server",
            fetchedAt: 1_000
        )
        let stale = UsageSnapshot(
            primary: LimitWindow(name: "primary", usedPercent: 8, windowMinutes: 300, resetsAt: 1_400),
            secondary: nil,
            contextWindow: nil,
            totalTokens: nil,
            lastTokens: nil,
            yesterdayTokens: nil,
            cumulativeTokens: nil,
            inputTokens: nil,
            outputTokens: nil,
            tokenUsageSource: "account",
            planType: "pro",
            source: "app-server",
            fetchedAt: 1_500
        )

        let stabilized = current.stabilizingQuota(from: stale, now: 1_500)

        XCTAssertEqual(stabilized.primary, current.primary)
    }

    func testRemoteQuotaStabilizationAcceptsRealResetAfterWindowExpires() {
        let current = UsageSnapshot(
            primary: LimitWindow(name: "primary", usedPercent: 98, windowMinutes: 300, resetsAt: 2_000),
            secondary: nil,
            contextWindow: nil,
            totalTokens: nil,
            lastTokens: nil,
            yesterdayTokens: nil,
            cumulativeTokens: nil,
            inputTokens: nil,
            outputTokens: nil,
            tokenUsageSource: "account",
            planType: "pro",
            source: "app-server",
            fetchedAt: 1_900
        )
        let reset = UsageSnapshot(
            primary: LimitWindow(name: "primary", usedPercent: 2, windowMinutes: 300, resetsAt: 20_000),
            secondary: nil,
            contextWindow: nil,
            totalTokens: nil,
            lastTokens: nil,
            yesterdayTokens: nil,
            cumulativeTokens: nil,
            inputTokens: nil,
            outputTokens: nil,
            tokenUsageSource: "account",
            planType: "pro",
            source: "app-server",
            fetchedAt: 2_100
        )

        let stabilized = current.stabilizingQuota(from: reset, now: 2_100)

        XCTAssertEqual(stabilized.primary, reset.primary)
    }

    func testRemoteQuotaStabilizationAcceptsNewCycleBeforeStaleResetExpires() {
        let current = UsageSnapshot(
            primary: LimitWindow(name: "primary", usedPercent: 90, windowMinutes: 300, resetsAt: 2_000),
            secondary: nil,
            contextWindow: nil,
            totalTokens: nil,
            lastTokens: nil,
            yesterdayTokens: nil,
            cumulativeTokens: nil,
            inputTokens: nil,
            outputTokens: nil,
            tokenUsageSource: "account",
            planType: "pro",
            source: "app-server",
            fetchedAt: 1_000
        )
        let reset = UsageSnapshot(
            primary: LimitWindow(name: "primary", usedPercent: 2, windowMinutes: 300, resetsAt: 20_000),
            secondary: nil,
            contextWindow: nil,
            totalTokens: nil,
            lastTokens: nil,
            yesterdayTokens: nil,
            cumulativeTokens: nil,
            inputTokens: nil,
            outputTokens: nil,
            tokenUsageSource: "account",
            planType: "pro",
            source: "app-server",
            fetchedAt: 1_500
        )

        let stabilized = current.stabilizingQuota(from: reset, now: 1_500)

        XCTAssertEqual(stabilized.primary, reset.primary)
    }

    func testRemoteQuotaStabilizationAcceptsChangedWindowIdentity() {
        let current = UsageSnapshot(
            primary: nil,
            secondary: LimitWindow(name: "secondary", usedPercent: 32, windowMinutes: 10_080, resetsAt: 10_000),
            contextWindow: nil,
            totalTokens: nil,
            lastTokens: nil,
            yesterdayTokens: nil,
            cumulativeTokens: nil,
            inputTokens: nil,
            outputTokens: nil,
            tokenUsageSource: "account",
            planType: "pro",
            source: "app-server",
            fetchedAt: 1_000
        )
        let changed = UsageSnapshot(
            primary: nil,
            secondary: LimitWindow(name: "GPT-5.3-Codex-Spark", usedPercent: 0, windowMinutes: 10_080, resetsAt: 30_000),
            contextWindow: nil,
            totalTokens: nil,
            lastTokens: nil,
            yesterdayTokens: nil,
            cumulativeTokens: nil,
            inputTokens: nil,
            outputTokens: nil,
            tokenUsageSource: "account",
            planType: "pro",
            source: "app-server",
            fetchedAt: 1_500
        )

        let stabilized = current.stabilizingQuota(from: changed, now: 1_500)

        XCTAssertEqual(stabilized.secondary, changed.secondary)
    }

    func testCachedUsagePreservesOfficialSourceForStartupStabilization() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-touchbar-cache-source-\(UUID().uuidString)")
        let cacheFile = directory.appendingPathComponent("usage-cache.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        try writeJSONObject(
            [
                "source": "app-server",
                "fetched_at": 1_000,
                "raw": [
                    "rate_limit": [
                        "primary_window": [
                            "used_percent": 30,
                            "limit_window_seconds": 18_000,
                            "reset_at": 2_000
                        ]
                    ]
                ]
            ],
            to: cacheFile
        )
        let configuration = UsageStoreConfiguration(
            codexHome: directory,
            cacheFile: cacheFile,
            tokenStatsCacheFile: directory.appendingPathComponent("token-cache.json")
        )

        let snapshot = try UsageStore(configuration: configuration).resolveCachedUsage()

        XCTAssertEqual(snapshot.source, "app-server")
        XCTAssertEqual(snapshot.primary?.usedPercent, 30)
    }

    func testSessionFallbackDoesNotOverwriteOfficialCache() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-touchbar-session-cache-\(UUID().uuidString)")
        let cacheFile = directory.appendingPathComponent("usage-cache.json")
        let sessionsDirectory = directory.appendingPathComponent("sessions/2026/07/11")
        let sessionFile = sessionsDirectory.appendingPathComponent("rollout-test.jsonl")
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        try writeJSONObject(
            [
                "source": "app-server",
                "fetched_at": 1_000,
                "raw": [
                    "rate_limit": [
                        "primary_window": [
                            "used_percent": 30,
                            "limit_window_seconds": 18_000,
                            "reset_at": 2_000
                        ]
                    ]
                ]
            ],
            to: cacheFile
        )
        let sessionEvent: JSONObject = [
            "timestamp": "2026-07-11T00:00:00Z",
            "payload": [
                "rate_limits": [
                    "primary": [
                        "used_percent": 90,
                        "window_minutes": 300,
                        "resets_at": 20_000
                    ],
                    "secondary": [
                        "used_percent": 38,
                        "window_minutes": 10_080,
                        "resets_at": 80_000
                    ]
                ]
            ]
        ]
        var sessionData = try JSONSerialization.data(withJSONObject: sessionEvent)
        sessionData.append(10)
        try sessionData.write(to: sessionFile)

        let configuration = UsageStoreConfiguration(
            codexHome: directory,
            cacheFile: cacheFile,
            tokenStatsCacheFile: directory.appendingPathComponent("token-cache.json")
        )
        let snapshot = try await UsageStore(configuration: configuration).resolveUsage(
            allowRemote: false,
            cacheMaxAge: 0,
            writeCache: true
        )
        let persisted = try readJSONObject(from: cacheFile)

        XCTAssertEqual(snapshot.source, "session")
        XCTAssertEqual(stringValue(persisted["source"]), "app-server")
    }
}
