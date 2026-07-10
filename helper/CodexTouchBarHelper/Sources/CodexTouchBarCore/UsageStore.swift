import Foundation

public final class UsageStore {
    private let configuration: UsageStoreConfiguration
    private let tokenStatsStore: TokenStatsStore

    public init(configuration: UsageStoreConfiguration = UsageStoreConfiguration()) {
        self.configuration = configuration
        self.tokenStatsStore = TokenStatsStore(
            codexHome: configuration.codexHome,
            cacheFile: configuration.tokenStatsCacheFile
        )
    }

    public func resolveUsage(
        allowRemote: Bool = true,
        cacheMaxAge: TimeInterval? = nil,
        writeCache: Bool = true
    ) async throws -> UsageSnapshot {
        var errors: [String] = []
        let ttl = cacheMaxAge ?? configuration.cacheTTL

        if ttl > 0, var cached = try? loadFreshCachedRaw(maxAge: ttl) {
            enrichWithLocalUsage(&cached)
            let snapshot = normalizeUsage(cached, source: "cache")
            if !isAllZeroUsage(snapshot) {
                return snapshot
            } else {
                errors.append("cache: skipped all-zero usage snapshot")
            }
        }

        if allowRemote {
            do {
                let remote = try await fetchRemoteUsage()
                var raw = remote.raw
                enrichWithLocalUsage(&raw)
                let snapshot = normalizeUsage(raw, source: remote.source)
                if isAllZeroUsage(snapshot) {
                    do {
                        let (sessionSnapshot, sessionRaw) = try latestSessionSnapshot(error: "remote returned all-zero usage")
                        if !isAllZeroUsage(sessionSnapshot) {
                            if writeCache {
                                try? writeJSONObject(
                                    ["raw": sessionRaw, "source": "session", "fetched_at": sessionSnapshot.fetchedAt],
                                    to: configuration.cacheFile
                                )
                            }
                            return sessionSnapshot
                        }
                    } catch {
                        errors.append("session-after-zero-remote: \(type(of: error)): \(error.localizedDescription)")
                    }
                    errors.append("remote: skipped all-zero usage snapshot")
                } else {
                    if writeCache {
                        try? writeJSONObject(
                            ["raw": raw, "source": remote.source, "fetched_at": snapshot.fetchedAt],
                            to: configuration.cacheFile
                        )
                    }
                    return snapshot
                }
            } catch {
                errors.append("remote: \(type(of: error)): \(error.localizedDescription)")
            }
        }

        do {
            let (snapshot, raw) = try latestSessionSnapshot(error: errors.joined(separator: "; "))
            if writeCache {
                try? writeJSONObject(
                    ["raw": raw, "source": "session", "fetched_at": snapshot.fetchedAt],
                    to: configuration.cacheFile
                )
            }
            return snapshot
        } catch {
            errors.append("session: \(type(of: error)): \(error.localizedDescription)")
        }

        do {
            var raw = try loadCachedRaw()
            enrichWithLocalUsage(&raw)
            let snapshot = normalizeUsage(raw, source: "cache", error: errors.joined(separator: "; "))
            if !isAllZeroUsage(snapshot) {
                return snapshot
            }
            errors.append("cache: skipped stale all-zero usage snapshot")
        } catch {
            errors.append("cache: \(type(of: error)): \(error.localizedDescription)")
        }

        throw UsageError.noUsableUsage(errors.joined(separator: "; "))
    }

    public func rebuildTokenStats() -> TokenStats {
        tokenStatsStore.load(fullScan: true)
    }

    public func resolveCachedUsage() throws -> UsageSnapshot {
        let raw = try loadCachedRaw()
        return normalizeUsage(raw, source: "cache")
    }

    public func resolveLocalTokenUsage() -> UsageSnapshot {
        let stats = tokenStatsStore.load(fullScan: false)
        return UsageSnapshot(
            primary: nil,
            secondary: nil,
            contextWindow: nil,
            totalTokens: nil,
            lastTokens: nil,
            yesterdayTokens: stats.yesterdayTokens,
            cumulativeTokens: stats.cumulativeTokens,
            inputTokens: nil,
            outputTokens: nil,
            tokenUsageSource: "local",
            planType: nil,
            source: "local",
            fetchedAt: Int(Date().timeIntervalSince1970)
        )
    }

