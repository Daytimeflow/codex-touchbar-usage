import AppKit
import CodexTouchBarCore
import QuartzCore

final class TouchBarController: NSObject, NSTouchBarDelegate {
    private let itemIdentifier = NSTouchBarItem.Identifier("codex.touchbar.usage.item")
    private let trayIdentifier = "codex.touchbar.usage.tray" as NSString
    private let fadeInDuration: TimeInterval = 0.28
    private let fadeOutDuration: TimeInterval = 0.22
    private let usageView = UsageTouchBarView(frame: NSRect(x: 0, y: 0, width: 720, height: 30))
    private lazy var touchBar: NSTouchBar = {
        let touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [itemIdentifier]
        touchBar.customizationIdentifier = NSTouchBar.CustomizationIdentifier("codex.touchbar.usage")
        return touchBar
    }()
    private var isPresented = false
    private var showWorkItem: DispatchWorkItem?
    private var hideWorkItem: DispatchWorkItem?

    func show() {
        showWorkItem?.cancel()
        hideWorkItem?.cancel()
        usageView.snapshot = usageView.snapshot ?? .placeholder

        if !isPresented {
            usageView.alphaValue = 0
            presentSystemModalTouchBar()
            isPresented = true
        }

        let work = DispatchWorkItem { [weak self] in
            self?.fadeIn()
        }
        showWorkItem = work
        DispatchQueue.main.async(execute: work)
    }

    func hideAnimated() {
        showWorkItem?.cancel()
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.dismissSystemModalTouchBar()
        }
        hideWorkItem = work

        animateOpacity(to: 0, duration: fadeOutDuration, timing: CAMediaTimingFunction(name: .easeInEaseOut)) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: work)
        }
    }

    func hideImmediately() {
        showWorkItem?.cancel()
        hideWorkItem?.cancel()
        usageView.alphaValue = 0
        dismissSystemModalTouchBar()
    }

    private func fadeIn() {
        guard isPresented else { return }
        animateOpacity(to: 1, duration: fadeInDuration, timing: CAMediaTimingFunction(name: .easeOut)) { [weak self] in
            self?.usageView.alphaValue = 1
            self?.usageView.needsDisplay = true
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
            usageView.animator().alphaValue = alpha
        } completionHandler: {
            completionHandler?()
        }
    }

    func update(_ snapshot: UsageSnapshot) {
        usageView.snapshot = snapshot
        if isPresented {
            usageView.alphaValue = 1
            usageView.needsDisplay = true
        }
    }

    func updateError(_ message: String) {
        usageView.errorMessage = message
        if isPresented {
            usageView.alphaValue = 1
        }
        NSLog("CodexTouchBarHelper: update error %@", message)
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == itemIdentifier else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.customizationLabel = "Codex Usage"
        item.view = usageView
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
