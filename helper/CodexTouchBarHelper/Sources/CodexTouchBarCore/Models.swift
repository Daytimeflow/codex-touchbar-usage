import Foundation

public struct LimitWindow: Codable, Equatable {
    public var name: String
    public var usedPercent: Double?
    public var windowMinutes: Int?
    public var resetsAt: Int?

    public init(name: String, usedPercent: Double?, windowMinutes: Int?, resetsAt: Int?) {
        self.name = name
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
    }
}

public struct UsageSnapshot: Codable, Equatable {
    public var primary: LimitWindow?
    public var secondary: LimitWindow?
    public var contextWindow: Int?
    public var totalTokens: Int?
    public var lastTokens: Int?
    public var yesterdayTokens: Int?
    public var cumulativeTokens: Int?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var tokenUsageSource: String?
    public var planType: String?
    public var source: String
    public var fetchedAt: Int
    public var error: String?

    public init(
        primary: LimitWindow?,
        secondary: LimitWindow?,
        contextWindow: Int?,
        totalTokens: Int?,
        lastTokens: Int?,
        yesterdayTokens: Int?,
        cumulativeTokens: Int?,
        inputTokens: Int?,
        outputTokens: Int?,
        tokenUsageSource: String? = nil,
        planType: String?,
        source: String,
        fetchedAt: Int,
        error: String? = nil
    ) {
        self.primary = primary
        self.secondary = secondary
        self.contextWindow = contextWindow
        self.totalTokens = totalTokens
        self.lastTokens = lastTokens
        self.yesterdayTokens = yesterdayTokens
        self.cumulativeTokens = cumulativeTokens
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.tokenUsageSource = tokenUsageSource
        self.planType = planType
        self.source = source
        self.fetchedAt = fetchedAt
        self.error = error
    }

    public static var placeholder: UsageSnapshot {
        UsageSnapshot(
            primary: LimitWindow(name: "primary", usedPercent: nil, windowMinutes: 300, resetsAt: nil),
            secondary: LimitWindow(name: "secondary", usedPercent: nil, windowMinutes: 10080, resetsAt: nil),
            contextWindow: nil,
            totalTokens: nil,
            lastTokens: nil,
            yesterdayTokens: nil,
            cumulativeTokens: nil,
            inputTokens: nil,
            outputTokens: nil,
            tokenUsageSource: nil,
            planType: nil,
            source: "placeholder",
            fetchedAt: Int(Date().timeIntervalSince1970)
        )
    }

    public func mergingLocalTokenUsage(from localSnapshot: UsageSnapshot) -> UsageSnapshot {
        let preservesAccountTotals = tokenUsageSource == "account"
        return UsageSnapshot(
            primary: primary,
            secondary: secondary,
            contextWindow: localSnapshot.contextWindow ?? contextWindow,
            totalTokens: localSnapshot.totalTokens ?? totalTokens,
            lastTokens: localSnapshot.lastTokens ?? lastTokens,
            yesterdayTokens: preservesAccountTotals
                ? (yesterdayTokens ?? localSnapshot.yesterdayTokens)
                : (localSnapshot.yesterdayTokens ?? yesterdayTokens),
            cumulativeTokens: preservesAccountTotals
                ? (cumulativeTokens ?? localSnapshot.cumulativeTokens)
                : (localSnapshot.cumulativeTokens ?? cumulativeTokens),
            inputTokens: localSnapshot.inputTokens ?? inputTokens,
            outputTokens: localSnapshot.outputTokens ?? outputTokens,
            tokenUsageSource: preservesAccountTotals ? tokenUsageSource : localSnapshot.tokenUsageSource,
            planType: planType,
            source: source,
            fetchedAt: fetchedAt,
            error: error
        )
    }

