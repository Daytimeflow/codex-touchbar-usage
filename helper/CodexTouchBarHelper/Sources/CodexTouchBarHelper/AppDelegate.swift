import AppKit
import CodexTouchBarCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let usageStore: UsageStore
    private let touchBarController = TouchBarController()
    private var frontmostMonitor: FrontmostAppMonitor?
    private var localRefreshTimer: Timer?
    private var remoteRefreshTimer: Timer?
    private var resetCardRefreshTimer: Timer?
    private var localRefreshTask: Task<Void, Never>?
    private var remoteRefreshTask: Task<Void, Never>?
    private var cachePreloadTask: Task<Void, Never>?
    private var currentSnapshot: UsageSnapshot?
    private var lastOfficialSnapshot: UsageSnapshot?
    private var lastRemoteFailureDescription: String?
    private var resetCardRefreshDeadline: Date?
    private var isCodexFrontmost = false
    private let localRefreshInterval: TimeInterval = 3
    private let remoteRefreshInterval: TimeInterval = 30
    private let resetCardRefreshInterval: TimeInterval = 8
    private let resetCardRefreshDuration: TimeInterval = 3 * 60

    init(configuration: UsageStoreConfiguration) {
        self.usageStore = UsageStore(configuration: configuration)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: "DFRSystemModalShowsCloseBox")

        let targetNames = targetApplicationNames()
        let monitor = FrontmostAppMonitor(targetNames: targetNames) { [weak self] visible in
            self?.handleVisibilityChange(visible)
        }
        frontmostMonitor = monitor
        monitor.start()
        preloadCachedUsage()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopRefresh()
        cachePreloadTask?.cancel()
        touchBarController.hideImmediately()
    }

    private func handleVisibilityChange(_ visible: Bool) {
        guard visible != isCodexFrontmost else { return }
        isCodexFrontmost = visible

        if visible {
            touchBarController.show()
            startRefresh()
        } else {
            stopRefresh()
            touchBarController.hideAnimated()
        }
    }

    private func startRefresh() {
        stopRefresh()
        refreshRemoteUsage()
        refreshLocalUsage()

        localRefreshTimer = Timer.scheduledTimer(withTimeInterval: localRefreshInterval, repeats: true) { [weak self] _ in
            self?.refreshLocalUsage()
        }
        localRefreshTimer?.tolerance = 0.5

        remoteRefreshTimer = Timer.scheduledTimer(withTimeInterval: remoteRefreshInterval, repeats: true) { [weak self] _ in
            self?.refreshRemoteUsage()
        }
        remoteRefreshTimer?.tolerance = 3

        resumeResetCardRefreshIfNeeded()
    }

    private func stopRefresh() {
        localRefreshTimer?.invalidate()
        localRefreshTimer = nil
        remoteRefreshTimer?.invalidate()
        remoteRefreshTimer = nil
        resetCardRefreshTimer?.invalidate()
        resetCardRefreshTimer = nil
        localRefreshTask?.cancel()
        localRefreshTask = nil
        remoteRefreshTask?.cancel()
        remoteRefreshTask = nil
    }

    private func refreshLocalUsage() {
        localRefreshTask?.cancel()
        localRefreshTask = Task { [weak self] in
            guard let self else { return }
            let snapshot = usageStore.resolveLocalTokenUsage()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let currentSnapshot = self.currentSnapshot else { return }
                let merged = currentSnapshot.mergingLocalTokenUsage(from: snapshot)
                self.currentSnapshot = merged
                self.touchBarController.update(merged)
            }
        }
    }

    private func preloadCachedUsage() {
        cachePreloadTask = Task { [weak self] in
            guard let self, let snapshot = try? usageStore.resolveCachedUsage() else { return }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.currentSnapshot == nil else { return }
                self.currentSnapshot = snapshot
                if snapshot.source == "app-server" || snapshot.source == "remote" {
                    self.lastOfficialSnapshot = snapshot
                }
                if self.isCodexFrontmost {
                    self.touchBarController.update(snapshot)
                }
            }
        }
    }

    private func refreshRemoteUsage() {
        guard remoteRefreshTask == nil else { return }
        remoteRefreshTask = Task { [weak self] in
            guard let self else { return }

            do {
                let snapshot = try await usageStore.resolveUsage(allowRemote: true, cacheMaxAge: 0)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.remoteRefreshTask = nil
                    guard snapshot.source == "app-server" || snapshot.source == "remote" || self.currentSnapshot == nil else {
                        self.logRemoteFallback(snapshot)
                        return
                    }
                    self.lastRemoteFailureDescription = nil
                    let previous = self.lastOfficialSnapshot
                    let stabilized = previous?.stabilizingQuota(from: snapshot) ?? snapshot
                    if let previous {
                        let consumedResetCredit = snapshot.consumedResetCredit(since: previous)
                        let quotaCycleAdvanced = stabilized.advancedPrimaryQuotaCycle(since: previous)
                        if consumedResetCredit && !quotaCycleAdvanced {
                            self.beginResetCardRefresh()
                        } else if quotaCycleAdvanced {
                            self.endResetCardRefresh()
                        }
                    }
                    self.lastOfficialSnapshot = stabilized
                    self.currentSnapshot = stabilized
                    self.touchBarController.update(stabilized)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.remoteRefreshTask = nil
                }
                NSLog("CodexTouchBarHelper: remote refresh failed: \(error.localizedDescription)")
            }
        }
    }

    private func beginResetCardRefresh() {
        resetCardRefreshDeadline = Date().addingTimeInterval(resetCardRefreshDuration)
        scheduleResetCardRefreshTimer()
    }

    private func resumeResetCardRefreshIfNeeded() {
        guard let deadline = resetCardRefreshDeadline, deadline > Date() else {
            endResetCardRefresh()
            return
        }
        scheduleResetCardRefreshTimer()
    }

    private func scheduleResetCardRefreshTimer() {
        guard isCodexFrontmost else { return }
        resetCardRefreshTimer?.invalidate()
        resetCardRefreshTimer = Timer.scheduledTimer(withTimeInterval: resetCardRefreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard let deadline = self.resetCardRefreshDeadline, deadline > Date() else {
                self.endResetCardRefresh()
                return
            }
            self.refreshRemoteUsage()
        }
        resetCardRefreshTimer?.tolerance = 1
    }

    private func endResetCardRefresh() {
        resetCardRefreshTimer?.invalidate()
        resetCardRefreshTimer = nil
        resetCardRefreshDeadline = nil
    }

    private func logRemoteFallback(_ snapshot: UsageSnapshot) {
        let description = snapshot.error ?? "official usage unavailable; using local session fallback"
        guard description != lastRemoteFailureDescription else { return }
        lastRemoteFailureDescription = description
        NSLog("CodexTouchBarHelper: official refresh unavailable: \(description)")
    }

    private func targetApplicationNames() -> Set<String> {
        let raw = ProcessInfo.processInfo.environment["CODEX_TOUCHBAR_TARGET_APPS"] ?? "Codex,ChatGPT,com.openai.codex"
        return Set(
            raw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }
}
