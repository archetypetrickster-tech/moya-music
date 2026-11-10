import AppKit
import QuartzCore

final class ArtworkView: NSImageView {
    // Original navigationMyVibe_xs outline, drawn as a vector for the empty cover.
    private static let placeholderPoints: [NSPoint] = [
        NSPoint(x: 23.781, y: 9.35725),
        NSPoint(x: 23.7157, y: 8.8734),
        NSPoint(x: 19.7701, y: 7.94806),
        NSPoint(x: 21.8082, y: 4.90962),
        NSPoint(x: 21.5673, y: 4.58021),
        NSPoint(x: 18.3891, y: 6.14249),
        NSPoint(x: 18.7401, y: 1.89305),
        NSPoint(x: 18.3891, y: 1.71809),
        NSPoint(x: 16.4163, y: 5.12968),
        NSPoint(x: 14.0939, y: 0),
        NSPoint(x: 13.6558, y: 0),
        NSPoint(x: 14.2245, y: 5.02033),
        NSPoint(x: 8.41633, y: 0.374509),
        NSPoint(x: 7.91293, y: 0.50709),
        NSPoint(x: 12.3837, y: 6.14249),
        NSPoint(x: 3.50748, y: 3.17102),
        NSPoint(x: 3.09116, y: 3.63301),
        NSPoint(x: 11.0245, y: 8.14625),
        NSPoint(x: 0.110204, y: 9.07159),
        NSPoint(x: 0, y: 9.73176),
        NSPoint(x: 11.3537, y: 10.9646),
        NSPoint(x: 1.86395, y: 18.7596),
        NSPoint(x: 2.30204, y: 19.3542),
        NSPoint(x: 13.5456, y: 13.1885),
        NSPoint(x: 11.332, y: 24),
        NSPoint(x: 12.0109, y: 24),
        NSPoint(x: 16.351, y: 13.8281),
        NSPoint(x: 18.9809, y: 21.7762),
        NSPoint(x: 19.4408, y: 21.4235),
        NSPoint(x: 18.4544, y: 13.4536),
        NSPoint(x: 22.4653, y: 18.0106),
        NSPoint(x: 22.7075, y: 17.5486),
        NSPoint(x: 19.7265, y: 11.9118),
        NSPoint(x: 23.9565, y: 13.4099),
        NSPoint(x: 24, y: 12.9465),
        NSPoint(x: 20.4721, y: 10.1063),
        NSPoint(x: 23.781, y: 9.35725),
    ]
    override func draw(_ dirtyRect: NSRect) {
        guard image == nil else {
            super.draw(dirtyRect)
            return
        }
        let size = min(96, bounds.width * 0.28)
        let rect = NSRect(x: bounds.midX - size / 2, y: bounds.midY - size / 2, width: size, height: size)
        let path = NSBezierPath()
        for (index, point) in Self.placeholderPoints.enumerated() {
            let mapped = NSPoint(x: rect.minX + point.x * size / 24, y: rect.maxY - point.y * size / 24)
            if index == 0 { path.move(to: mapped) } else { path.line(to: mapped) }
        }
        path.close()
        NSColor.yellow.setFill()
        path.fill()
    }

    @available(macOS 27.0, *)
    override var cornerConfiguration: NSViewCornerConfiguration? { .corners(radius: .containerConcentric(6)) }
    @available(macOS 27.0, *)
    override func viewDidChangeEffectiveCornerRadii() {
        super.viewDidChangeEffectiveCornerRadii()
        if let radius = effectiveCornerRadii?.topLeft { layer?.cornerRadius = radius }
    }
    // Album artwork must never supply the layout's minimum window size.
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
    override func mouseDown(with event: NSEvent) {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        window.performDrag(with: event)
    }
}