    func normalizeUsage(_ raw: JSONObject, source: String, error: String? = nil) -> UsageSnapshot {
        let rateLimits = (raw["rate_limits"] as? JSONObject) ?? (raw["rateLimits"] as? JSONObject) ?? [:]
        let apiRateLimit = raw["rate_limit"] as? JSONObject
        let tokenInfo = raw["token_info"] as? JSONObject ?? [:]
        let tokenStats = raw["token_stats"] as? JSONObject ?? [:]
        let now = Int(Date().timeIntervalSince1970)

        let contextWindow = intAtPath(tokenInfo, "model_context_window")
        let totalTokens = intAtPath(tokenInfo, "total_token_usage", "total_tokens")
        let lastTokens = intAtPath(tokenInfo, "last_token_usage", "total_tokens")
        let inputTokens = intAtPath(tokenInfo, "last_token_usage", "input_tokens")
        let outputTokens = intAtPath(tokenInfo, "last_token_usage", "output_tokens")
        let yesterdayTokens = intValue(tokenStats["yesterday_tokens"])
        let cumulativeTokens = intValue(tokenStats["cumulative_tokens"])
        let tokenUsageSource = stringValue(tokenStats["source"])

        if let apiRateLimit {
            return UsageSnapshot(
                primary: limitFromAPIWindow(name: "primary", payload: apiRateLimit["primary_window"]),
                secondary: limitFromAPIWindow(name: "secondary", payload: apiRateLimit["secondary_window"]),
                contextWindow: contextWindow,
                totalTokens: totalTokens,
                lastTokens: lastTokens,
                yesterdayTokens: yesterdayTokens,
                cumulativeTokens: cumulativeTokens,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                tokenUsageSource: tokenUsageSource,
                planType: stringValue(raw["plan_type"]),
                source: source,
                fetchedAt: now,
                error: error?.isEmpty == false ? error : nil
            )
        }

        return UsageSnapshot(
            primary: limitFromDictionary(name: "primary", payload: rateLimits["primary"]),
            secondary: limitFromDictionary(name: "secondary", payload: rateLimits["secondary"]),
            contextWindow: contextWindow,
            totalTokens: totalTokens,
            lastTokens: lastTokens,
            yesterdayTokens: yesterdayTokens,
            cumulativeTokens: cumulativeTokens,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            tokenUsageSource: tokenUsageSource,
            planType: stringValue(rateLimits["plan_type"]) ?? stringValue(raw["plan_type"]),
            source: source,
            fetchedAt: now,
            error: error?.isEmpty == false ? error : nil
        )
    }

    private func fetchRemoteUsage() async throws -> (raw: JSONObject, source: String) {
        if let client = CodexAppServerClient(timeout: configuration.requestTimeout),
           let raw = try? client.fetchUsage() {
            return (raw, "app-server")
        }
        let auth = try readAuthCredentials()
        return (try await fetchAuthenticatedJSON(url: configuration.endpoint, auth: auth), "remote")
    }

    private func readAuthCredentials() throws -> (accessToken: String, accountID: String?) {
        let auth = try readJSONObject(from: configuration.authFile)
        let tokens = auth["tokens"] as? JSONObject ?? [:]
        guard let accessToken = stringValue(tokens["access_token"]) else {
            throw UsageError.missingAccessToken(configuration.authFile)
        }
        return (accessToken, stringValue(tokens["account_id"]))
    }