    public func stabilizingQuota(from incoming: UsageSnapshot, now: Int = Int(Date().timeIntervalSince1970)) -> UsageSnapshot {
        UsageSnapshot(
            primary: stableLimitWindow(current: primary, incoming: incoming.primary, now: now),
            secondary: stableLimitWindow(current: secondary, incoming: incoming.secondary, now: now),
            contextWindow: incoming.contextWindow ?? contextWindow,
            totalTokens: incoming.totalTokens ?? totalTokens,
            lastTokens: incoming.lastTokens ?? lastTokens,
            yesterdayTokens: incoming.yesterdayTokens ?? yesterdayTokens,
            cumulativeTokens: incoming.cumulativeTokens ?? cumulativeTokens,
            inputTokens: incoming.inputTokens ?? inputTokens,
            outputTokens: incoming.outputTokens ?? outputTokens,
            tokenUsageSource: incoming.tokenUsageSource ?? tokenUsageSource,
            planType: incoming.planType ?? planType,
            source: incoming.source,
            fetchedAt: incoming.fetchedAt,
            error: incoming.error
        )
    }
}

private func stableLimitWindow(current: LimitWindow?, incoming: LimitWindow?, now: Int) -> LimitWindow? {
    guard let current else { return incoming }
    guard var incoming else { return current }
    guard let currentUsed = current.usedPercent else { return incoming }
    guard let incomingUsed = incoming.usedPercent else { return current }

    if let currentReset = current.resetsAt {
        if now >= currentReset {
            guard let incomingReset = incoming.resetsAt, incomingReset > now else {
                return current
            }
            return incoming
        }
    }

    guard let incomingReset = incoming.resetsAt, incomingReset > now else {
        var stabilized = current
        stabilized.usedPercent = max(currentUsed, incomingUsed)
        return stabilized
    }

    if incomingUsed < currentUsed,
       startsNewQuotaCycle(current: current, incoming: incoming, currentReset: current.resetsAt, incomingReset: incomingReset) {
        return incoming
    }

    incoming.usedPercent = max(currentUsed, incomingUsed)
    return incoming
}

private func startsNewQuotaCycle(
    current: LimitWindow,
    incoming: LimitWindow,
    currentReset: Int?,
    incomingReset: Int
) -> Bool {
    guard let currentReset, incomingReset > currentReset else { return false }
    guard let windowMinutes = incoming.windowMinutes ?? current.windowMinutes, windowMinutes > 0 else { return false }
    let minimumCycleShift = max(60, windowMinutes * 60 / 4)
    return incomingReset - currentReset >= minimumCycleShift
}

public struct TokenStats: Codable, Equatable {
    public var yesterdayTokens: Int
    public var cumulativeTokens: Int
    public var yesterdayDate: String

    public init(yesterdayTokens: Int, cumulativeTokens: Int, yesterdayDate: String) {
        self.yesterdayTokens = yesterdayTokens
        self.cumulativeTokens = cumulativeTokens
        self.yesterdayDate = yesterdayDate
    }
}

public struct UsageStoreConfiguration {
    public var codexHome: URL
    public var endpoint: URL
    public var cacheFile: URL
    public var tokenStatsCacheFile: URL
    public var requestTimeout: TimeInterval
    public var cacheTTL: TimeInterval

    public init(
        codexHome: URL = UsageStoreConfiguration.defaultCodexHome(),
        endpoint: URL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
        cacheFile: URL? = nil,
        tokenStatsCacheFile: URL? = nil,
        requestTimeout: TimeInterval = 4,
        cacheTTL: TimeInterval = 20
    ) {
        self.codexHome = codexHome
        self.endpoint = endpoint
        self.cacheFile = cacheFile ?? codexHome.appendingPathComponent("touchbar-usage/usage-cache.json")
        self.tokenStatsCacheFile = tokenStatsCacheFile ?? codexHome.appendingPathComponent("touchbar-usage/token-stats-cache.json")
        self.requestTimeout = requestTimeout
        self.cacheTTL = cacheTTL
    }

    public var authFile: URL {
        codexHome.appendingPathComponent("auth.json")
    }

    public static func defaultCodexHome() -> URL {
        if let value = ProcessInfo.processInfo.environment["CODEX_HOME"], !value.isEmpty {
            return URL(fileURLWithPath: NSString(string: value).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }
}
