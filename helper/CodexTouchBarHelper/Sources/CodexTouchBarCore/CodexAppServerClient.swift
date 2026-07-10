import Foundation

final class CodexAppServerClient {
    private let executableURL: URL
    private let timeout: TimeInterval

    init?(timeout: TimeInterval) {
        guard let executableURL = Self.findCodexExecutable() else { return nil }
        self.executableURL = executableURL
        self.timeout = max(timeout, 6)
    }

    func fetchUsage() throws -> JSONObject {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executableURL
        process.arguments = ["app-server"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let stateQueue = DispatchQueue(label: "codex.touchbar.app-server.responses")
        let completed = DispatchSemaphore(value: 0)
        var pending = Data()
        var rateLimitsResult: JSONObject?
        var tokenUsageResult: JSONObject?
        var receivedRateLimitsResponse = false
        var receivedTokenUsageResponse = false
        var didSignal = false

        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            stateQueue.sync {
                pending.append(data)
                while let newline = pending.firstIndex(of: 10) {
                    let line = pending[..<newline]
                    pending.removeSubrange(...newline)
                    guard
                        let message = try? JSONSerialization.jsonObject(with: line) as? JSONObject,
                        let id = intValue(message["id"])
                    else {
                        continue
                    }
                    if id == 2 {
                        receivedRateLimitsResponse = true
                        rateLimitsResult = message["result"] as? JSONObject
                    } else if id == 3 {
                        receivedTokenUsageResponse = true
                        tokenUsageResult = message["result"] as? JSONObject
                    }
                    if receivedRateLimitsResponse, receivedTokenUsageResponse, !didSignal {
                        didSignal = true
                        completed.signal()
                    }
                }
            }
        }

        try process.run()
        let messages: [JSONObject] = [
            [
                "method": "initialize",
                "id": 0,
                "params": [
                    "clientInfo": [
                        "name": "codex_touchbar_usage",
                        "title": "Codex Touch Bar Usage",
                        "version": "0.3.3"
                    ]
                ]
            ],
            ["method": "initialized", "params": JSONObject()],
            ["method": "account/read", "id": 1, "params": ["refreshToken": true]],
            ["method": "account/rateLimits/read", "id": 2, "params": JSONObject()],
            ["method": "account/usage/read", "id": 3, "params": JSONObject()]
        ]
        for message in messages {
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }

        let waitResult = completed.wait(timeout: .now() + timeout)
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
        }

        guard waitResult == .success else {
            throw UsageError.noUsableUsage("Codex app-server usage request timed out")
        }
        let responses = stateQueue.sync { (rateLimitsResult, tokenUsageResult) }
        guard let rateLimits = responses.0 else {
            throw UsageError.noUsableUsage("Codex app-server returned no rate-limit data")
        }
        return try Self.combine(rateLimits: rateLimits, tokenUsage: responses.1 ?? [:])
    }

    static func combine(rateLimits: JSONObject, tokenUsage: JSONObject) throws -> JSONObject {
        guard let limits = rateLimits["rateLimits"] as? JSONObject else {
            throw UsageError.noUsableUsage("Codex app-server returned no rate limits")
        }

        var raw: JSONObject = ["plan_type": limits["planType"] ?? ""]
        var apiRateLimit: JSONObject = [:]
        if let primary = appServerWindow(limits["primary"]) {
            apiRateLimit["primary_window"] = primary
        }
        if let secondary = appServerWindow(limits["secondary"]) {
            apiRateLimit["secondary_window"] = secondary
        }
        raw["rate_limit"] = apiRateLimit

        let summary = tokenUsage["summary"] as? JSONObject ?? [:]
        let buckets = tokenUsage["dailyUsageBuckets"] as? [JSONObject] ?? []
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()).map { dayKey(for: $0) } ?? ""
        if let lifetimeTokens = intValue(summary["lifetimeTokens"]) {
            let yesterdayTokens = buckets.first {
                stringValue($0["startDate"]) == yesterday
            }.flatMap { intValue($0["tokens"]) }
            raw["token_stats"] = [
                "source": "account",
                "yesterday_tokens": yesterdayTokens ?? 0,
                "cumulative_tokens": lifetimeTokens,
                "yesterday_date": yesterday
            ]
        }
        return raw
    }

    private static func appServerWindow(_ value: Any?) -> JSONObject? {
        guard let window = value as? JSONObject else { return nil }
        let minutes = intValue(window["windowDurationMins"])
        return [
            "used_percent": doubleValue(window["usedPercent"]) ?? 0,
            "limit_window_seconds": (minutes ?? 0) * 60,
            "reset_at": intValue(window["resetsAt"]) ?? 0
        ]
    }

    private static func findCodexExecutable() -> URL? {
        var candidates: [String] = []
        if let configured = ProcessInfo.processInfo.environment["CODEX_TOUCHBAR_CODEX_BINARY"], !configured.isEmpty {
            candidates.append(NSString(string: configured).expandingTildeInPath)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        candidates.append(contentsOf: [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "\(home)/Applications/ChatGPT.app/Contents/Resources/codex",
            "\(home)/Applications/Codex.app/Contents/Resources/codex"
        ])
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/codex" })
        }
        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0)
        }.map(URL.init(fileURLWithPath:))
    }
}
