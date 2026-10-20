import AppKit
import CodexTouchBarCore

final class UsageTouchBarView: NSView {
    var snapshot: UsageSnapshot? = .placeholder {
        didSet {
            errorMessage = nil
            needsDisplay = true
        }
    }

    var errorMessage: String? {
        didSet {
            needsDisplay = true
        }
    }

    var displaySettings = DisplaySettings() {
        didSet { needsDisplay = true }
    }

    var displayLayout: UsageDisplayLayout {
        let current = snapshot ?? .placeholder
        return UsageDisplayLayout(
            quotaCount: displaySettings.quotaRows(for: current).count,
            tokenCount: displaySettings.tokenRows(for: current).count
        )
    }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 720, height: 30) }

    private let codexFont = NSFontManager.shared.convert(
        NSFont.systemFont(ofSize: 14.5, weight: .semibold),
        toHaveTrait: .italicFontMask
    )
    private let labelFont = NSFont.systemFont(ofSize: 12.7, weight: .semibold)
    private let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12.7, weight: .semibold)
    private let smallMonoFont = NSFont.monospacedDigitSystemFont(ofSize: 11.2, weight: .medium)
    private let tokenFont = NSFont.systemFont(ofSize: 11.4, weight: .semibold)

    private let white = NSColor(calibratedWhite: 0.94, alpha: 1)
    private let muted = NSColor(calibratedWhite: 0.78, alpha: 0.96)
    private let emptyFill = NSColor(calibratedRed: 0.15, green: 0.18, blue: 0.15, alpha: 1)
    private let emptyStroke = NSColor(calibratedRed: 0.25, green: 0.30, blue: 0.23, alpha: 0.9)
    private let green = NSColor(calibratedRed: 0.72, green: 1.0, blue: 0.38, alpha: 1)
    private let greenTop = NSColor(calibratedRed: 0.91, green: 1.0, blue: 0.68, alpha: 0.92)
    private let warning = NSColor(calibratedRed: 1.0, green: 0.76, blue: 0.28, alpha: 1)
    private let danger = NSColor(calibratedRed: 1.0, green: 0.36, blue: 0.32, alpha: 1)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        alphaValue = 0
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.clear.setFill()
        dirtyRect.fill()

        let snapshot = snapshot ?? .placeholder
        drawText("Codex", in: NSRect(x: 8, y: 7.0, width: 60, height: 17), font: codexFont, color: white, alignment: .left)

        let layout = displayLayout
        for (row, rect) in zip(displaySettings.quotaRows(for: snapshot), layout.quotaRects) {
            drawQuotaRow(row, snapshot: snapshot, in: rect)
        }
        for (text, rect) in zip(displaySettings.tokenRows(for: snapshot), layout.tokenRects) {
            drawText(text, in: rect, font: tokenFont, color: white, alignment: .left)
        }

        if snapshot.source == "placeholder" {
            drawActivityDots()
        } else if errorMessage != nil {
            drawErrorDot()
        }
    }

    private func drawQuotaRow(_ row: QuotaDisplayRow, snapshot: UsageSnapshot, in rect: NSRect) {
        let label: String
        let value: String
        let reset: Int?
        let usedPercent: Double?
        let isResetCard: Bool
        switch row {
        case .window(let window):
            label = UsageFormatting.windowLabel(window)
            value = UsageFormatting.balanceLabel(usedPercent: window?.usedPercent)
            reset = window?.resetsAt
            usedPercent = window?.usedPercent
            isResetCard = false
        case .resetCards:
            label = "重置卡"
            value = UsageFormatting.resetCreditCountLabel(snapshot.resetCreditsAvailable)
            reset = snapshot.resetCreditsExpiresAt
            usedPercent = nil
            isResetCard = true
        }

        let dateX = rect.maxX - 82
        let valueX = dateX - 54
        let barX = rect.minX + 49
        let barWidth = valueX - barX - 10
        drawText(label, in: NSRect(x: rect.minX, y: rect.minY, width: 43, height: 15), font: labelFont, color: white, alignment: .left)
        if isResetCard {
            drawResetCreditTickets(x: barX, y: rect.minY + 4.5, width: barWidth,
                                   availableCount: snapshot.resetCreditsAvailable, expiresAt: reset)
        } else {
            let segments = max(1, min(10, Int((barWidth + 5.2) / 16)))
            let gap: CGFloat = segments > 3 ? 5.2 : 3
            drawSegmentedBar(x: barX, y: rect.minY + 4.5, usedPercent: usedPercent,
                             segments: segments, segmentWidth: (barWidth - CGFloat(segments - 1) * gap) / CGFloat(segments),
                             segmentHeight: 7.8, gap: gap)
        }
        drawText(value, in: NSRect(x: valueX, y: rect.minY, width: 42, height: 15), font: valueFont,
                 color: isResetCard && snapshot.resetCreditsAvailable == 0 ? muted : white, alignment: .right)
        drawText(UsageFormatting.resetLabel(reset), in: NSRect(x: dateX, y: rect.minY, width: 82, height: 15),
                 font: smallMonoFont, color: muted, alignment: .left)
    }

    private func drawResetCreditTickets(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        availableCount: Int?,
        expiresAt: Int?
    ) {
        let count = max(0, availableCount ?? 0)
        let ticketWidth: CGFloat = min(28, width)
        let visibleCount = min(count, 7, max(1, Int((width + 5.5) / (ticketWidth + 5.5))))
        let ticketHeight: CGFloat = 7.8
        let gap: CGFloat = 5.5
        let color = resetCreditColor(availableCount: availableCount, expiresAt: expiresAt)

        if availableCount == nil || count == 0 {
            let rect = NSRect(x: x, y: y, width: ticketWidth, height: ticketHeight)
            let path = NSBezierPath(roundedRect: rect, xRadius: 2.6, yRadius: 2.6)
            emptyFill.setFill()
            path.fill()
            emptyStroke.withAlphaComponent(availableCount == nil ? 0.55 : 0.35).setStroke()
            path.lineWidth = 0.8
            path.stroke()
            return
        }

        for index in 0..<visibleCount {
            let left = x + CGFloat(index) * (ticketWidth + gap)
            let rect = NSRect(x: left, y: y, width: ticketWidth, height: ticketHeight)
            let path = NSBezierPath(roundedRect: rect, xRadius: 2.6, yRadius: 2.6)

            color.withAlphaComponent(0.17).setFill()
            path.fill()
            color.withAlphaComponent(0.78).setStroke()
            path.lineWidth = 0.85
            path.stroke()

            color.withAlphaComponent(0.52).setStroke()
            let divider = NSBezierPath()
            divider.move(to: NSPoint(x: left + 6.5, y: y + 1.8))
            divider.line(to: NSPoint(x: left + 6.5, y: y + ticketHeight - 1.8))
            divider.lineWidth = 0.75
            divider.stroke()

            greenTop.withAlphaComponent(0.42).setFill()
            NSBezierPath(
                roundedRect: NSRect(x: left + 9.5, y: y + 1.25, width: ticketWidth - 12, height: 1.35),
                xRadius: 0.7,
                yRadius: 0.7
            ).fill()
        }

        if count > visibleCount, width >= CGFloat(visibleCount) * (ticketWidth + gap) - gap + 16 {
            let plusX = x + CGFloat(visibleCount) * (ticketWidth + gap) - gap + 4
            drawText(
                "+",
                in: NSRect(x: plusX, y: y - 4, width: 12, height: 15),
                font: valueFont,
                color: color,
                alignment: .left
            )
        }
    }

    private func resetCreditColor(availableCount: Int?, expiresAt: Int?) -> NSColor {
        guard let availableCount, availableCount > 0 else { return emptyStroke }
        if let expiresAt,
           TimeInterval(expiresAt) - Date().timeIntervalSince1970 <= 24 * 60 * 60 {
            return warning
        }
        return green
    }

    private func drawText(
        _ text: String,
        in rect: NSRect,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byClipping
        (text as NSString).draw(
            in: rect,
            withAttributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }

    private func drawSegmentedBar(
        x: CGFloat,
        y: CGFloat,
        usedPercent: Double?,
        segments: Int,
        segmentWidth: CGFloat,
        segmentHeight: CGFloat,
        gap: CGFloat
    ) {
        let remaining = UsageFormatting.remainingPercent(usedPercent: usedPercent) ?? 0
        let segmentValue = 100.0 / Double(segments)

        for index in 0..<segments {
            let left = x + CGFloat(index) * (segmentWidth + gap)
            let rect = NSRect(x: left, y: y, width: segmentWidth, height: segmentHeight)
            let path = NSBezierPath(roundedRect: rect, xRadius: segmentHeight / 2, yRadius: segmentHeight / 2)

            emptyFill.setFill()
            path.fill()
            emptyStroke.setStroke()
            path.lineWidth = 0.8
            path.stroke()

            let start = Double(index) * segmentValue
            let end = Double(index + 1) * segmentValue
            let fillRatio: Double
            if remaining <= start {
                fillRatio = 0
            } else if remaining >= end {
                fillRatio = 1
            } else {
                fillRatio = (remaining - start) / segmentValue
            }
            guard fillRatio > 0 else { continue }

            let fillWidth = max(1.2, segmentWidth * CGFloat(fillRatio))
            let fillRect = NSRect(x: left, y: y, width: min(segmentWidth, fillWidth), height: segmentHeight)
            let isHealthy = remaining > 30
            let fillColor = fillColor(for: remaining)

            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            fillColor.setFill()
            fillRect.fill()
            let highlightRect = NSRect(
                x: left + 1.4,
                y: y + 1.1,
                width: max(0, min(segmentWidth, fillWidth) - 2.8),
                height: segmentHeight * 0.34
            )
            greenTop.withAlphaComponent(isHealthy ? 0.88 : 0.44).setFill()
            NSBezierPath(
                roundedRect: highlightRect,
                xRadius: highlightRect.height / 2,
                yRadius: highlightRect.height / 2
            ).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func fillColor(for remaining: Double) -> NSColor {
        if remaining <= 10 { return danger }
        if remaining <= 30 { return warning }
        return green
    }

    private func drawActivityDots() {
        let baseX: CGFloat = 701
        for index in 0..<4 {
            let alpha = 0.25 + CGFloat(index) * 0.16
            white.withAlphaComponent(alpha).setFill()
            NSBezierPath(ovalIn: NSRect(x: baseX + CGFloat(index) * 4.8, y: 11.5, width: 2.5, height: 2.5)).fill()
        }
    }

    private func drawErrorDot() {
        danger.setFill()
        NSBezierPath(ovalIn: NSRect(x: 706, y: 11.5, width: 4.5, height: 4.5)).fill()
    }
}

/// Two rows per quota column, with a token column allocated only when enabled.
struct UsageDisplayLayout {
    let quotaRects: [NSRect]
    let tokenRects: [NSRect]

    init(quotaCount: Int, tokenCount: Int) {
        let left: CGFloat = 75
        let right: CGFloat = 695 // Leave room for the existing status indicator.
        let gap: CGFloat = 14
        let tokenWidth: CGFloat = 150
        let columns = (quotaCount + 1) / 2
        let quotaRight = tokenCount > 0 ? right - tokenWidth - gap : right
        let columnWidth = columns > 0 ? (quotaRight - left - CGFloat(columns - 1) * gap) / CGFloat(columns) : 0
        quotaRects = (0..<quotaCount).map { index in
            NSRect(x: left + CGFloat(index / 2) * (columnWidth + gap), y: CGFloat(index % 2) * 15,
                   width: columnWidth, height: 15)
        }
        tokenRects = (0..<tokenCount).map { index in
            NSRect(x: columns > 0 ? right - tokenWidth : left, y: CGFloat(index) * 15,
                   width: columns > 0 ? tokenWidth : right - left, height: 15)
        }
    }
}
