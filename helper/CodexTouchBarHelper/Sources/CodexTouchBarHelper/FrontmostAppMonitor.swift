import AppKit

final class FrontmostAppMonitor {
    private let targetTokens: Set<String>
    private let onChange: (Bool) -> Void
    private var lastValue: Bool?

    init(targetNames: Set<String>, onChange: @escaping (Bool) -> Void) {
        self.targetTokens = targetNames
        self.onChange = onChange
    }

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeApplicationChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        evaluate(NSWorkspace.shared.frontmostApplication)
    }

    @objc private func activeApplicationChanged(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        evaluate(app ?? NSWorkspace.shared.frontmostApplication)
    }

    private func evaluate(_ application: NSRunningApplication?) {
        let candidates = [
            application?.localizedName,
            application?.bundleIdentifier,
            application?.executableURL?.deletingPathExtension().lastPathComponent,
            application?.bundleURL?.deletingPathExtension().lastPathComponent
        ].compactMap { $0 }
        let visible = candidates.contains { targetTokens.contains($0) }
        guard visible != lastValue else { return }
        lastValue = visible
        if ProcessInfo.processInfo.environment["CODEX_TOUCHBAR_DEBUG"] == "1" {
            NSLog(
                "CodexTouchBarHelper: frontmost candidates=%@ visible=%@",
                candidates.joined(separator: ","),
                visible ? "true" : "false"
            )
        }
        DispatchQueue.main.async {
            self.onChange(visible)
        }
    }
}
