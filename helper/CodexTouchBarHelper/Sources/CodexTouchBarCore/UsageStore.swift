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
                                writeSessionCacheIfNoOfficialCache(raw: sessionRaw, snapshot: sessionSnapshot)
                            }
                            return sessionSnapshot
                        }
                    } catch {
                        errors.append("session-after-zero-remote: \(type(of: error)): \(error.localizedDescription)")
                    }
                    errors.append("remote: skipped all-zero usage snapshot")
                } else {
                    if writeCache {
                        writeRemoteCacheIfStable(raw: raw, source: remote.source, snapshot: snapshot)
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
                writeSessionCacheIfNoOfficialCache(raw: raw, snapshot: snapshot)
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
        try loadCachedSnapshot()
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
        let resetCredits = resetCreditSummary(raw)

        let contextWindow = intAtPath(tokenInfo, "model_context_window")
        let totalTokens = intAtPath(tokenInfo, "total_token_usage", "total_tokens")
        let lastTokens = intAtPath(tokenInfo, "last_token_usage", "total_tokens")
        let inputTokens = intAtPath(tokenInfo, "last_token_usage", "input_tokens")
        let outputTokens = intAtPath(tokenInfo, "last_token_usage", "output_tokens")
        let yesterdayTokens = intValue(tokenStats["yesterday_tokens"])
        let cumulativeTokens = intValue(tokenStats["cumulative_tokens"])
        let tokenUsageSource = stringValue(tokenStats["source"])

        if let apiRateLimit {
            let primary = limitFromAPIWindow(name: "codex", payload: apiRateLimit["primary_window"])
            let secondary = limitFromAPIWindow(name: "secondary", payload: apiRateLimit["secondary_window"])
                ?? additionalLimitFromAPI(raw)
            return UsageSnapshot(
                primary: primary,
                secondary: secondary,
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
                resetCreditsAvailable: resetCredits.availableCount,
                resetCreditsExpiresAt: resetCredits.earliestExpiration,
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
            resetCreditsAvailable: resetCredits.availableCount,
            resetCreditsExpiresAt: resetCredits.earliestExpiration,
            error: error?.isEmpty == false ? error : nil
        )
    }

    private func fetchRemoteUsage() async throws -> (raw: JSONObject, source: String) {
        var failures: [String] = []
        if let client = CodexAppServerClient(timeout: configuration.requestTimeout) {
            do {
                return (try client.fetchUsage(), "app-server")
            } catch {
                failures.append("app-server: \(error.localizedDescription)")
            }
        } else {
            failures.append("app-server: Codex executable not found")
        }

        do {
            let auth = try readAuthCredentials()
            var raw = try await fetchAuthenticatedJSON(url: configuration.endpoint, auth: auth)
            if let details = try? await fetchAuthenticatedJSON(
                url: configuration.resetCreditsEndpoint,
                auth: auth
            ) {
                mergeResetCreditDetails(details, into: &raw)
            }
            return (raw, "remote")
        } catch {
            failures.append("authenticated HTTP: \(error.localizedDescription)")
            throw UsageError.noUsableUsage(failures.joined(separator: "; "))
        }
    }

    private func readAuthCredentials() throws -> (accessToken: String, accountID: String?) {
        guard let auth = try? readJSONObject(from: configuration.authFile) else {
            throw UsageError.missingAccessToken(configuration.authFile)
        }
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
        request.setValue("codex-touchbar-usage-native/0.3.6", forHTTPHeaderField: "User-Agent")
        if let accountID = auth.accountID {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-ID")
        }

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.urlCache = nil
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: sessionConfiguration)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UsageError.noUsableUsage("\(url.lastPathComponent) endpoint returned HTTP \(http.statusCode)")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? JSONObject else {
            throw UsageError.noUsableUsage("\(url.path) returned non-object JSON")
        }
        return object
    }

    private func mergeResetCreditDetails(_ details: JSONObject, into raw: inout JSONObject) {
        let summary = resetCreditSummary(details)
        guard let availableCount = summary.availableCount else { return }

        var compact: JSONObject = ["available_count": max(0, availableCount)]
        if let earliestExpiration = summary.earliestExpiration {
            compact["expires_at"] = earliestExpiration
        }
        raw["rate_limit_reset_credits"] = compact
    }

    private func resetCreditSummary(_ raw: JSONObject) -> (availableCount: Int?, earliestExpiration: Int?) {
        let payload = (raw["rate_limit_reset_credits"] as? JSONObject)
            ?? (raw["rateLimitResetCredits"] as? JSONObject)
            ?? raw
        let availableCount = intValue(payload["available_count"])
            ?? intValue(payload["availableCount"])
        guard let availableCount else { return (nil, nil) }
        guard availableCount > 0 else { return (0, nil) }

        let compactExpiration = timestampValue(payload["expires_at"] ?? payload["expiresAt"])
        let credits = payload["credits"] as? [JSONObject] ?? []
        let detailedExpiration = credits
            .filter { (stringValue($0["status"]) ?? "available") == "available" }
            .compactMap { timestampValue($0["expires_at"] ?? $0["expiresAt"]) }
            .min()
        return (availableCount, detailedExpiration ?? compactExpiration)
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

    private func loadCachedSnapshot() throws -> UsageSnapshot {
        let object = try readJSONObject(from: configuration.cacheFile)
        let raw = (object["raw"] as? JSONObject) ?? object
        let source = stringValue(object["source"]) ?? "cache"
        return normalizeUsage(raw, source: source)
    }

    private func writeRemoteCacheIfStable(raw: JSONObject, source: String, snapshot: UsageSnapshot) {
        if let cached = try? loadCachedSnapshot(),
           ["app-server", "remote"].contains(cached.source) {
            let stabilized = cached.stabilizingQuota(from: snapshot, now: snapshot.fetchedAt)
            guard stabilized.primary == snapshot.primary, stabilized.secondary == snapshot.secondary else {
                return
            }
        }

        try? writeJSONObject(
            ["raw": raw, "source": source, "fetched_at": snapshot.fetchedAt],
            to: configuration.cacheFile
        )
    }

    private func writeSessionCacheIfNoOfficialCache(raw: JSONObject, snapshot: UsageSnapshot) {
        if let cached = try? loadCachedSnapshot(), ["app-server", "remote"].contains(cached.source) {
            return
        }
        try? writeJSONObject(
            ["raw": raw, "source": "session", "fetched_at": snapshot.fetchedAt],
            to: configuration.cacheFile
        )
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
            name: stringValue(payload["name"]) ?? name,
            usedPercent: doubleValue(payload["used_percent"]),
            windowMinutes: seconds.map { $0 / 60 },
            resetsAt: intValue(payload["reset_at"])
        )
    }

    private func additionalLimitFromAPI(_ raw: JSONObject) -> LimitWindow? {
        guard let limits = raw["additional_rate_limits"] as? [JSONObject] else { return nil }
        let ordered = limits.sorted {
            stringValue($0["metered_feature"]) == "codex_bengalfox"
                && stringValue($1["metered_feature"]) != "codex_bengalfox"
        }
        for item in ordered {
            guard let rateLimit = item["rate_limit"] as? JSONObject else { continue }
            let name = stringValue(item["limit_name"])
                ?? stringValue(item["metered_feature"])
                ?? "additional"
            if let window = limitFromAPIWindow(name: name, payload: rateLimit["primary_window"])
                ?? limitFromAPIWindow(name: name, payload: rateLimit["secondary_window"]) {
                return window
            }
        }
        return nil
    }
}
