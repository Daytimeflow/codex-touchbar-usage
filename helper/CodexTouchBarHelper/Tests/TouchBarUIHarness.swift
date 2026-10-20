import AppKit
import CodexTouchBarCore

@main
struct TouchBarUIHarness {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let tokens: Set<String> = ["Codex", "ChatGPT", "com.openai.codex"]
        precondition(ForegroundTarget.resolve(bundleIdentifier: "dev.zcode.app", candidates: ["ChatGPT"], codexTokens: tokens) == .zcode)
        precondition(ForegroundTarget.resolve(bundleIdentifier: "com.openai.codex", candidates: ["ZCode"], codexTokens: tokens) == .codex)
        precondition(ForegroundTarget.resolve(bundleIdentifier: "com.apple.Terminal", candidates: ["Terminal"], codexTokens: tokens) == .none)
        precondition(ForegroundTarget.resolve(bundleIdentifier: nil, candidates: ["ChatGPT"], codexTokens: tokens) == .codex)
        let controller = TouchBarController(usesSystemTouchBar: false)
        var timings: [Double] = []
        for _ in 0..<100 {
            let start = CFAbsoluteTimeGetCurrent()
            controller.show(for: .codex)
            controller.show(for: .zcode)
            controller.hideAnimated()
            controller.show(for: .codex)
            timings.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.7))
        precondition(controller.isPresented && controller.target == .codex, "late hide must not dismiss current panel")
        controller.hideAnimated()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        precondition(!controller.isPresented)
        timings.sort()
        print("100 rapid synthetic target cycles: PASS; p95 dispatch ms=\(timings[94]) (system presentation disabled)")

        let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/codex-touchbar-preview")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let codex = UsageTouchBarView(frame: NSRect(x: 0, y: 0, width: 720, height: 30))
        codex.alphaValue = 1
        var original = UsageSnapshot.placeholder
        original.primary = LimitWindow(name: "codex", usedPercent: 39, windowMinutes: 10080, resetsAt: 1785258135)
        original.resetCreditsAvailable = 3
        original.resetCreditsExpiresAt = 1785109710
        original.yesterdayTokens = 791733914
        original.cumulativeTokens = 15439107907
        original.source = "app-server"
        codex.snapshot = original
        try render(codex, to: directory.appendingPathComponent("codex.png"))
        original.primary = LimitWindow(name: "codex", usedPercent: 35, windowMinutes: 300, resetsAt: 1_800_000_000)
        original.secondary = LimitWindow(name: "secondary", usedPercent: 20, windowMinutes: 10_080, resetsAt: 1_800_010_000)
        original.resetCreditsAvailable = 12
        codex.snapshot = original
        for mask in 0..<32 {
            codex.displaySettings = DisplaySettings(
                fiveHour: mask & 1 != 0, weekly: mask & 2 != 0, resetCards: mask & 4 != 0,
                yesterdayTokens: mask & 8 != 0, totalTokens: mask & 16 != 0
            )
            let layout = codex.displayLayout
            let rects = layout.quotaRects + layout.tokenRects
            precondition(layout.quotaRects.count == (mask & 7).nonzeroBitCount)
            precondition(layout.tokenRects.count == (mask & 24).nonzeroBitCount)
            for (index, rect) in rects.enumerated() {
                precondition(rect.minX >= 75 && rect.maxX <= 695 && rect.minY >= 0 && rect.maxY <= 30)
                for other in rects.dropFirst(index + 1) {
                    precondition(!rect.intersects(other), "overlapping rows for mask \(mask)")
                }
            }
            // Each quota row reserves 195 px for label/value/date/gaps; the bar remains positive.
            precondition(layout.quotaRects.allSatisfy { $0.width >= 215 })
            try render(codex, to: directory.appendingPathComponent("display-\(mask).png"))
        }
        codex.displaySettings = DisplaySettings(weekly: true, resetCards: false, yesterdayTokens: false, totalTokens: false)
        original.secondary = nil
        codex.snapshot = original
        try render(codex, to: directory.appendingPathComponent("weekly-missing.png"))
        print("32 display combinations: PASS; all rows within bounds with no overlap")
        let zcode = ZCodeTouchBarView(frame: codex.frame)
        var z = ZCodeUsageSnapshot.placeholder
        z.provider = .go
        z.goRolling = ZCodeQuota(usedPercent: 23, resetsAt: 1788939447)
        z.goWeekly = ZCodeQuota(usedPercent: 81, resetsAt: 1789344000)
        z.goMonthly = ZCodeQuota(usedPercent: 94, resetsAt: 1789004067)
        z.glmPrimary = ZCodeQuota(usedPercent: 27, resetsAt: 1788929097)
        z.glmWeekly = ZCodeQuota(usedPercent: 72, resetsAt: 1789106366)
        z.todayTokens = 12345678
        z.cumulativeTokens = 1234567890
        z.statsReady = true
        zcode.snapshot = z
        try render(zcode, to: directory.appendingPathComponent("go.png"))
        z.provider = .glm
        zcode.snapshot = z
        try render(zcode, to: directory.appendingPathComponent("glm.png"))
        (zcode.subviews.first as? NSButton)?.performClick(nil)
        precondition(zcode.showsDetails)
        try render(zcode, to: directory.appendingPathComponent("details.png"))
        print("Native AppKit rendering: PASS")
    }

    @MainActor static func render(_ view: NSView, to url: URL) throws {
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.backgroundColor = .black
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("bitmap unavailable") }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("PNG unavailable") }
        try data.write(to: url)
    }
}