final class PlayerSurface: NSVisualEffectView {
    @available(macOS 27.0, *)
    override var cornerConfiguration: NSViewCornerConfiguration? { .corners(radius: .containerConcentric) }
    var onTopHover: ((Bool) -> Void)?
    var onLayout: (() -> Void)?
    private var hoverArea: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self)
        addTrackingArea(area)
        hoverArea = area
    }
    private func checkHover(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onTopHover?(point.y > bounds.maxY - 46)
    }
    override func mouseMoved(with event: NSEvent) { checkHover(event) }
    override func mouseEntered(with event: NSEvent) { checkHover(event) }
    override func mouseExited(with event: NSEvent) { onTopHover?(false) }
    override func layout() {
        super.layout()
        onLayout?()
    }
    @available(macOS 27.0, *)
    override func viewDidChangeEffectiveCornerRadii() {
        super.viewDidChangeEffectiveCornerRadii()
        if let radius = effectiveCornerRadii?.topLeft, radius > 0 {
            layer?.cornerRadius = radius
            onLayout?()
        }
    }
}

final class ChromeButton: NSButton {
    enum Kind { case close, minimize, zoom }
    var kind: Kind = .close
    var parentActive = false { didSet { needsDisplay = true } }
    var groupHovered = false { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let colored = parentActive || groupHovered
        let color: NSColor
        if colored {
            switch kind {
            case .close: color = NSColor(srgbRed: 1, green: 0.373, blue: 0.341, alpha: 1)
            case .minimize: color = NSColor(srgbRed: 1, green: 0.741, blue: 0.180, alpha: 1)
            case .zoom: color = NSColor(srgbRed: 0.157, green: 0.788, blue: 0.251, alpha: 1)
            }
        } else {
            color = NSColor(srgbRed: 0.57, green: 0.57, blue: 0.59, alpha: 1)
        }
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
        (isHighlighted ? color.blended(withFraction: 0.18, of: .black)! : color).setFill()
        if let gradient = NSGradient(
            starting: color.blended(withFraction: 0.20, of: .white)!,
            ending: color.blended(withFraction: 0.06, of: .black)!)
        {
            gradient.draw(in: circle, angle: -90)
        } else {
            circle.fill()
        }
        NSGraphicsContext.saveGraphicsState()
        circle.addClip()
        NSColor.white.withAlphaComponent(colored ? 0.12 : 0.16).setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: bounds.minX + 2, y: bounds.midY + 0.5, width: bounds.width - 4,
                height: bounds.height * 0.40)
        ).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.black.withAlphaComponent(0.045).setStroke()
        circle.lineWidth = 0.5
        circle.stroke()
        guard groupHovered else { return }
        NSColor.black.withAlphaComponent(0.48).setStroke()
        NSColor.black.withAlphaComponent(0.48).setFill()
        let x = bounds.midX
        let y = bounds.midY
        let mark = NSBezierPath()
        mark.lineWidth = 1.0
        mark.lineCapStyle = .round
        switch kind {
        case .close:
            mark.move(to: NSPoint(x: x - 2.4, y: y - 2.4))
            mark.line(to: NSPoint(x: x + 2.4, y: y + 2.4))
            mark.move(to: NSPoint(x: x - 2.4, y: y + 2.4))
            mark.line(to: NSPoint(x: x + 2.4, y: y - 2.4))
            mark.stroke()
        case .minimize:
            mark.move(to: NSPoint(x: x - 3, y: y))
            mark.line(to: NSPoint(x: x + 3, y: y))
            mark.stroke()
        case .zoom:
            mark.move(to: NSPoint(x: x - 3, y: y - 3))
            mark.line(to: NSPoint(x: x - 3, y: y + 1))
            mark.line(to: NSPoint(x: x + 1, y: y - 3))
            mark.close()
            mark.move(to: NSPoint(x: x + 3, y: y + 3))
            mark.line(to: NSPoint(x: x + 3, y: y - 1))
            mark.line(to: NSPoint(x: x - 1, y: y + 3))
            mark.close()
            mark.fill()
        }
    }
}

final class ChromeHoverView: NSView {
    var onHover: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }
    func updateGroupHover(_ value: Bool) {
        for case let button as ChromeButton in subviews { button.groupHovered = value }
    }
    override func mouseEntered(with event: NSEvent) {
        updateGroupHover(true)
        onHover?(true)
    }
    override func mouseExited(with event: NSEvent) {
        updateGroupHover(false)
        onHover?(false)
    }
}

