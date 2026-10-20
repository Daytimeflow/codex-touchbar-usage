import AppKit
import CodexTouchBarCore

// Keep synchronous session scans and app-server waits off the UI executor.
private actor CodexUsageLoader {
    let store: UsageStore
    init(configuration: UsageStoreConfiguration) { store = UsageStore(configuration: configuration) }
    func cached() throws -> UsageSnapshot { try store.resolveCachedUsage() }
    func local() -> UsageSnapshot { store.resolveLocalTokenUsage() }
    func remote() async throws -> UsageSnapshot {
        try Task.checkCancellation()
        return try await store.resolveUsage(allowRemote: true, cacheMaxAge: 0)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let codexLoader: CodexUsageLoader
    private let zcodeStore = ZCodeUsageStore()
    private let touchBarController = TouchBarController()
    private var frontmostMonitor: FrontmostAppMonitor?
    private var localTimer: Timer?
    private var remoteTimer: Timer?
    private var resetTimer: Timer?
    private var startup: DispatchWorkItem?
    private var statsContinuation: DispatchWorkItem?
    private var preloadTask: Task<Void, Never>?
    private var localTasks: [ForegroundTarget: Task<Void, Never>] = [:]
    private var remoteTasks: [ForegroundTarget: Task<Void, Never>] = [:]
    private var target: ForegroundTarget = .none
    private var generation = 0
    private var codexSnapshot: UsageSnapshot?
    private var lastOfficialSnapshot: UsageSnapshot?
    private var zcodeSnapshot = ZCodeUsageSnapshot.placeholder
    private var zcodeLoaded = false
    private var lastRemoteSuccess: [ForegroundTarget: Date] = [:]
    private var resetDeadline: Date?
    private var lastFailure: String?
    private let displayConfigurationURL: URL
    private var lastDisplayConfigurationFailure: String?

    init(configuration: UsageStoreConfiguration) {
        codexLoader = CodexUsageLoader(configuration: configuration)
        displayConfigurationURL = DisplayConfiguration.fileURL(codexHome: configuration.codexHome)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        reloadDisplayConfiguration()
        UserDefaults.standard.set(false, forKey: "DFRSystemModalShowsCloseBox")
        frontmostMonitor = FrontmostAppMonitor(targetNames: targetApplicationNames()) { [weak self] target in
            self?.handleTargetChange(target)
        }
        frontmostMonitor?.start()
        preloadTask = Task { [weak self] in
            guard let self else { return }
            let cached = try? await codexLoader.cached()
            guard !Task.isCancelled else { return }
            if codexSnapshot == nil, let cached {
                codexSnapshot = cached
                if ["app-server", "remote"].contains(cached.source) { lastOfficialSnapshot = cached }
                touchBarController.update(cached)
            }
            let cachedZCode = await zcodeStore.cachedSnapshot()
            guard !Task.isCancelled else { return }
            if !zcodeLoaded {
                zcodeSnapshot = cachedZCode
                touchBarController.update(cachedZCode)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopRefresh()
        preloadTask?.cancel()
        touchBarController.hideImmediately()
    }

    private func handleTargetChange(_ next: ForegroundTarget) {
        guard target != next else { return }
        if next == .codex { reloadDisplayConfiguration() }
        stopRefresh()
        generation += 1
        target = next
        if next == .none {
            touchBarController.hideAnimated()
            return
        }
        if next == .codex { touchBarController.update(codexSnapshot ?? .placeholder) }
        else { touchBarController.update(zcodeSnapshot) }
        touchBarController.show(for: next)
        scheduleStartup()
    }

    private func scheduleStartup() {
        startup?.cancel()
        statsContinuation?.cancel()
        let expected = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == expected, self.target != .none else { return }
            self.startRefresh()
        }
        startup = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func startRefresh() {
        let expected = generation
        localTimer?.invalidate()
        remoteTimer?.invalidate()
        refreshRemote()
        refreshLocal()
        localTimer = Timer.scheduledTimer(withTimeInterval: target == .codex ? 3 : 15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == expected else { return }
                self.refreshLocal()
            }
        }
        localTimer?.tolerance = 0.5
        remoteTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == expected else { return }
                self.refreshRemote()
            }
        }
        remoteTimer?.tolerance = 3
        configureResetTimer()
    }

    private func stopRefresh() {
        startup?.cancel()
        statsContinuation?.cancel()
        localTimer?.invalidate()
        remoteTimer?.invalidate()
        resetTimer?.invalidate()
        localTimer = nil
        remoteTimer = nil
        resetTimer = nil
        for task in localTasks.values { task.cancel() }
        for task in remoteTasks.values { task.cancel() }
        // Occupy task slots until cancellation has actually completed.
    }

    private func refreshLocal() {
        if target == .codex { reloadDisplayConfiguration() }
        let requestedTarget = target
        let expected = generation
        guard requestedTarget != .none, localTasks[requestedTarget] == nil else { return }
        localTasks[requestedTarget] = Task { [weak self] in
            guard let self else { return }
            defer {
                localTasks[requestedTarget] = nil
                if target == requestedTarget, generation != expected { refreshLocal() }
            }
            if requestedTarget == .codex {
                let local = await codexLoader.local()
                guard !Task.isCancelled, target == requestedTarget, generation == expected,
                      let current = codexSnapshot else { return }
                let merged = current.mergingLocalTokenUsage(from: local)
                codexSnapshot = merged
                touchBarController.update(merged)
            } else {
                let snapshot = await zcodeStore.refreshLocal()
                guard !Task.isCancelled, target == requestedTarget, generation == expected else { return }
                zcodeLoaded = true
                zcodeSnapshot = snapshot
                touchBarController.update(snapshot)
                if !snapshot.statsReady {
                    statsContinuation?.cancel()
                    let work = DispatchWorkItem { [weak self] in
                        guard let self, self.target == .zcode, self.generation == expected else { return }
                        self.refreshLocal()
                    }
                    statsContinuation = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
                }
            }
        }
    }

    private func refreshRemote() {
        let requestedTarget = target
        let expected = generation
        guard requestedTarget != .none, remoteTasks[requestedTarget] == nil else { return }
        let interval: TimeInterval = requestedTarget == .codex && (resetDeadline ?? .distantPast) > Date() ? 8 : 30
        if let last = lastRemoteSuccess[requestedTarget], Date().timeIntervalSince(last) < interval { return }
        let requestStarted = Date()
        remoteTasks[requestedTarget] = Task { [weak self] in
            guard let self else { return }
            defer {
                remoteTasks[requestedTarget] = nil
                if target == requestedTarget, generation != expected { refreshRemote() }
            }
            if requestedTarget == .zcode {
                let snapshot = await zcodeStore.refreshRemote()
                guard !Task.isCancelled, target == requestedTarget, generation == expected else { return }
                zcodeLoaded = true
                lastRemoteSuccess[requestedTarget] = requestStarted
                zcodeSnapshot = snapshot
                touchBarController.update(snapshot)
                return
            }
            do {
                let snapshot = try await codexLoader.remote()
                guard !Task.isCancelled, target == requestedTarget, generation == expected else { return }
                guard ["app-server", "remote"].contains(snapshot.source) || codexSnapshot == nil else {
                    let description = snapshot.error ?? "official usage unavailable"
                    if lastFailure != description {
                        lastFailure = description
                        NSLog("CodexTouchBarHelper: official refresh unavailable: %@", description)
                    }
                    return
                }
                lastRemoteSuccess[requestedTarget] = requestStarted
                lastFailure = nil
                let previous = lastOfficialSnapshot
                let stable = previous?.stabilizingQuota(from: snapshot) ?? snapshot
                if let previous {
                    if stable.advancedPrimaryQuotaCycle(since: previous) { resetDeadline = nil }
                    else if snapshot.consumedResetCredit(since: previous) {
                        resetDeadline = Date().addingTimeInterval(180)
                    }
                }
                lastOfficialSnapshot = stable
                codexSnapshot = stable
                touchBarController.update(stable)
                configureResetTimer()
            } catch {
                if !Task.isCancelled { NSLog("CodexTouchBarHelper: remote refresh failed: %@", error.localizedDescription) }
            }
        }
    }

    private func configureResetTimer() {
        resetTimer?.invalidate()
        resetTimer = nil
        guard target == .codex, let deadline = resetDeadline, deadline > Date() else { return }
        let expected = generation
        resetTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.target == .codex, self.generation == expected else { return }
                if (self.resetDeadline ?? .distantPast) <= Date() {
                    self.resetDeadline = nil
                    self.resetTimer?.invalidate()
                    self.resetTimer = nil
                } else { self.refreshRemote() }
            }
        }
        resetTimer?.tolerance = 1
    }

    private func targetApplicationNames() -> Set<String> {
        let raw = ProcessInfo.processInfo.environment["CODEX_TOUCHBAR_TARGET_APPS"] ?? "Codex,ChatGPT,com.openai.codex"
        return Set(raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }

    private func reloadDisplayConfiguration() {
        do {
            let configuration = try DisplayConfiguration.load(from: displayConfigurationURL)
            touchBarController.updateDisplaySettings(configuration.display)
            lastDisplayConfigurationFailure = nil
        } catch {
            let message = String(describing: error)
            if message != lastDisplayConfigurationFailure {
                NSLog("CodexTouchBarHelper: invalid display configuration at %@; keeping last valid settings: %@",
                      displayConfigurationURL.path, message)
                lastDisplayConfigurationFailure = message
            }
        }
    }
}
