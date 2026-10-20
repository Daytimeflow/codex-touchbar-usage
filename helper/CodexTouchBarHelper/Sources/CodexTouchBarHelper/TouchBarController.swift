import AppKit
import CodexTouchBarCore
import QuartzCore

private final class TouchBarContentView: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: 720, height: 30) }
}

final class TouchBarController: NSObject, NSTouchBarDelegate {
    private let usesSystemTouchBar: Bool

    init(usesSystemTouchBar: Bool = true) {
        self.usesSystemTouchBar = usesSystemTouchBar
        super.init()
    }
    private let itemIdentifier = NSTouchBarItem.Identifier("codex.touchbar.usage.item")
    private let trayIdentifier = "codex.touchbar.usage.tray" as NSString
    private let fadeInDuration: TimeInterval = 0.28
    private let fadeOutDuration: TimeInterval = 0.22
    private let usageView = UsageTouchBarView(frame: NSRect(x: 0, y: 0, width: 720, height: 30))
    private let zcodeView = ZCodeTouchBarView(frame: NSRect(x: 0, y: 0, width: 720, height: 30))
    private(set) var target: ForegroundTarget = .codex
    private var animationGeneration = 0
    private lazy var hostView: NSView = {
        let view = TouchBarContentView(frame: NSRect(x: 0, y: 0, width: 720, height: 30))
        view.wantsLayer = true
        usageView.alphaValue = 1
        view.addSubview(usageView)
        view.addSubview(zcodeView)
        zcodeView.isHidden = true
        view.alphaValue = 0
        return view
    }()
    private lazy var touchBar: NSTouchBar = {
        let touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [itemIdentifier]
        touchBar.customizationIdentifier = NSTouchBar.CustomizationIdentifier("codex.touchbar.usage")
        return touchBar
    }()
    private(set) var isPresented = false
    private var showWorkItem: DispatchWorkItem?
    private var hideWorkItem: DispatchWorkItem?

    func show(for next: ForegroundTarget = .codex) {
        showWorkItem?.cancel()
        hideWorkItem?.cancel()
        animationGeneration += 1
        _ = hostView
        let alreadyVisible = isPresented && hostView.alphaValue == 1
        target = next
        usageView.isHidden = next != .codex
        zcodeView.isHidden = next != .zcode
        usageView.snapshot = usageView.snapshot ?? .placeholder

        if !isPresented {
            hostView.alphaValue = 0
            presentSystemModalTouchBar()
            isPresented = true
        }
        if alreadyVisible { return }

        let expected = animationGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.animationGeneration == expected else { return }
            self.fadeIn()
        }
        showWorkItem = work
        DispatchQueue.main.async(execute: work)
    }

    func hideAnimated() {
        showWorkItem?.cancel()
        hideWorkItem?.cancel()
        animationGeneration += 1
        let expected = animationGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.animationGeneration == expected else { return }
            self.dismissSystemModalTouchBar()
        }
        hideWorkItem = work

        animateOpacity(to: 0, duration: fadeOutDuration, timing: CAMediaTimingFunction(name: .easeInEaseOut))
        // Background Touch Bar animations do not always deliver completion callbacks.
        DispatchQueue.main.asyncAfter(deadline: .now() + fadeOutDuration + 0.03, execute: work)
    }

    func hideImmediately() {
        showWorkItem?.cancel()
        hideWorkItem?.cancel()
        animationGeneration += 1
        hostView.alphaValue = 0
        dismissSystemModalTouchBar()
    }

    private func fadeIn() {
        guard isPresented else { return }
        let expected = animationGeneration
        animateOpacity(to: 1, duration: fadeInDuration, timing: CAMediaTimingFunction(name: .easeOut)) { [weak self] in
            guard let self, self.animationGeneration == expected else { return }
            self.hostView.alphaValue = 1
            self.hostView.needsDisplay = true
        }
    }

    private func animateOpacity(
        to alpha: CGFloat,
        duration: TimeInterval,
        timing: CAMediaTimingFunction,
        completionHandler: (() -> Void)? = nil
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = timing
            context.allowsImplicitAnimation = true
            hostView.animator().alphaValue = alpha
        } completionHandler: {
            completionHandler?()
        }
    }

    func update(_ snapshot: UsageSnapshot) {
        guard usageView.snapshot != snapshot else { return }
        usageView.snapshot = snapshot
        if isPresented && target == .codex {
            hostView.alphaValue = 1
            usageView.needsDisplay = true
        }
    }

    func updateDisplaySettings(_ settings: DisplaySettings) {
        guard usageView.displaySettings != settings else { return }
        usageView.displaySettings = settings
    }

    func update(_ snapshot: ZCodeUsageSnapshot) {
        var previous = zcodeView.snapshot
        previous.fetchedAt = snapshot.fetchedAt
        guard previous != snapshot else { return }
        zcodeView.snapshot = snapshot
        if isPresented && target == .zcode { zcodeView.needsDisplay = true }
    }

    func updateError(_ message: String) {
        usageView.errorMessage = message
        if isPresented {
            hostView.alphaValue = 1
        }
        NSLog("CodexTouchBarHelper: update error %@", message)
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == itemIdentifier else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.customizationLabel = "Codex Usage"
        item.view = hostView
        return item
    }

    private func presentSystemModalTouchBar() {
        performClassSelector("presentSystemModalTouchBar:systemTrayItemIdentifier:", first: touchBar, second: trayIdentifier)
    }

    private func dismissSystemModalTouchBar() {
        guard isPresented else { return }
        performClassSelector("dismissSystemModalTouchBar:", first: touchBar, second: nil)
        isPresented = false
    }

    private func performClassSelector(_ selectorName: String, first: AnyObject, second: AnyObject?) {
        guard usesSystemTouchBar else { return }
        let host = NSTouchBar.self as AnyObject
        let selector = NSSelectorFromString(selectorName)
        guard host.responds(to: selector) else {
            NSLog("CodexTouchBarHelper: NSTouchBar selector unavailable: \(selectorName)")
            return
        }
        if let second {
            _ = host.perform(selector, with: first, with: second)
        } else {
            _ = host.perform(selector, with: first)
        }
    }
}
