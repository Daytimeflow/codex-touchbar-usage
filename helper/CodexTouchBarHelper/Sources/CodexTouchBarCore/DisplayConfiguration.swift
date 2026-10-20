import Foundation

public struct DisplaySettings: Codable, Equatable {
    /// The primary quota (usually five hours); its actual window label is preserved.
    public var fiveHour: Bool
    public var weekly: Bool
    public var resetCards: Bool
    public var yesterdayTokens: Bool
    public var totalTokens: Bool

    public init(fiveHour: Bool = true, weekly: Bool = false, resetCards: Bool = true,
                yesterdayTokens: Bool = true, totalTokens: Bool = true) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.resetCards = resetCards
        self.yesterdayTokens = yesterdayTokens
        self.totalTokens = totalTokens
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case fiveHour = "five_hour", weekly, resetCards = "reset_cards"
        case yesterdayTokens = "yesterday_tokens", totalTokens = "total_tokens"
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = DisplaySettings()
        fiveHour = try values.contains(.fiveHour) ? values.decode(Bool.self, forKey: .fiveHour) : defaults.fiveHour
        weekly = try values.contains(.weekly) ? values.decode(Bool.self, forKey: .weekly) : defaults.weekly
        resetCards = try values.contains(.resetCards) ? values.decode(Bool.self, forKey: .resetCards) : defaults.resetCards
        yesterdayTokens = try values.contains(.yesterdayTokens) ? values.decode(Bool.self, forKey: .yesterdayTokens) : defaults.yesterdayTokens
        totalTokens = try values.contains(.totalTokens) ? values.decode(Bool.self, forKey: .totalTokens) : defaults.totalTokens
    }
}

public struct DisplayConfiguration: Codable, Equatable {
    public var display: DisplaySettings

    public init(display: DisplaySettings = DisplaySettings()) { self.display = display }

    enum CodingKeys: String, CodingKey { case display }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(decoder, allowed: ["display"])
        let values = try decoder.container(keyedBy: CodingKeys.self)
        display = try values.contains(.display)
            ? values.decode(DisplaySettings.self, forKey: .display) : DisplaySettings()
    }

    public static func fileURL(codexHome: URL = UsageStoreConfiguration.defaultCodexHome()) -> URL {
        codexHome.appendingPathComponent("touchbar-usage/config.json")
    }

    public static func load(from url: URL) throws -> DisplayConfiguration {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return DisplayConfiguration()
        }
        return try JSONDecoder().decode(DisplayConfiguration.self, from: data)
    }
}

private struct ConfigurationKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private func rejectUnknownKeys(_ decoder: Decoder, allowed: [String]) throws {
    let values = try decoder.container(keyedBy: ConfigurationKey.self)
    if let key = values.allKeys.sorted(by: { $0.stringValue < $1.stringValue })
        .first(where: { !allowed.contains($0.stringValue) }) {
        throw DecodingError.dataCorrupted(.init(
            codingPath: decoder.codingPath + [key], debugDescription: "Unknown display configuration key: \(key.stringValue)"
        ))
    }
}

/// Presentation rows, independent of AppKit and of the order in the API response.
public enum QuotaDisplayRow: Equatable {
    case window(LimitWindow?)
    case resetCards
}

extension DisplaySettings {
    public func quotaRows(for snapshot: UsageSnapshot) -> [QuotaDisplayRow] {
        var rows: [QuotaDisplayRow] = []
        if fiveHour { rows.append(.window(snapshot.primary)) }
        if weekly {
            let window = [snapshot.primary, snapshot.secondary].compactMap { $0 }
                .first { $0.windowMinutes == 10_080 }
            // Some accounts have a weekly primary, or a Spark secondary instead of a week.
            if !fiveHour || window == nil || window != snapshot.primary {
                rows.append(.window(window ?? LimitWindow(
                    name: "weekly", usedPercent: nil, windowMinutes: 10_080, resetsAt: nil
                )))
            }
        }
        if resetCards { rows.append(.resetCards) }
        return rows
    }

    public func tokenRows(for snapshot: UsageSnapshot) -> [String] {
        var rows: [String] = []
        if yesterdayTokens { rows.append("昨日 \(UsageFormatting.tokenCount(snapshot.yesterdayTokens))") }
        if totalTokens { rows.append("累计 \(UsageFormatting.tokenCount(UsageFormatting.cumulativeTokenCount(snapshot)))") }
        return rows
    }
}
