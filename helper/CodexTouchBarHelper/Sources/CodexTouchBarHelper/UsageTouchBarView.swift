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
        let row1Y: CGFloat = 0.0
        let row2Y: CGFloat = 15.0
        let textHeight: CGFloat = 15.0

        drawText("Codex", in: NSRect(x: 8, y: 7.0, width: 60, height: 17), font: codexFont, color: white, alignment: .left)

        drawText(UsageFormatting.windowLabel(snapshot.primary), in: NSRect(x: 75, y: row1Y, width: 43, height: textHeight), font: labelFont, color: white, alignment: .left)
        drawText(UsageFormatting.windowLabel(snapshot.secondary), in: NSRect(x: 75, y: row2Y, width: 43, height: textHeight), font: labelFont, color: white, alignment: .left)

        let barX: CGFloat = 124
        drawSegmentedBar(
            x: barX,
            y: row1Y + 4.5,
            usedPercent: snapshot.primary?.usedPercent,
            segments: 10,
            segmentWidth: 21,
            segmentHeight: 7.8,
            gap: 5.2
        )
        drawSegmentedBar(
            x: barX,
            y: row2Y + 4.5,
            usedPercent: snapshot.secondary?.usedPercent,
            segments: 10,
            segmentWidth: 21,
            segmentHeight: 7.8,
            gap: 5.2
        )

        let percentX: CGFloat = 396
        let dateX: CGFloat = 454
        let tokenX: CGFloat = 552

        drawText(
            UsageFormatting.balanceLabel(usedPercent: snapshot.primary?.usedPercent),
            in: NSRect(x: percentX, y: row1Y, width: 42, height: textHeight),
            font: valueFont,
            color: white,
            alignment: .right
        )
        drawText(
            UsageFormatting.balanceLabel(usedPercent: snapshot.secondary?.usedPercent),
            in: NSRect(x: percentX, y: row2Y, width: 42, height: textHeight),
            font: valueFont,
            color: white,
            alignment: .right
        )

        drawText(
            UsageFormatting.resetLabel(snapshot.primary?.resetsAt),
            in: NSRect(x: dateX, y: row1Y, width: 82, height: textHeight),
            font: smallMonoFont,
            color: muted,
            alignment: .left
        )
        drawText(
            UsageFormatting.resetLabel(snapshot.secondary?.resetsAt),
            in: NSRect(x: dateX, y: row2Y, width: 82, height: textHeight),
            font: smallMonoFont,
            color: muted,
            alignment: .left
        )

        let rows = UsageFormatting.tokenRows(snapshot)
        drawText(rows.0, in: NSRect(x: tokenX, y: row1Y, width: 150, height: textHeight), font: tokenFont, color: white, alignment: .left)
        drawText(rows.1, in: NSRect(x: tokenX, y: row2Y, width: 150, height: textHeight), font: tokenFont, color: white, alignment: .left)

        if snapshot.source == "placeholder" {
            drawActivityDots()
        } else if errorMessage != nil {
            drawErrorDot()
        }
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
