import Foundation
#if !DISPLAY_STANDALONE
@testable import CodexTouchBarCore
import XCTest
#endif

struct DisplayConfigurationChecks {
    private func decode(_ json: String) throws -> DisplayConfiguration {
        try JSONDecoder().decode(DisplayConfiguration.self, from: Data(json.utf8))
    }

    func testDefaultsAndPartialConfiguration() throws {
        try equal(try decode("{}"), DisplayConfiguration())
        try equal(try decode(#"{"display":{}}"#), DisplayConfiguration())
        let settings = try decode(#"{"display":{"weekly":true,"reset_cards":false}}"#).display
        try equal(settings, DisplaySettings(weekly: true, resetCards: false))
        let roundTrip = try JSONDecoder().decode(DisplayConfiguration.self, from: JSONEncoder().encode(DisplayConfiguration(display: settings)))
        try equal(roundTrip.display, settings)
    }

    func testRejectsTyposNullAndNonBooleanValues() throws {
        for json in [#"{"weekly":true}"#, #"{"display":{"weeky":true}}"#,
                     #"{"display":{"weekly":"true"}}"#, #"{"display":{"weekly":1}}"#,
                     #"{"display":{"weekly":null}}"#, #"{"display":null}"#, "[]", ""] {
            try expectError { _ = try decode(json) }
        }
    }

    func testFileCanBeAddedEditedAndRemoved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = DisplayConfiguration.fileURL(codexHome: directory)
        try equal(try DisplayConfiguration.load(from: url), DisplayConfiguration())
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"display":{"weekly":true}}"#.utf8).write(to: url, options: .atomic)
        try require(try DisplayConfiguration.load(from: url).display.weekly)
        try Data("broken".utf8).write(to: url, options: .atomic)
        try expectError { _ = try DisplayConfiguration.load(from: url) }
        try Data(#"{"display":{"five_hour":false,"weekly":true}}"#.utf8).write(to: url, options: .atomic)
        try requireFalse(try DisplayConfiguration.load(from: url).display.fiveHour)
        try FileManager.default.removeItem(at: url)
        try equal(try DisplayConfiguration.load(from: url), DisplayConfiguration())
    }

    func testWeeklyWindowUsesDurationAndDoesNotDuplicatePrimary() throws {
        var snapshot = UsageSnapshot.placeholder
        snapshot.primary = LimitWindow(name: "codex", usedPercent: 35, windowMinutes: 300, resetsAt: 1_800_000_000)
        let week = LimitWindow(name: "secondary", usedPercent: 20, windowMinutes: 10_080, resetsAt: 1_800_010_000)
        snapshot.secondary = week
        let settings = DisplaySettings(weekly: true, resetCards: false)
        try equal(settings.quotaRows(for: snapshot), [.window(snapshot.primary), .window(week)])
        snapshot.primary = week
        snapshot.secondary = LimitWindow(name: "spark", usedPercent: 90, windowMinutes: 300, resetsAt: nil)
        try equal(settings.quotaRows(for: snapshot), [.window(week)])
        let weeklyOnly = DisplaySettings(fiveHour: false, weekly: true, resetCards: false)
        try equal(weeklyOnly.quotaRows(for: snapshot), [.window(week)])
        snapshot.primary = nil
        let rows = weeklyOnly.quotaRows(for: snapshot)
        guard case .window(let missingWeek) = rows.first else { throw CheckFailure(message: "missing weekly row") }
        try equal(missingWeek?.windowMinutes, 10_080)
        try isNil(missingWeek?.usedPercent)
        try equal(UsageFormatting.balanceLabel(usedPercent: missingWeek?.usedPercent), "--%")
    }

    func testEverySwitchCombinationAndTokenFallback() throws {
        var snapshot = UsageSnapshot.placeholder
        snapshot.yesterdayTokens = 10_000
        snapshot.totalTokens = 100_000_000
        for mask in 0..<32 {
            let settings = DisplaySettings(fiveHour: mask & 1 != 0, weekly: mask & 2 != 0,
                                           resetCards: mask & 4 != 0, yesterdayTokens: mask & 8 != 0,
                                           totalTokens: mask & 16 != 0)
            try equal(settings.quotaRows(for: snapshot).count, (mask & 7).nonzeroBitCount)
            try equal(settings.tokenRows(for: snapshot).count, (mask & 24).nonzeroBitCount)
        }
        try equal(DisplaySettings().tokenRows(for: snapshot), ["昨日 1.0万", "累计 1.0亿"])
        try equal(DisplaySettings(fiveHour: false, resetCards: false, yesterdayTokens: false).tokenRows(for: snapshot), ["累计 1.0亿"])
    }
}

private struct CheckFailure: Error { let message: String }
private func require(_ condition: Bool, line: Int = #line) throws {
    if !condition { throw CheckFailure(message: "check failed at line \(line)") }
}
private func requireFalse(_ condition: Bool, line: Int = #line) throws { try require(!condition, line: line) }
private func isNil<T>(_ value: T?, line: Int = #line) throws { try require(value == nil, line: line) }
private func equal<T: Equatable>(_ actual: T, _ expected: T, line: Int = #line) throws {
    if actual != expected { throw CheckFailure(message: "line \(line): \(actual) != \(expected)") }
}
private func expectError(_ body: () throws -> Void) throws {
    do { try body() } catch { return }
    throw CheckFailure(message: "expected an error")
}

#if DISPLAY_STANDALONE
@main struct DisplayConfigurationStandalone {
    static func main() throws {
        let checks = DisplayConfigurationChecks()
        try checks.testDefaultsAndPartialConfiguration()
        try checks.testRejectsTyposNullAndNonBooleanValues()
        try checks.testFileCanBeAddedEditedAndRemoved()
        try checks.testWeeklyWindowUsesDurationAndDoesNotDuplicatePrimary()
        try checks.testEverySwitchCombinationAndTokenFallback()
        print("Display configuration, file reload, weekly selection and 32 switch combinations: PASS")
    }
}
#else
final class DisplayConfigurationTests: XCTestCase {
    func testConfigurationAndRows() throws {
        let checks = DisplayConfigurationChecks()
        try checks.testDefaultsAndPartialConfiguration()
        try checks.testRejectsTyposNullAndNonBooleanValues()
        try checks.testFileCanBeAddedEditedAndRemoved()
        try checks.testWeeklyWindowUsesDurationAndDoesNotDuplicatePrimary()
        try checks.testEverySwitchCombinationAndTokenFallback()
    }
}
#endif