final class TrackTitle: NSTextField {
    var onOpen: (() -> Void)?
    var linkEnabled = false { didSet { needsDisplay = true } }
    private var hoverTarget: CGFloat = 0
    private var hoverAmount: CGFloat = 0
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { if linkEnabled { addCursorRect(bounds, cursor: .pointingHand) } }
    override func mouseEntered(with event: NSEvent) { hoverTarget = linkEnabled ? 1 : 0 }
    override func mouseExited(with event: NSEvent) { hoverTarget = 0 }
    override func viewDidHide() {
        super.viewDidHide()
        hoverTarget = 0
        hoverAmount = 0
        needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if linkEnabled && bounds.contains(convert(event.locationInWindow, from: nil)) { onOpen?() }
    }
    override func accessibilityPerformPress() -> Bool {
        guard linkEnabled else { return false }
        onOpen?()
        return true
    }
    private var offset: CGFloat = 0
    private var started = ProcessInfo.processInfo.systemUptime
    private var ticker: Timer?
    override var stringValue: String {
        didSet {
            if stringValue != oldValue {
                offset = 0
                started = ProcessInfo.processInfo.systemUptime
                needsDisplay = true
            }
        }
    }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 32) }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        ticker?.invalidate()
        if window != nil {
            ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                self?.advance()
            }
        }
    }
    private func advance() {
        if abs(hoverTarget - hoverAmount) > 0.001 {
            hoverAmount +=
                (hoverTarget - hoverAmount)
                * (NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0.4)
            needsDisplay = true
        }
        let width = (stringValue as NSString).size(withAttributes: [
            .font: font ?? NSFont.systemFont(ofSize: 20, weight: .bold)
        ]).width
        guard width > bounds.width else {
            if offset != 0 {
                offset = 0
                needsDisplay = true
            }
            return
        }
        guard ProcessInfo.processInfo.systemUptime - started > 1.6 else { return }
        offset += 0.6
        if offset >= width + 36 {
            offset = 0
            started = ProcessInfo.processInfo.systemUptime
        }
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 20, weight: .bold),
            .foregroundColor: (textColor ?? NSColor.labelColor).withAlphaComponent(
                linkEnabled ? 0.86 + 0.14 * hoverAmount : 1),
        ]
        let text = stringValue as NSString
        let size = text.size(withAttributes: attributes)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds).addClip()
        let y = floor((bounds.height - size.height) / 2)
        text.draw(at: NSPoint(x: -offset, y: y), withAttributes: attributes)
        if size.width > bounds.width {
            text.draw(at: NSPoint(x: size.width + 36 - offset, y: y), withAttributes: attributes)
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

enum IconLibrary {
    private static var cache: [String: NSImage] = [:]
    static func image(_ name: String, size: CGFloat = 24) -> NSImage {
        let aliases = [
            "pin": "pushpin", "arrow.down.right.and.arrow.up.left": "minimize", "square.grid.2x2": "grid",
            "backward.end.fill": "skip-back", "forward.end.fill": "skip-forward", "heart.slash": "unlike",
            "waveform": "audio-waveform", "repeat.1": "repeat-one",
        ]
        let icon = aliases[name] ?? name
        let key = "\(icon)-\(size)"
        if let image = cache[key] { return image }
        guard let url = Bundle.main.url(forResource: icon, withExtension: "png", subdirectory: "Icons"),
            let image = NSImage(contentsOf: url)
        else { fatalError("Missing icon: \(icon)") }
        image.size = NSSize(width: size, height: size)
        image.isTemplate = true
        cache[key] = image
        return image
    }
    static func draw(_ image: NSImage, in rect: NSRect, color: NSColor) {
        let tinted = NSImage(size: image.size, flipped: false) { bounds in
            image.draw(in: bounds)
            color.setFill()
            bounds.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: rect)
    }
}

class HoverButton: NSButton {
    var selected = false { didSet { if selected != oldValue { animateFeedback() } } }
    private var mouseInside = false
    private var pressed = false
    private var ticker: Timer?
    private var tracking: NSTrackingArea?
    var hoverAmount: CGFloat = 0
    var selectionAmount: CGFloat = 0
    var pressAmount: CGFloat = 0
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseEntered(with event: NSEvent) {
        mouseInside = true
        animateFeedback()
    }
    override func mouseExited(with event: NSEvent) {
        mouseInside = false
        animateFeedback()
    }
    func resetFeedback() {
        mouseInside = false
        pressed = false
        hoverAmount = 0
        pressAmount = 0
        selectionAmount = selected ? 1 : 0
        ticker?.invalidate()
        ticker = nil
        needsDisplay = true
    }
    override func viewDidHide() {
        super.viewDidHide()
        resetFeedback()
    }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressed = true
        animateFeedback()
        super.mouseDown(with: event)
        pressed = false
        animateFeedback()
    }
    private func animateFeedback() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            let hover: CGFloat = self.mouseInside && self.isEnabled ? 1 : 0
            let selection: CGFloat = self.selected ? 1 : 0
            let press: CGFloat = self.pressed ? 1 : 0
            let speed: CGFloat = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0.32
            self.hoverAmount += (hover - self.hoverAmount) * speed
            self.selectionAmount += (selection - self.selectionAmount) * speed
            self.pressAmount += (press - self.pressAmount) * speed
            self.needsDisplay = true
            if abs(hover - self.hoverAmount) + abs(selection - self.selectionAmount)
                + abs(press - self.pressAmount) < 0.01
            {
                self.hoverAmount = hover
                self.selectionAmount = selection
                self.pressAmount = press
                self.ticker?.invalidate()
                self.ticker = nil
            }
        }
        ticker = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    var foreground: NSColor {
        guard isEnabled else { return NSColor.white.withAlphaComponent(0.25) }
        let normal = NSColor(calibratedWhite: 0.65 + hoverAmount * 0.25, alpha: 1)
        return normal.blended(withFraction: selectionAmount, of: .yellow) ?? normal
    }
}

