import AppKit

// Native segment hit testing and accessibility, with the player's own colors and icons.
final class SourceSwitch: NSSegmentedControl {
    private var thumb: CGFloat = 0
    private var thumbTarget: CGFloat = 0
    private var hover: CGFloat = 0
    private var hoverTarget: CGFloat = 0
    private var hoveredSegment = -1
    private var ticker: Timer?
    private var tracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        segmentCount = 2; trackingMode = .selectOne; segmentStyle = .rounded
        setLabel("Волна", forSegment: 0); setLabel("Моё", forSegment: 1)
        for index in 0...1 { setWidth(80, forSegment: index) }
        selectedSegment = 0
        font = .systemFont(ofSize: 11, weight: .medium)
        focusRingType = .none
        setAccessibilityLabel("Источник музыки")
        setToolTip("Персональные рекомендации", forSegment: 0)
        setToolTip("Понравившиеся треки", forSegment: 1)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: NSSize { NSSize(width:164,height:32) }
    func showSelection(_ index: Int, animated: Bool = true) {
        guard index == 0 || index == 1 else { return }
        selectedSegment = index
        thumbTarget = CGFloat(index)
        if !animated || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            thumb = thumbTarget; needsDisplay = true
        } else if abs(thumbTarget-thumb) > 0.002 { animate() }
    }
    override func viewDidHide() {
        super.viewDidHide(); hoveredSegment = -1; hover = 0; hoverTarget = 0
        thumb = thumbTarget; ticker?.invalidate(); ticker = nil; needsDisplay = true
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved,.mouseEnteredAndExited,.activeAlways,.inVisibleRect], owner:self)
        addTrackingArea(area); tracking = area
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { ticker?.invalidate(); ticker = nil }
    }
    private func updateHover(_ event: NSEvent) {
        let point = convert(event.locationInWindow,from:nil)
        if bounds.contains(point) {
            hoveredSegment = point.x < bounds.midX ? 0 : 1
            hoverTarget = 1
        } else { hoverTarget = 0 }
        animate()
    }
    override func mouseMoved(with event: NSEvent) { updateHover(event) }
    override func mouseEntered(with event: NSEvent) { updateHover(event) }
    override func mouseExited(with event: NSEvent) { hoverTarget = 0; animate() }
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        showSelection(selectedSegment)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 123 || event.keyCode == 124 {
            showSelection(event.keyCode == 123 ? 0 : 1)
            sendAction(action, to: target)
        } else { super.keyDown(with:event) }
    }
    private func animate() {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            thumb = thumbTarget; hover = hoverTarget; needsDisplay = true; return
        }
        guard ticker == nil else { return }
        let timer = Timer(timeInterval:1.0/60, repeats:true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.thumb += (self.thumbTarget - self.thumb) * 0.3
            self.hover += (self.hoverTarget - self.hover) * 0.3
            self.needsDisplay = true
            if abs(self.thumbTarget-self.thumb)+abs(self.hoverTarget-self.hover) < 0.002 {
                self.thumb = self.thumbTarget; self.hover = self.hoverTarget
                self.ticker?.invalidate(); self.ticker = nil
            }
        }
        ticker = timer; RunLoop.main.add(timer,forMode:.common)
    }
    override func draw(_ dirtyRect: NSRect) {
        let capsule = NSBezierPath(roundedRect:bounds,xRadius:11,yRadius:11)
        NSColor.white.withAlphaComponent(0.045).setFill(); capsule.fill()
        let inner = bounds.insetBy(dx:2,dy:2), width = inner.width/2
        NSColor.white.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect:NSRect(x:inner.minX+thumb*width,y:inner.minY,width:width,height:inner.height),xRadius:9,yRadius:9).fill()
        for index in 0...1 {
            let active = 1 - min(1,abs(thumb-CGFloat(index)))
            let normal = NSColor.white.withAlphaComponent(0.62 + (hoveredSegment == index ? hover * 0.24 : 0))
            let color = normal.blended(withFraction:active,of:.yellow) ?? normal
            let text = (index == 0 ? "Волна" : "Моё") as NSString
            let attributes: [NSAttributedString.Key:Any] = [.font:font ?? NSFont.systemFont(ofSize:11,weight:.medium),.foregroundColor:color]
            let textSize = text.size(withAttributes:attributes)
            let start = inner.minX+CGFloat(index)*width+(width-16-7-textSize.width)/2
            IconLibrary.draw(IconLibrary.image(index == 0 ? "audio-waveform" : "heart",size:16),in:NSRect(x:start,y:bounds.midY-8,width:16,height:16),color:color)
            text.draw(at:NSPoint(x:start+23,y:bounds.midY-textSize.height/2),withAttributes:attributes)
        }
        if window?.firstResponder === self {
            NSColor.white.withAlphaComponent(0.25).setStroke(); capsule.lineWidth = 1; capsule.stroke()
        }
    }
}
