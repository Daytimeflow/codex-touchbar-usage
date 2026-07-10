import Foundation

public enum UsageFormatting {
    public static func clamp(_ value: Double, low: Double = 0, high: Double = 100) -> Double {
        max(low, min(high, value))
    }

    public static func remainingPercent(usedPercent: Double?) -> Double? {
        guard let usedPercent else { return nil }
        return clamp(100 - usedPercent)
    }

    public static func balanceLabel(usedPercent: Double?) -> String {
        percentLabel(remainingPercent(usedPercent: usedPercent))
    }

    public static func percentLabel(_ value: Double?) -> String {
        guard let value else { return "--%" }
        if abs(value - value.rounded()) < 0.05 {
            return "\(Int(value.rounded()))%"
        }
        return String(format: "%.1f%%", value)
    }

    public static func resetLabel(_ timestamp: Int?) -> String {
        guard let timestamp, timestamp > 0 else { return "--/-- --:--" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    public static func tokenCount(_ value: Int?) -> String {
        guard let value else { return "--" }
        if value >= 100_000_000 {
            let amount = Double(value) / 100_000_000
            return amount < 10 ? String(format: "%.1f亿", amount) : String(format: "%.0f亿", amount)
        }
        if value >= 10_000 {
            let amount = Double(value) / 10_000
            return amount < 100 ? String(format: "%.1f万", amount) : String(format: "%.0f万", amount)
        }
        if value >= 1_000 {
            let amount = Double(value) / 1_000
            return String(format: "%.1fK", amount)
        }
        return "\(value)"
    }

    public static func cumulativeTokenCount(_ snapshot: UsageSnapshot) -> Int? {
        snapshot.cumulativeTokens ?? snapshot.totalTokens
    }

    public static func tokenRows(_ snapshot: UsageSnapshot) -> (String, String) {
        return (
            "昨日 \(tokenCount(snapshot.yesterdayTokens))",
            "累计 \(tokenCount(cumulativeTokenCount(snapshot)))"
        )
    }
}