final class IconButton: HoverButton {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(hoverAmount * 0.09 + pressAmount * 0.07 + selectionAmount * 0.04)
            .setFill()
        let side = min(bounds.width, bounds.height)
        let square = NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        NSBezierPath(roundedRect: square, xRadius: 11, yRadius: 11).fill()
        guard let image else { return }
        let size = image.size.width - pressAmount * 1.5
        IconLibrary.draw(
            image,
            in: NSRect(x: bounds.midX - size / 2, y: bounds.midY - size / 2, width: size, height: size),
            color: foreground)
    }
}

final class RoundPlayButton: HoverButton {
    var playing = false { didSet { if playing != oldValue { needsDisplay = true } } }
    override func draw(_ dirtyRect: NSRect) {
        let color = NSColor.yellow.blended(withFraction: hoverAmount * 0.15, of: .white) ?? .yellow
        color.withAlphaComponent(1 - pressAmount * 0.14).setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 1 + pressAmount, dy: 1 + pressAmount)).fill()
        let iconSize = min(27, bounds.width * 0.48)
        IconLibrary.draw(
            IconLibrary.image(playing ? "pause" : "play", size: iconSize),
            in: NSRect(
                x: bounds.midX - iconSize / 2, y: bounds.midY - iconSize / 2, width: iconSize,
                height: iconSize), color: NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.14, alpha: 1))
    }
}

final class PlayerSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let track = NSRect(x: rect.minX, y: rect.midY - 1, width: rect.width, height: 2)
        NSColor.white.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: track, xRadius: 1, yRadius: 1).fill()
        let fraction = CGFloat(max(0, min(1, (doubleValue - minValue) / max(1, maxValue - minValue))))
        NSColor.white.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: track.minX, y: track.minY, width: track.width * fraction, height: 2),
            xRadius: 1, yRadius: 1
        ).fill()
    }
    override func drawKnob(_ knobRect: NSRect) {
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: knobRect.midX - 3.5, y: knobRect.midY - 3.5, width: 7, height: 7))
            .fill()
    }
}
