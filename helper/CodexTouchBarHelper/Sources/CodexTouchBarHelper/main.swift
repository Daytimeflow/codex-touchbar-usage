import AppKit
import CodexTouchBarCore
import Foundation

let arguments = Set(CommandLine.arguments.dropFirst())
let configuration = UsageStoreConfiguration()

if arguments.contains("--print-display-config") {
    do {
        let display = try DisplayConfiguration.load(from: DisplayConfiguration.fileURL(codexHome: configuration.codexHome))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(display))
        FileHandle.standardOutput.write(Data("\n".utf8))
        exit(0)
    } catch {
        fputs("CodexTouchBarHelper: invalid display configuration: \(error)\n", stderr)
        exit(2)
    }
}

if arguments.contains("--zcode-once-json") {
    let store = ZCodeUsageStore()
    _ = await store.refreshLocal()
    let snapshot = arguments.contains("--no-remote")
        ? await store.cachedSnapshot()
        : await store.refreshRemote()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(snapshot))
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(0)
}

if arguments.contains("--rebuild-token-stats") {
    let stats = TokenStatsStore(
        codexHome: configuration.codexHome,
        cacheFile: configuration.tokenStatsCacheFile
    ).load(fullScan: true)
    let data = try JSONEncoder().encode(stats)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(0)
}

if arguments.contains("--once-json") {
    do {
        let snapshot = try await UsageStore(configuration: configuration).resolveUsage(
            allowRemote: !arguments.contains("--no-remote"),
            cacheMaxAge: arguments.contains("--no-remote") ? 60 : nil
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        exit(0)
    } catch {
        fputs("CodexTouchBarHelper: \(error.localizedDescription)\n", stderr)
        exit(2)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate(configuration: configuration)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