    private func fetchAuthenticatedJSON(url: URL, auth: (accessToken: String, accountID: String?)) async throws -> JSONObject {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = configuration.requestTimeout
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codex-touchbar-usage-native/0.3", forHTTPHeaderField: "User-Agent")
        if let accountID = auth.accountID {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-ID")
        }

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.urlCache = nil
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: sessionConfiguration)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UsageError.noUsableUsage("usage endpoint returned HTTP \(http.statusCode)")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? JSONObject else {
            throw UsageError.noUsableUsage("\(url.path) returned non-object JSON")
        }
        return object
    }

    private func loadLatestSessionUsage(maxFiles: Int = 12) throws -> JSONObject {
        let files = jsonlFiles(under: configuration.codexHome.appendingPathComponent("sessions"))
            .sorted { modificationDate(for: $0) > modificationDate(for: $1) }

        for url in files.prefix(maxFiles) {
            var found: JSONObject?
            try reverseLines(at: url) { line in
                guard line.contains(#""rate_limits""#), let event = parseJSONLine(line) else { return false }
                guard
                    let payload = event["payload"] as? JSONObject,
                    let rateLimits = payload["rate_limits"] as? JSONObject
                else {
                    return false
                }
                if isAllZeroRateLimits(rateLimits) {
                    return false
                }
                found = [
                    "rate_limits": rateLimits,
                    "session_event_timestamp": event["timestamp"] ?? ""
                ]
                return true
            }
            if let found {
                return found
            }
        }
        throw UsageError.noLocalRateLimits
    }

    private func loadLatestTokenInfo(maxFiles: Int = 12) throws -> JSONObject {
        let files = jsonlFiles(under: configuration.codexHome.appendingPathComponent("sessions"))
            .sorted { modificationDate(for: $0) > modificationDate(for: $1) }

        for url in files.prefix(maxFiles) {
            var found: JSONObject?
            try reverseLines(at: url) { line in
                guard line.contains(#""total_token_usage""#), let event = parseJSONLine(line) else { return false }
                guard
                    let payload = event["payload"] as? JSONObject,
                    let info = payload["info"] as? JSONObject,
                    info["total_token_usage"] is JSONObject
                else {
                    return false
                }
                found = [
                    "token_info": info,
                    "token_event_timestamp": event["timestamp"] ?? ""
                ]
                return true
            }
            if let found {
                return found
            }
        }
        throw UsageError.noLocalTokenUsage
    }

    private func enrichWithLocalUsage(_ raw: inout JSONObject) {
        if raw["token_info"] == nil, let tokenInfo = try? loadLatestTokenInfo() {
            raw.merge(tokenInfo) { _, new in new }
        }
        let stats = tokenStatsStore.load(fullScan: false)
        if raw["token_stats"] == nil {
            raw["token_stats"] = [
                "source": "local",
                "yesterday_tokens": stats.yesterdayTokens,
                "cumulative_tokens": stats.cumulativeTokens,
                "yesterday_date": stats.yesterdayDate
            ]
        }
    }

    private func latestSessionSnapshot(error: String?) throws -> (UsageSnapshot, JSONObject) {
        var raw = try loadLatestSessionUsage()
        enrichWithLocalUsage(&raw)
        let snapshot = normalizeUsage(raw, source: "session", error: error?.isEmpty == false ? error : nil)
        return (snapshot, raw)
    }

    func isAllZeroUsage(_ snapshot: UsageSnapshot) -> Bool {
        guard
            let primary = snapshot.primary?.usedPercent,
            let secondary = snapshot.secondary?.usedPercent
        else {
            return false
        }
        return abs(primary) < 0.001 && abs(secondary) < 0.001
    }

    private func isAllZeroRateLimits(_ rateLimits: JSONObject) -> Bool {
        let primary = rateLimits["primary"] as? JSONObject
        let secondary = rateLimits["secondary"] as? JSONObject
        guard
            let primaryUsed = doubleValue(primary?["used_percent"]),
            let secondaryUsed = doubleValue(secondary?["used_percent"])
        else {
            return false
        }
        return abs(primaryUsed) < 0.001 && abs(secondaryUsed) < 0.001
    }

    private func loadFreshCachedRaw(maxAge: TimeInterval) throws -> JSONObject {
        let attributes = try FileManager.default.attributesOfItem(atPath: configuration.cacheFile.path)
        guard let modifiedAt = attributes[.modificationDate] as? Date else {
            throw UsageError.noUsableUsage("usage cache has no modification date")
        }
        guard Date().timeIntervalSince(modifiedAt) <= maxAge else {
            throw UsageError.noUsableUsage("cached usage is stale")
        }
        return try loadCachedRaw()
    }

    private func loadCachedRaw() throws -> JSONObject {
        let object = try readJSONObject(from: configuration.cacheFile)
        return (object["raw"] as? JSONObject) ?? object
    }

    private func limitFromDictionary(name: String, payload: Any?) -> LimitWindow? {
        guard let payload = payload as? JSONObject else { return nil }
        return LimitWindow(
            name: name,
            usedPercent: doubleValue(payload["used_percent"]),
            windowMinutes: intValue(payload["window_minutes"]),
            resetsAt: intValue(payload["resets_at"])
        )
    }

    private func limitFromAPIWindow(name: String, payload: Any?) -> LimitWindow? {
        guard let payload = payload as? JSONObject else { return nil }
        let seconds = intValue(payload["limit_window_seconds"])
        return LimitWindow(
            name: name,
            usedPercent: doubleValue(payload["used_percent"]),
            windowMinutes: seconds.map { $0 / 60 },
            resetsAt: intValue(payload["reset_at"])
        )
    }
}
