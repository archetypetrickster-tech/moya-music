import AppKit
import WebKit
import CoreImage
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
            NSPoint(x: 23.781, y: 9.35725)
    ]
    override func draw(_ dirtyRect: NSRect) {
        guard image == nil else { super.draw(dirtyRect); return }
        let size = min(96, bounds.width * 0.28)
        let rect = NSRect(x: bounds.midX - size/2, y: bounds.midY - size/2, width: size, height: size)
        let path = NSBezierPath()
        for (index, point) in Self.placeholderPoints.enumerated() {
            let mapped = NSPoint(x: rect.minX + point.x * size / 24, y: rect.maxY - point.y * size / 24)
            if index == 0 { path.move(to: mapped) } else { path.line(to: mapped) }
        }
        path.close(); NSColor.yellow.setFill(); path.fill()
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
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
    }
    private func checkHover(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onTopHover?(point.y > bounds.maxY - 46)
    }
    override func mouseMoved(with event: NSEvent) { checkHover(event) }
    override func mouseEntered(with event: NSEvent) { checkHover(event) }
    override func mouseExited(with event: NSEvent) { onTopHover?(false) }
    override func layout() { super.layout(); onLayout?() }
    @available(macOS 27.0, *)
    override func viewDidChangeEffectiveCornerRadii() {
        super.viewDidChangeEffectiveCornerRadii()
        if let radius = effectiveCornerRadii?.topLeft, radius > 0 { layer?.cornerRadius = radius; onLayout?() }
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
        } else { color = NSColor(srgbRed: 0.57, green: 0.57, blue: 0.59, alpha: 1) }
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
        (isHighlighted ? color.blended(withFraction: 0.18, of: .black)! : color).setFill()
        if let gradient = NSGradient(starting: color.blended(withFraction: 0.20, of: .white)!, ending: color.blended(withFraction: 0.06, of: .black)!) {
            gradient.draw(in: circle, angle: -90)
        } else { circle.fill() }
        NSGraphicsContext.saveGraphicsState()
        circle.addClip()
        NSColor.white.withAlphaComponent(colored ? 0.12 : 0.16).setFill()
        NSBezierPath(ovalIn: NSRect(x: bounds.minX + 2, y: bounds.midY + 0.5, width: bounds.width - 4, height: bounds.height * 0.40)).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.black.withAlphaComponent(0.045).setStroke(); circle.lineWidth = 0.5; circle.stroke()
        guard groupHovered else { return }
        NSColor.black.withAlphaComponent(0.48).setStroke()
        NSColor.black.withAlphaComponent(0.48).setFill()
        let x = bounds.midX, y = bounds.midY
        let mark = NSBezierPath(); mark.lineWidth = 1.0; mark.lineCapStyle = .round
        switch kind {
        case .close:
            mark.move(to: NSPoint(x: x-2.4, y: y-2.4)); mark.line(to: NSPoint(x: x+2.4, y: y+2.4))
            mark.move(to: NSPoint(x: x-2.4, y: y+2.4)); mark.line(to: NSPoint(x: x+2.4, y: y-2.4)); mark.stroke()
        case .minimize:
            mark.move(to: NSPoint(x: x-3, y: y)); mark.line(to: NSPoint(x: x+3, y: y)); mark.stroke()
        case .zoom:
            mark.move(to: NSPoint(x: x-3, y: y-3)); mark.line(to: NSPoint(x: x-3, y: y+1)); mark.line(to: NSPoint(x: x+1, y: y-3)); mark.close()
            mark.move(to: NSPoint(x: x+3, y: y+3)); mark.line(to: NSPoint(x: x+3, y: y-1)); mark.line(to: NSPoint(x: x-1, y: y+3)); mark.close(); mark.fill()
        }
    }
}

final class ChromeHoverView: NSView {
    var onHover: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
    }
    func updateGroupHover(_ value: Bool) {
        subviews.compactMap { $0 as? ChromeButton }.forEach { $0.groupHovered = value }
    }
    override func mouseEntered(with event: NSEvent) { updateGroupHover(true); onHover?(true) }
    override func mouseExited(with event: NSEvent) { updateGroupHover(false); onHover?(false) }
}

final class TrackTitle: NSTextField {
    var onOpen: (() -> Void)?
    var linkEnabled = false
    private var hoverTarget: CGFloat = 0
    private var hoverAmount: CGFloat = 0
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self)
        addTrackingArea(area); tracking = area
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { if linkEnabled { addCursorRect(bounds,cursor:.pointingHand) } }
    override func mouseEntered(with event: NSEvent) { hoverTarget = linkEnabled ? 1:0 }
    override func mouseExited(with event: NSEvent) { hoverTarget = 0 }
    override func viewDidHide() { super.viewDidHide(); hoverTarget = 0; hoverAmount = 0; needsDisplay = true }
    override func mouseDown(with event: NSEvent) { }
    override func mouseUp(with event: NSEvent) { if linkEnabled && bounds.contains(convert(event.locationInWindow,from:nil)) { onOpen?() } }
    override func accessibilityPerformPress() -> Bool { guard linkEnabled else { return false }; onOpen?(); return true }
    private var offset: CGFloat = 0
    private var started = ProcessInfo.processInfo.systemUptime
    private var ticker: Timer?
    override var stringValue: String {
        didSet {
            if stringValue != oldValue { offset = 0; started = ProcessInfo.processInfo.systemUptime; needsDisplay = true }
        }
    }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 32) }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        ticker?.invalidate()
        if window != nil {
            ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.advance() }
        }
    }
    private func advance() {
        if abs(hoverTarget-hoverAmount)>0.001 {
            hoverAmount += (hoverTarget-hoverAmount) * (NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1:0.4)
            needsDisplay = true
        }
        let width = (stringValue as NSString).size(withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 20, weight: .bold)]).width
        guard width > bounds.width else { offset = 0; needsDisplay = true; return }
        guard ProcessInfo.processInfo.systemUptime - started > 1.6 else { return }
        offset += 0.6
        if offset >= width + 36 { offset = 0; started = ProcessInfo.processInfo.systemUptime }
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        let attributes: [NSAttributedString.Key:Any] = [.font: font ?? NSFont.systemFont(ofSize: 20, weight: .bold), .foregroundColor:(textColor ?? NSColor.labelColor).withAlphaComponent(linkEnabled ? 0.86+0.14*hoverAmount:1)]
        let text = stringValue as NSString
        let size = text.size(withAttributes: attributes)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds).addClip()
        let y = floor((bounds.height - size.height) / 2)
        text.draw(at: NSPoint(x: -offset, y: y), withAttributes: attributes)
        if size.width > bounds.width { text.draw(at: NSPoint(x: size.width + 36 - offset, y: y), withAttributes: attributes) }
        NSGraphicsContext.restoreGraphicsState()
    }
}

enum IconLibrary {
    private static var cache: [String:NSImage] = [:]
    static func image(_ name: String, size: CGFloat = 24) -> NSImage {
        let aliases = ["pin":"pushpin", "arrow.down.right.and.arrow.up.left":"minimize", "square.grid.2x2":"grid", "backward.end.fill":"skip-back", "forward.end.fill":"skip-forward", "heart.slash":"unlike", "waveform":"audio-waveform", "repeat.1":"repeat-one"]
        let icon = aliases[name] ?? name
        let key = "\(icon)-\(size)"
        if let image = cache[key] { return image }
        guard let url = Bundle.main.url(forResource: icon, withExtension: "png", subdirectory: "Icons"), let image = NSImage(contentsOf: url) else { fatalError("Missing icon: \(icon)") }
        image.size = NSSize(width: size, height: size); image.isTemplate = true
        cache[key] = image
        return image
    }
    static func draw(_ image: NSImage, in rect: NSRect, color: NSColor) {
        let tinted = NSImage(size: image.size, flipped: false) { bounds in
            image.draw(in: bounds)
            color.setFill(); bounds.fill(using: .sourceAtop)
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
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { mouseInside = true; animateFeedback() }
    override func mouseExited(with event: NSEvent) { mouseInside = false; animateFeedback() }
    func resetFeedback() {
        mouseInside = false; pressed = false; hoverAmount = 0; pressAmount = 0
        selectionAmount = selected ? 1:0; ticker?.invalidate(); ticker = nil; needsDisplay = true
    }
    override func viewDidHide() { super.viewDidHide(); resetFeedback() }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressed = true; animateFeedback()
        super.mouseDown(with: event)
        pressed = false; animateFeedback()
    }
    private func animateFeedback() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let hover: CGFloat = self.mouseInside && self.isEnabled ? 1 : 0
            let selection: CGFloat = self.selected ? 1 : 0
            let press: CGFloat = self.pressed ? 1 : 0
            let speed: CGFloat = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0.32
            self.hoverAmount += (hover - self.hoverAmount) * speed
            self.selectionAmount += (selection - self.selectionAmount) * speed
            self.pressAmount += (press - self.pressAmount) * speed
            self.needsDisplay = true
            if abs(hover - self.hoverAmount) + abs(selection - self.selectionAmount) + abs(press - self.pressAmount) < 0.01 {
                self.hoverAmount = hover; self.selectionAmount = selection; self.pressAmount = press
                self.ticker?.invalidate(); self.ticker = nil
            }
        }
        ticker = timer; RunLoop.main.add(timer, forMode: .common)
    }
    var foreground: NSColor {
        guard isEnabled else { return NSColor.white.withAlphaComponent(0.25) }
        let normal = NSColor(calibratedWhite: 0.65 + hoverAmount * 0.25, alpha: 1)
        return normal.blended(withFraction: selectionAmount, of: .yellow) ?? normal
    }
}

final class IconButton: HoverButton {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(hoverAmount * 0.09 + pressAmount * 0.07 + selectionAmount * 0.04).setFill()
        let side = min(bounds.width,bounds.height)
        let square = NSRect(x:bounds.midX-side/2,y:bounds.midY-side/2,width:side,height:side)
        NSBezierPath(roundedRect:square,xRadius:11,yRadius:11).fill()
        guard let image else { return }
        let size = image.size.width - pressAmount * 1.5
        IconLibrary.draw(image, in: NSRect(x: bounds.midX - size / 2, y: bounds.midY - size / 2, width: size, height: size), color: foreground)
    }
}

final class RoundPlayButton: HoverButton {
    var playing = false { didSet { if playing != oldValue { needsDisplay = true } } }
    override func draw(_ dirtyRect: NSRect) {
        let color = NSColor.yellow.blended(withFraction: hoverAmount * 0.15, of: .white) ?? .yellow
        color.withAlphaComponent(1 - pressAmount * 0.14).setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 1 + pressAmount, dy: 1 + pressAmount)).fill()
        let iconSize = min(27, bounds.width * 0.48)
        IconLibrary.draw(IconLibrary.image(playing ? "pause" : "play", size: iconSize), in: NSRect(x: bounds.midX - iconSize/2, y: bounds.midY - iconSize/2, width: iconSize, height: iconSize), color: NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.14, alpha: 1))
    }
}

final class PlayerSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let track = NSRect(x: rect.minX, y: rect.midY - 1, width: rect.width, height: 2)
        NSColor.white.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: track, xRadius: 1, yRadius: 1).fill()
        let fraction = CGFloat(max(0, min(1, (doubleValue - minValue) / max(1, maxValue - minValue))))
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: track.width * fraction, height: 2), xRadius: 1, yRadius: 1).fill()
    }
    override func drawKnob(_ knobRect: NSRect) {
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: knobRect.midX - 3.5, y: knobRect.midY - 3.5, width: 7, height: 7)).fill()
    }
}

final class MusicApp: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    var web: WKWebView!
    var library: NSWindow!
    var mini: NSWindow!
    var popupWindows: [NSWindow] = []
    var statusItem: NSStatusItem!
    let cover = ArtworkView()
    let compactArtwork = ArtworkView()
    let titleLabel = TrackTitle(labelWithString: "Твоя музыка. Рядом.")
    let artistLabel = NSTextField(labelWithString: "Открой библиотеку и выбери трек")
    let progress = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let timeLabel = NSTextField(labelWithString: "0:00                                      0:00")
    var playButton: RoundPlayButton!
    var previousButton: IconButton!
    var nextButton: IconButton!
    var likeButton: IconButton!
    var dislikeButton: IconButton!
    var repeatButton: IconButton!
    var pinButton: IconButton!
    var settingsButton: IconButton!
    var alwaysOnTop = UserDefaults.standard.bool(forKey:"alwaysOnTop")
    var connectionSettings = ConnectionSettings.load()
    var artworkSession = URLSession(configuration:.default)
    let connectionPanel = ConnectionPanel(frame:.zero)
    var settingsOpen = false
    var sourceSwitch: SourceSwitch!
    var pendingSource: String?
    var pendingSourceAt = Date.distantPast
    var confirmedSource = "wave"
    let ambientView = NSView()
    let ambientSpin = CALayer()
    var surface: PlayerSurface!
    var chromeGutter: CGFloat = 30
    var chromeView: ChromeHoverView!
    var cardShadowWindow: NSPanel?
    var cardShadowSuspended = false
    var fullScreenPhase = FullScreenPhase.windowed
    var pendingWindowAction: PendingWindowAction?
    let frameAnimator = PlayerFrameAnimator()
    var transitionGeneration = 0
    weak var transitionSnapshot: NSImageView?
    var playerWidth: NSLayoutConstraint!
    var queueWidth: NSLayoutConstraint!
    var dockedQueueSuppressed = false
    var chromeHide: DispatchWorkItem?
    var chromeVisible = false
    let ambientContext = CIContext(options: [.cacheIntermediates: false])
    var controlsRow: NSStackView!
    var playerContainer: NSView!
    var playerTop: NSLayoutConstraint!
    var queueTop: NSLayoutConstraint!
    var chromeInset: CGFloat = 0
    var fullPlayerHeight: NSLayoutConstraint!
    var compactPlayerHeight: NSLayoutConstraint!
    var queueButton: IconButton!
    let overlayQueue = QueuePanel(frame: .zero)
    let dockedQueue = QueuePanel(frame: .zero)
    var queueOverlay = false
    var queueReturnFrame: NSRect?
    var queueWatching = false
    var queueFetching = false
    var dockedQueueVisible = false
    var windowTransition = false
    var lastQueue: [String:Any]?

    var artworkHeight: NSLayoutConstraint!
    var artworkContainer: NSView!
    var timeRow: NSStackView!
    let durationLabel = NSTextField(labelWithString: "0:00")
    var shuffleButton: IconButton!
    var compactButton: IconButton!
    var duration = 0.0
    var playing = false
    var compact = false
    var artworkURL = ""
    var artworkTask: URLSessionDataTask?
    var liveTest = ProcessInfo.processInfo.arguments.contains("--live-check")
    var selfTest = ProcessInfo.processInfo.arguments.contains("--self-test") || ProcessInfo.processInfo.arguments.contains("--window-test")
    let accent = NSColor.yellow

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.applicationIconImage = makeIcon()
        setupMenu()
        setupWeb()
        setupMini()
        setupStatusItem()
        if !selfTest { applyConnectionSettings() }
        if ProcessInfo.processInfo.arguments.contains("--debug") || liveTest {
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(inspectPlayer(_:)), name: Notification.Name("ru.ninesquares.moyamusic.inspect"), object: nil)
        }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(headphonesConnected(_:)), name: Notification.Name("ru.ninesquares.moyamusic.headphones"), object: nil)
        mini.makeKeyAndOrderFront(nil)
        updateCardShadow()
        NSApp.activate(ignoringOtherApps: true)
        for name in [NSWorkspace.willSleepNotification,NSWorkspace.didWakeNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(pauseOnWake),name:name,object:nil)
        }
        if selfTest { runSelfTest(); return }
        web.load(URLRequest(url: URL(string: "https://music.yandex.ru/")!))
        if liveTest || !UserDefaults.standard.bool(forKey: "hasPlayed") { showLibrary() }
        if liveTest {
            DispatchQueue.main.asyncAfter(deadline: .now() + 18) { self.reportLivePage() }
        }
    }

    func makeIcon() -> NSImage {
        NSImage(size: NSSize(width: 512, height: 512), flipped: false) { rect in
            NSColor(calibratedWhite: 0.09, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 112, yRadius: 112).fill()
            self.accent.setFill()
            for (i, h) in [100.0, 210, 290, 170, 90].enumerated() {
                NSBezierPath(roundedRect: NSRect(x: 118 + Double(i) * 56, y: (512-h)/2, width: 32, height: h), xRadius: 16, yRadius: 16).fill()
            }
            return true
        }
    }

    func setupMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Открыть библиотеку", action: #selector(showLibrary), keyEquivalent: "o").target = self
        appMenu.addItem(withTitle: "Показать плеер", action: #selector(showMini), keyEquivalent: "1").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Скрыть Мою музыку", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Завершить Мою музыку", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Правка"); editItem.submenu = edit
        for (name, selector, key) in [("Отменить", "undo:", "z"), ("Вырезать", "cut:", "x"), ("Копировать", "copy:", "c"), ("Вставить", "paste:", "v"), ("Выбрать всё", "selectAll:", "a")] {
            edit.addItem(withTitle: name, action: Selector(selector), keyEquivalent: key)
        }
        let windowItem = NSMenuItem(); main.addItem(windowItem)
        let windowMenu = NSMenu(title: "Окно"); windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Закрыть окно", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle:"Настройки…",action:#selector(showConnectionSettings),keyEquivalent:",").target = self
        windowMenu.addItem(withTitle: "Обновить библиотеку", action: #selector(reload), keyEquivalent: "r").target = self
        windowMenu.addItem(withTitle: "Свернуть плеер", action: #selector(minimizePlayer), keyEquivalent: "m").target = self
        let fullscreen = windowMenu.addItem(withTitle: "На весь экран / выйти", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullscreen.keyEquivalentModifierMask = [.control, .command]
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = main
    }

    func installWebScripts(_ controller: WKUserContentController) {
        controller.removeAllUserScripts()
        let bridgeURL = Bundle.main.url(forResource: "bridge", withExtension: "js")!
        let bridge = "window.__moyaPlaybackAllowed = \(UserDefaults.standard.bool(forKey:"autoplay") && !selfTest ? "true":"false");\n" + (try! String(contentsOf: bridgeURL, encoding: .utf8))
        controller.addUserScript(WKUserScript(source: bridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        if let queueURL = Bundle.main.url(forResource: "queue-engine", withExtension: "js"), let queueScript = try? String(contentsOf: queueURL, encoding: .utf8) {
            let history = UserDefaults.standard.array(forKey: "queueHistory") ?? []
            let historyData = (try? JSONSerialization.data(withJSONObject: history)) ?? Data("[]".utf8)
            let historyJSON = String(data: historyData, encoding: .utf8) ?? "[]"
            controller.addUserScript(WKUserScript(source: "if (/^music\\.yandex\\.(ru|com|by|kz|uz)$/.test(location.hostname)) { window.__moyaQueueHistory=\(historyJSON);\n" + queueScript + "\n}", injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
    }
    func setupWeb() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        if !selfTest { connectionSettings.apply(to:configuration.websiteDataStore,password:connectionSettings.enabled && !connectionSettings.username.isEmpty ? ConnectionSettings.password():"") }
        configuration.mediaTypesRequiringUserActionForPlayback = []
        if #available(macOS 14.0, *) { configuration.preferences.inactiveSchedulingPolicy = .none }
        installWebScripts(configuration.userContentController)
        configuration.userContentController.add(self, name: "music")
        web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = self; web.uiDelegate = self
        web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
        web.allowsBackForwardNavigationGestures = true
        library = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 740), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        library.title = "Моя музыка — библиотека Яндекса"
        library.contentMinSize = NSSize(width: 700, height: 500)
        library.contentView = web; library.delegate = self; library.isReleasedWhenClosed = false
        library.center()
    }

    func setupMini() {
        mini = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 540), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        mini.title = "Моя музыка"; mini.titleVisibility = .hidden
        mini.titlebarAppearsTransparent = true; mini.isMovableByWindowBackground = true
        mini.titlebarSeparatorStyle = .none
        mini.acceptsMouseMovedEvents = true
        mini.isOpaque = false; mini.backgroundColor = .clear; mini.hasShadow = false
        mini.minSize = NSSize(width: 340, height: 598)
        mini.minFullScreenContentSize = NSSize(width: 340, height: 598)
        mini.collectionBehavior = [.fullScreenPrimary, .fullScreenAllowsTiling]
        mini.tabbingMode = .disallowed
        mini.delegate = self; mini.isReleasedWhenClosed = false
        if !selfTest { mini.setFrameAutosaveName("MiniPlayer") }
        let host = ChromeHostView(frame: mini.contentView!.bounds)
        host.wantsLayer = true; host.layer?.backgroundColor = NSColor.clear.cgColor
        host.onTopHover = { [weak self] visible in self?.revealChrome(visible) }
        host.onLayout = { [weak self] in self?.positionChrome() }
        let root = PlayerSurface(frame: NSRect(x:0,y:0,width:host.bounds.width,height:max(1,host.bounds.height-30)))
        surface = root
        root.autoresizingMask = [.width,.height]
        root.wantsLayer = true; root.layer?.masksToBounds = true
        root.layer?.cornerCurve = .continuous; root.layer?.cornerRadius = 14
        root.onTopHover = { [weak self] visible in self?.revealChrome(visible) }
        root.onLayout = { [weak self] in self?.layoutAmbient(); self?.layoutPlayerColumn(); self?.layoutQueueRegion(); self?.updateCardShadow() }
        root.material = .hudWindow; root.blendingMode = .behindWindow; root.state = .active
        host.addSubview(root); mini.contentView = host
        ambientView.frame = root.bounds; ambientView.autoresizingMask = [.width, .height]
        ambientView.wantsLayer = true; ambientView.layer?.contentsGravity = .resizeAspectFill
        ambientView.layer?.masksToBounds = true; ambientView.alphaValue = 0.95
        ambientSpin.contentsGravity = .resizeAspectFill
        ambientView.layer?.addSublayer(ambientSpin)
        root.addSubview(ambientView)
        let shade = NSView(frame: root.bounds)
        shade.autoresizingMask = [.width, .height]; shade.wantsLayer = true
        shade.layer?.backgroundColor = NSColor(calibratedRed: 0.075, green: 0.075, blue: 0.105, alpha: 0.30).cgColor
        root.addSubview(shade)
        playerContainer = NSView()
        playerContainer.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(playerContainer)
        fullPlayerHeight = playerContainer.heightAnchor.constraint(equalTo: playerContainer.widthAnchor, constant: 228)
        compactPlayerHeight = playerContainer.heightAnchor.constraint(equalToConstant: 222)
        playerWidth = playerContainer.widthAnchor.constraint(equalToConstant: 340)
        playerTop = playerContainer.topAnchor.constraint(equalTo: root.topAnchor, constant: 0)
        NSLayoutConstraint.activate([
            playerContainer.centerXAnchor.constraint(equalTo: root.centerXAnchor), playerWidth!,
            playerTop!, fullPlayerHeight
        ])
        sourceSwitch = SourceSwitch(frame:.zero)
        sourceSwitch.target = self; sourceSwitch.action = #selector(sourceSwitchChanged(_:))
        sourceSwitch.translatesAutoresizingMaskIntoConstraints = false
        sourceSwitch.widthAnchor.constraint(equalToConstant:164).isActive = true
        sourceSwitch.heightAnchor.constraint(equalToConstant:32).isActive = true
        shuffleButton = iconButton("shuffle", "Случайный порядок", #selector(toggleShuffle), 16, 32)
        shuffleButton.isEnabled = false
        compactButton = iconButton("minimize-in", "Компактный вид", #selector(toggleCompact), 16, 32)
        let libraryButton = iconButton("square.grid.2x2", "Открыть библиотеку", #selector(showLibrary), 16, 32)
        repeatButton = iconButton("repeat", "Повтор выключен", #selector(toggleRepeat), 16, 32)
        repeatButton.isEnabled = false
        pinButton = iconButton("pushpin","Поверх окон",#selector(togglePin),16, 32)
        pinButton.selected = alwaysOnTop
        pinButton.image = IconLibrary.image(alwaysOnTop ? "pushpin-filled":"pushpin",size:16)
        let symbol = NSImage(systemSymbolName:"gearshape",accessibilityDescription:nil)!
        let shield = NSImage(size:NSSize(width:16,height:16),flipped:false) { rect in
            symbol.draw(in:rect); return true
        }
        shield.isTemplate = true
        settingsButton = IconButton(image:shield,target:self,action:#selector(showConnectionSettings))
        settingsButton.isBordered = false; settingsButton.bezelStyle = .regularSquare; settingsButton.focusRingType = .none; settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.widthAnchor.constraint(equalToConstant:32).isActive = true; settingsButton.heightAnchor.constraint(equalToConstant:32).isActive = true
        settingsButton.setAccessibilityLabel("Настройки")
        let proxyMenu = NSMenu()
        proxyMenu.addItem(withTitle:"Настройки…",action:#selector(showConnectionSettings),keyEquivalent:"").target = self
        settingsButton.menu = proxyMenu
        let top = NSStackView(views: [libraryButton, settingsButton!, sourceSwitch!, pinButton!, compactButton])
        top.orientation = .horizontal; top.spacing = 4; top.distribution = .equalSpacing; top.alignment = .centerY
        for artwork in [cover,compactArtwork] {
            artwork.image = nil
            artwork.contentTintColor = accent; artwork.imageScaling = .scaleProportionallyUpOrDown
            artwork.wantsLayer = true; artwork.layer?.cornerRadius = 6
            artwork.layer?.cornerCurve = .continuous; artwork.layer?.masksToBounds = true
            artwork.layer?.backgroundColor = NSColor(calibratedWhite:0.13,alpha:1).cgColor
        }
        compactArtwork.isHidden = true
        compactArtwork.translatesAutoresizingMaskIntoConstraints = false
        compactArtwork.widthAnchor.constraint(equalToConstant:64).isActive = true
        compactArtwork.heightAnchor.constraint(equalToConstant:64).isActive = true
        artworkContainer = NSView()
        cover.translatesAutoresizingMaskIntoConstraints = false
        artworkContainer.addSubview(cover)
        NSLayoutConstraint.activate([
            cover.centerXAnchor.constraint(equalTo: artworkContainer.centerXAnchor),
            cover.centerYAnchor.constraint(equalTo: artworkContainer.centerYAnchor),
            cover.heightAnchor.constraint(equalTo: artworkContainer.heightAnchor),
            cover.widthAnchor.constraint(equalTo: cover.heightAnchor),
            cover.widthAnchor.constraint(equalTo: artworkContainer.widthAnchor)
        ])
        titleLabel.onOpen = { [weak self] in self?.openCurrentTrackPage() }
        titleLabel.toolTip = "Открыть страницу песни в Яндекс Музыке"
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        artistLabel.font = .systemFont(ofSize: 14); artistLabel.textColor = .secondaryLabelColor
        for label in [titleLabel, artistLabel] {
            label.lineBreakMode = .byTruncatingTail; label.maximumNumberOfLines = 1
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        queueButton = IconButton(image: IconLibrary.image("playlist", size: 18), target: self, action: #selector(toggleQueue))
        queueButton.isBordered = false; queueButton.toolTip = "Очередь треков"; queueButton.setAccessibilityLabel("Открыть очередь треков")
        queueButton.translatesAutoresizingMaskIntoConstraints = false
        queueButton.widthAnchor.constraint(equalToConstant: 32).isActive = true
        queueButton.heightAnchor.constraint(equalToConstant: 32).isActive = true
        let artistRow = NSStackView(views: [artistLabel, NSView(), shuffleButton!, repeatButton!, queueButton!])
        artistRow.orientation = .horizontal; artistRow.alignment = .centerY; artistRow.spacing = 4
        let metadataLabels = NSStackView(views:[titleLabel,artistRow])
        metadataLabels.orientation = .vertical; metadataLabels.alignment = .leading; metadataLabels.spacing = 0
        for view in [titleLabel,artistRow] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo:metadataLabels.widthAnchor).isActive = true
        }
        let metadataRow = NSStackView(views:[compactArtwork,metadataLabels])
        metadataRow.orientation = .horizontal; metadataRow.alignment = .centerY; metadataRow.spacing = 12
        metadataRow.detachesHiddenViews = true
        progress.cell = PlayerSliderCell()
        progress.minValue = 0; progress.maxValue = 1; progress.doubleValue = 0
        progress.target = self; progress.action = #selector(seek); progress.isContinuous = false
        progress.controlSize = .small; progress.isEnabled = false
        timeLabel.stringValue = "0:00"
        for label in [timeLabel, durationLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            label.textColor = .secondaryLabelColor
        }
        durationLabel.alignment = .right
        timeRow = NSStackView(views: [timeLabel, NSView(), durationLabel])
        timeRow.orientation = .horizontal
        timeRow.heightAnchor.constraint(equalToConstant: 14).isActive = true
        for label in [timeLabel, durationLabel] { label.heightAnchor.constraint(equalToConstant: 14).isActive = true }
        playButton = RoundPlayButton(frame: .zero)
        playButton.target = self; playButton.action = #selector(togglePlay)
        playButton.isBordered = false; playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.setAccessibilityLabel("Воспроизвести / пауза")
        playButton.widthAnchor.constraint(equalToConstant: 56).isActive = true
        playButton.heightAnchor.constraint(equalToConstant: 56).isActive = true
        previousButton = iconButton("backward.end.fill", "Предыдущий трек", #selector(previous), 20)
        nextButton = iconButton("forward.end.fill", "Следующий трек", #selector(next), 20)
        likeButton = iconButton("heart", "Нравится", #selector(like), 20)
        dislikeButton = iconButton("heart.slash", "Не нравится", #selector(dislike), 20)
        likeButton.isEnabled = false; dislikeButton.isEnabled = false
        let controls = NSStackView(views: [dislikeButton, previousButton, playButton, nextButton, likeButton])
        controls.orientation = .horizontal; controls.distribution = .equalSpacing; controls.alignment = .centerY
        controlsRow = controls
        let stack = NSStackView(views: [top, artworkContainer, metadataRow, progress, timeRow, controls])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 0; stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(14, after: top)
        stack.setCustomSpacing(14, after: artworkContainer)
        stack.setCustomSpacing(8, after: metadataRow)
        stack.setCustomSpacing(2, after: progress)
        stack.setCustomSpacing(10, after: timeRow)
        playerContainer.addSubview(stack)
        for view in [top, artworkContainer!, metadataRow, progress, timeRow!] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        artworkHeight = artworkContainer.heightAnchor.constraint(equalTo: playerContainer.heightAnchor, constant: -260)
        artworkHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: playerContainer.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: playerContainer.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: playerContainer.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: playerContainer.bottomAnchor, constant: -16),
            top.heightAnchor.constraint(equalToConstant: 32),
            controls.heightAnchor.constraint(equalToConstant: 56),
            controls.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -36),
            controls.centerXAnchor.constraint(equalTo: stack.centerXAnchor),
            progress.heightAnchor.constraint(equalToConstant: 14),
            titleLabel.heightAnchor.constraint(equalToConstant: 32),
            artistLabel.heightAnchor.constraint(equalToConstant: 22),
            artworkHeight!
        ])
        setupQueuePanels(root: root)
        var initialFrame = mini.frame
        initialFrame.size = NSSize(width: 340, height: 598)
        mini.setFrame(initialFrame, display: false)
        mini.center()
        setupWindowChrome()
        layoutAmbient()
        if UserDefaults.standard.bool(forKey: "compact") { setCompact(true) }
        // Pin preference is stored independently from earlier versions.
    }

    func iconButton(_ symbol: String, _ help: String, _ action: Selector, _ size: CGFloat, _ edge: CGFloat = 32) -> IconButton {
        let image = IconLibrary.image(symbol, size: size)
        let button = IconButton(image: image, target: self, action: action)
        button.isBordered = false; button.toolTip = help; button.setAccessibilityLabel(help)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: edge).isActive = true
        button.heightAnchor.constraint(equalToConstant: edge).isActive = true
        return button
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = IconLibrary.image("audio-waveform", size: 18)
        let menu = NSMenu()
        for (title, action) in [("Показать плеер", #selector(showMini)), ("Воспроизвести / пауза", #selector(togglePlay)), ("Следующий трек", #selector(next)), ("Библиотека", #selector(showLibrary))] {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Завершить", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusItem.menu = menu
    }

    @objc func headphonesConnected(_ notification: Notification) {
        if !mini.isVisible { showMini() }
    }
    @objc func showLibrary() { library.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func showMini() { mini.makeKeyAndOrderFront(nil); layoutQueueRegion(); updateCardShadow(); NSApp.activate(ignoringOtherApps: true) }
    @objc func reload() { web.reload() }
    @objc func sourceSwitchChanged(_ sender: SourceSwitch) {
        let source = sender.selectedSegment == 0 ? "wave" : "likes"
        sender.showSelection(sender.selectedSegment)
        pendingSource = source; pendingSourceAt = Date()
        command(source)
    }
    @objc func togglePlay() { command("toggle") }
    @objc func next() { command("nexttrack") }
    @objc func previous() { command("previoustrack") }
    @objc func like() { command("like") }
    @objc func dislike() { command("dislike") }
    @objc func toggleRepeat() { command("repeat") }
    @objc func seek() { command("seekto", value: progress.doubleValue) }
    @objc func toggleShuffle() { command("shuffle") }
    @objc func toggleCompact() { setCompact(!compact) }
    func setCompact(_ enabled: Bool) {
        guard !windowTransition && !fullScreenPhase.isTransitioning else { return }
        if queueOverlay { closeQueueOverlay(); return }
        let oldFrame = mini.frame
        let preserveFrame = preservesSystemFrame
        let frozen = queueTransitionSnapshot()
        compact = enabled
        if frozen != nil { playerContainer.alphaValue = 0 }
        resetPlayerFeedback()
        fullPlayerHeight.isActive = false; compactPlayerHeight.isActive = false
        artworkHeight.isActive = !enabled
        artworkContainer.isHidden = enabled; compactArtwork.isHidden = !enabled; timeRow.isHidden = enabled
        if enabled { compactPlayerHeight.isActive = true } else { fullPlayerHeight.isActive = true }
        dockedQueue.isHidden = true; dockedQueueSuppressed = false
        mini.minSize = NSSize(width: 340, height: 252)
        var target = oldFrame
        if !preserveFrame {
            let height: CGFloat = (enabled ? 222 : min(target.width, 660) + 228) + windowTopReserve
            target.origin.y += target.height - height; target.size.height = height
        }
        compactButton.selected = enabled
        compactButton.image = IconLibrary.image(enabled ? "minimize" : "minimize-in", size: 16)
        compactButton.toolTip = enabled ? "Развернуть плеер" : "Компактный вид"
        animateQueueChange(to: target, showing: playerContainer, frozen: frozen)
        if !selfTest { UserDefaults.standard.set(enabled, forKey: "compact") }
    }
    func snapshotOverlay(_ source: NSView? = nil) -> NSImageView? {
        guard let root = surface, let content = source ?? playerContainer, let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return nil }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        let image = NSImage(size: content.bounds.size); image.addRepresentation(bitmap)
        let view = NSImageView(frame: content.convert(content.bounds,to:root))
        view.image = image; view.imageScaling = .scaleNone; view.imageAlignment = .alignTopLeft
        view.autoresizingMask = [.minXMargin,.maxXMargin,.minYMargin]
        root.addSubview(view); transitionSnapshot = view
        return view
    }
    func finishWindowTransition() {
        transitionSnapshot?.removeFromSuperview()
        transitionSnapshot = nil
        windowTransition = false; compactButton.isEnabled = true
        configureWindowLimits(); layoutPlayerColumn(); layoutQueueRegion()
    }
    func configureWindowLimits() {
        guard !fullScreenPhase.isTransitioning else { return }
        mini.minSize = NSSize(width: 340, height: (queueOverlay || !compact ? 568 : 222) + 30)
    }
    func setupQueuePanels(root: NSView) {
        for panel in [overlayQueue,dockedQueue] {
            root.addSubview(panel); panel.isHidden = true
            panel.onSelect = { [weak self] track in self?.selectQueueTrack(track) }
            panel.onTogglePlayback = { [weak self] in self?.togglePlay() }
        }
        overlayQueue.onBack = { [weak self] in self?.closeQueueOverlay() }
        root.addSubview(connectionPanel); connectionPanel.isHidden = true
        NSLayoutConstraint.activate([connectionPanel.leadingAnchor.constraint(equalTo:overlayQueue.leadingAnchor),connectionPanel.trailingAnchor.constraint(equalTo:overlayQueue.trailingAnchor),connectionPanel.topAnchor.constraint(equalTo:overlayQueue.topAnchor),connectionPanel.bottomAnchor.constraint(equalTo:overlayQueue.bottomAnchor)])
        connectionPanel.onBack = { [weak self] in self?.closeQueueOverlay() }
        connectionPanel.onSave = { [weak self] value,password in
            guard let self else { return "Плеер закрыт" }
            guard value.username.isEmpty || !password.isEmpty else { return "Введите пароль для указанного логина." }
            guard ConnectionSettings.savePassword(password) else { return "Не удалось сохранить пароль в Связке ключей." }
            self.connectionSettings = value; value.save(); self.web.stopLoading(); self.applyConnectionSettings()
            self.installWebScripts(self.web.configuration.userContentController)
            self.web.reload()
            return nil
        }
        dockedQueue.onBack = { [weak self] in self?.collapseDockedQueue() }
        overlayQueue.prepare(docked: false); dockedQueue.prepare(docked: true)
        dockedQueue.translatesAutoresizingMaskIntoConstraints = true
        dockedQueue.frame = NSRect(x:16,y:12,width:max(1,root.bounds.width-32),height:120)
        queueWidth = overlayQueue.widthAnchor.constraint(equalToConstant: 308)
        queueTop = overlayQueue.topAnchor.constraint(equalTo: root.topAnchor, constant: 16 + chromeInset)
        NSLayoutConstraint.activate([
            overlayQueue.centerXAnchor.constraint(equalTo: root.centerXAnchor), queueWidth!,
            queueTop!,
            overlayQueue.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16)
        ])
    }
    var basePlayerHeight: CGFloat { (compact ? 222 : (playerWidth?.constant ?? 340) + 228) + chromeInset }
    @objc func toggleQueue() { presentOverlay(settings:false) }
    func presentOverlay(settings: Bool) {
        guard !windowTransition && !fullScreenPhase.isTransitioning else { return }
        if queueOverlay { closeQueueOverlay(); return }
        let frozen = queueTransitionSnapshot()
        queueReturnFrame = mini.frame
        queueOverlay = true; settingsOpen = settings
        resetPlayerFeedback()
        if frozen != nil { (settings ? connectionPanel:overlayQueue).alphaValue = 0 }
        connectionPanel.isHidden = !settings
        overlayQueue.prepare(docked: false); overlayQueue.showLoading()
        playerContainer.isHidden = true; dockedQueue.isHidden = true; overlayQueue.isHidden = settings
        mini.minSize = NSSize(width: 340, height: 222)
        var frame = mini.frame
        if !preservesSystemFrame {
            let height = max(frame.height, min(frame.width, 660) + 228 + windowTopReserve)
            frame.origin.y += frame.height - height; frame.size.height = height
        }
        animateQueueChange(to: frame, showing: settings ? connectionPanel:overlayQueue, frozen: frozen)
        if !settings { fetchQueue() }
    }
    func closeQueueOverlay() {
        guard queueOverlay && !windowTransition else { return }
        let frozen = queueTransitionSnapshot()
        queueOverlay = false; settingsOpen = false
        resetPlayerFeedback()
        if frozen != nil { playerContainer.alphaValue = 0 }
        connectionPanel.isHidden = true; overlayQueue.isHidden = true; playerContainer.isHidden = false
        mini.minSize = NSSize(width: 340, height: 222)
        var frame = queueReturnFrame ?? mini.frame
        if preservesSystemFrame { frame = mini.frame }
        else {
            frame.origin.x = mini.frame.minX
            let height = max(frame.height, (compact ? 222 : min(frame.width, 660) + 228) + windowTopReserve)
            frame.origin.y = mini.frame.maxY - height; frame.size.height = height
        }
        queueReturnFrame = nil
        animateQueueChange(to: frame, showing: playerContainer, frozen: frozen)
    }
    func queueTransitionSnapshot() -> NSImageView? {
        guard mini.isVisible && !selfTest && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return nil }
        return snapshotOverlay(queueOverlay ? (settingsOpen ? connectionPanel:overlayQueue):playerContainer)
    }
    func animateQueueChange(to frame: NSRect, showing view: NSView, frozen: NSImageView?) {
        guard let frozen else {
            if !preservesSystemFrame && mini.frame != frame { mini.setFrame(frame, display: true) }
            view.alphaValue = 1; finishWindowTransition(); return
        }
        transitionGeneration += 1
        let generation = transitionGeneration
        windowTransition = true; compactButton.isEnabled = false
        view.alphaValue = 0
        let resize = !preservesSystemFrame && mini.frame != frame
        var sizeDone = !resize, fadeDone = false
        let complete = { [weak self] in
            guard let self, generation == self.transitionGeneration, sizeDone, fadeDone else { return }
            self.finishWindowTransition()
        }
        if resize { frameAnimator.move(mini,to:frame) { sizeDone = true; complete() } }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.20; context.timingFunction = CAMediaTimingFunction(name:.easeInEaseOut)
            frozen.animator().alphaValue = 0; view.animator().alphaValue = 1
        },completionHandler: { fadeDone = true; complete() })
    }
    func resetPlayerFeedback() {
        func clear(_ view: NSView) {
            (view as? HoverButton)?.resetFeedback()
            view.subviews.forEach(clear)
        }
        clear(playerContainer)
        queueButton?.selected = dockedQueueVisible || (queueOverlay && !settingsOpen)
    }
    static func trackPageURL(_ raw: String) -> URL? {
        guard var parts = URLComponents(url:URL(string:raw,relativeTo:URL(string:"https://music.yandex.ru"))?.absoluteURL ?? URL(fileURLWithPath:"/"),resolvingAgainstBaseURL:true),
              parts.scheme == "https",let host = parts.host,
              ["music.yandex.ru","music.yandex.com","music.yandex.by","music.yandex.kz","music.yandex.uz"].contains(host),
              parts.path.contains("/track/") else { return nil }
        parts.query = nil; parts.fragment = nil
        return parts.url
    }
    func openCurrentTrackPage() {
        web.evaluateJavaScript("window.__moyaQueue?.currentURL() || ''") { value,_ in
            guard let raw = value as? String,let url = Self.trackPageURL(raw) else { return }
            NSWorkspace.shared.open(url)
        }
    }
    func collapseDockedQueue() {
        if preservesSystemFrame { dockedQueueSuppressed = true; layoutQueueRegion(); return }
        var frame = mini.frame
        let height = basePlayerHeight + chromeGutter
        frame.origin.y += frame.height - height; frame.size.height = height
        mini.setFrame(frame, display: true)
    }
    func layoutQueueRegion() {
        guard playerContainer != nil, let root = surface, !windowTransition else { return }
        let available = root.bounds.height - basePlayerHeight - 20
        if available < 98 { dockedQueueSuppressed = false }
        let showDocked = !queueOverlay && !dockedQueueSuppressed && available >= 98
        let changed = showDocked != dockedQueueVisible
        dockedQueueVisible = showDocked
        let columnWidth = playerWidth?.constant ?? min(660, root.bounds.width)
        let frame = NSRect(x:(root.bounds.width-columnWidth)/2+16,y:12,width:max(1,columnWidth-32),height:showDocked ? available : 120)
        if dockedQueue.frame != frame { dockedQueue.frame = frame; dockedQueue.needsLayout = true }
        if dockedQueue.isHidden == showDocked { dockedQueue.isHidden = !showDocked }
        queueButton?.selected = showDocked || (queueOverlay && !settingsOpen)
        let wants = (queueOverlay && !settingsOpen) || showDocked
        if wants != queueWatching {
            queueWatching = wants
            web?.evaluateJavaScript("window.__moyaQueue?.watch(\(wants ? "true" : "false")); null", completionHandler: nil)
            if wants { fetchQueue() }
        } else if changed && showDocked { fetchQueue() }
    }
    func fetchQueue() {
        guard !queueFetching, !settingsOpen, queueOverlay || dockedQueueVisible else { return }
        queueFetching = true
        web.callAsyncJavaScript("return await window.__moyaQueue?.refresh()", arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self else { return }; self.queueFetching = false
            switch result {
            case .success(let value): if let data = value as? [String:Any] { self.applyQueue(data) }
            case .failure: self.overlayQueue.showError(); self.dockedQueue.showError()
            }
        }
    }
    func applyQueue(_ value: [String:Any]) {
        lastQueue = value; overlayQueue.apply(value); dockedQueue.apply(value)
    }
    func selectQueueTrack(_ track: QueueTrack) {
        guard let data = try? JSONSerialization.data(withJSONObject: ["id":track.id,"index":track.index,"url":track.url]), let json = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("(() => { const t=\(json); (window.__moyaMusic?.allowPlayback(),window.__moyaQueue?.select(t.id,t.index,t.url)).then(() => window.__moyaQueue?.refresh()).then(value=>{if(value)window.webkit.messageHandlers.music.postMessage({queueSnapshot:value})}); return true; })()", completionHandler: nil)
    }

    func command(_ action: String, value: Double = 0) {
        let safeValue = value.isFinite ? value : 0
        let script = """
        (() => {
          window.__moyaMusic?.command('\(action)', \(safeValue)).then(result => {
            window.webkit.messageHandlers.music.postMessage({commandResult: result});
          }).catch(() => window.webkit.messageHandlers.music.postMessage({commandResult:'unavailable'}));
          return true;
        })()
        """
        web.evaluateJavaScript(script) { _, error in
            if error != nil { self.showLibrary() }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let host = message.frameInfo.securityOrigin.host as String?,
              ["music.yandex.ru", "music.yandex.com", "music.yandex.by", "music.yandex.kz", "music.yandex.uz"].contains(host),
              let data = message.body as? [String: Any] else { return }
        if let history = data["queueHistory"] as? [[String:Any]] {
            if !selfTest { UserDefaults.standard.set(Array(history.suffix(150)), forKey: "queueHistory") }
            return
        }
        if let snapshot = data["queueSnapshot"] as? [String:Any] { applyQueue(snapshot); return }
        if data["queuePlayReady"] as? Bool == true {
            web.evaluateJavaScript("window.__moyaQueue?.startPendingTrack(true); null", completionHandler: nil); return
        }
        if data["startSource"] as? Bool == true {
            web.evaluateJavaScript("window.__moyaMusic?.startPendingSource(true); null", completionHandler: nil)
            return
        }
        if data["sourceFailed"] as? Bool == true {
            pendingSource = nil
            sourceSwitch.showSelection(confirmedSource == "wave" ? 0 : 1)
            artistLabel.stringValue = "Открой библиотеку и нажми «Слушать»"
            showLibrary(); return
        }
        if data["commandResult"] as? String == "unavailable" {
            artistLabel.stringValue = "Открой библиотеку для этого действия"
            showLibrary(); return
        }
        if data["commandResult"] != nil { return }
        update(data)
    }
    func update(_ data: [String: Any]) {
        let ready = data["ready"] as? Bool ?? false
        if titleLabel.linkEnabled != ready { titleLabel.linkEnabled = ready; mini.invalidateCursorRects(for:titleLabel) }
        if ready {
            titleLabel.stringValue = data["title"] as? String ?? ""
            artistLabel.stringValue = data["artist"] as? String ?? ""
            if !selfTest && !UserDefaults.standard.bool(forKey: "hasPlayed") { UserDefaults.standard.set(true, forKey: "hasPlayed") }
        }
        if let source = data["source"] as? String, ["wave","likes"].contains(source) {
            confirmedSource = source
            if pendingSource == source || Date().timeIntervalSince(pendingSourceAt) > 20 { pendingSource = nil }
            if pendingSource == nil { sourceSwitch.showSelection(source == "wave" ? 0 : 1, animated:!selfTest) }
        }
        playing = data["playing"] as? Bool ?? false
        playButton.playing = playing
        overlayQueue.updatePlayback(title: titleLabel.stringValue, artist: artistLabel.stringValue, playing: playing)
        dockedQueue.updatePlayback(title: titleLabel.stringValue, artist: artistLabel.stringValue, playing: playing)
        playButton.setAccessibilityLabel(playing ? "Пауза" : "Воспроизвести")
        likeButton.isEnabled = data["canLike"] as? Bool ?? false
        dislikeButton.isEnabled = data["canDislike"] as? Bool ?? false
        let liked = data["liked"] as? Bool ?? false
        let disliked = data["disliked"] as? Bool ?? false
        likeButton.image = IconLibrary.image(liked ? "heart-filled" : "heart", size: 20)
        dislikeButton.image = IconLibrary.image(disliked ? "unlike-filled" : "unlike", size: 20)
        likeButton.selected = liked
        dislikeButton.selected = disliked
        shuffleButton.isEnabled = data["canShuffle"] as? Bool ?? false
        shuffleButton.selected = data["shuffle"] as? Bool ?? false
        shuffleButton.toolTip = shuffleButton.isEnabled ? (shuffleButton.selected ? "Случайный порядок включён" : "Случайный порядок выключен") : "Волна сама подбирает порядок треков"
        repeatButton.isEnabled = data["canRepeat"] as? Bool ?? false
        let repeatMode = data["repeat"] as? String ?? "off"
        repeatButton.image = IconLibrary.image(repeatMode == "one" ? "repeat-one" : "repeat", size: 16)
        repeatButton.selected = repeatMode != "off"
        repeatButton.toolTip = repeatMode == "one" ? "Повтор одного трека" : repeatMode == "all" ? "Повтор всех треков" : "Повтор выключен"
        repeatButton.setAccessibilityLabel(repeatButton.toolTip!)
        duration = data["duration"] as? Double ?? 0
        let position = data["position"] as? Double ?? 0
        if duration > 0 {
            progress.maxValue = duration
            if !(progress.cell?.isHighlighted ?? false) { progress.doubleValue = position }
            timeLabel.stringValue = formatTime(position)
            durationLabel.stringValue = formatTime(duration)
        } else {
            progress.doubleValue = 0
            timeLabel.stringValue = "0:00"; durationLabel.stringValue = "0:00"
        }
        progress.isEnabled = duration > 0
        let url = data["artwork"] as? String ?? ""
        if url != artworkURL { loadArtwork(url) }
        statusItem.button?.toolTip = ready ? "\(titleLabel.stringValue) — \(artistLabel.stringValue)" : "Моя музыка"
    }
    func formatTime(_ value: Double) -> String {
        let seconds = value.isFinite ? max(0, Int(value)) : 0
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
    func setArtworkImage(_ image: NSImage?, animated: Bool) {
        for artwork in [cover,compactArtwork] {
            if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                let fade = CATransition(); fade.type = .fade; fade.duration = 0.35
                artwork.layer?.add(fade,forKey:"artworkFade")
            }
            artwork.image = image
        }
    }
    func loadArtwork(_ string: String) {
        artworkTask?.cancel(); artworkURL = string
        guard let url = URL(string: string), url.scheme == "https" else {
            setArtworkImage(nil,animated:false)
            setAmbient(nil); return
        }
        artworkTask = artworkSession.dataTask(with: url) { data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            let ambient = self.makeAmbient(data)
            DispatchQueue.main.async {
                if self.artworkURL == string {
                    self.setArtworkImage(image,animated:true); self.setAmbient(ambient)
                }
            }
        }
        artworkTask?.resume()
    }

    func makeAmbient(_ data: Data) -> CGImage? {
        guard let source = CIImage(data: data), source.extent.width > 0 else { return nil }
        let scale = 96 / max(source.extent.width, source.extent.height)
        let small = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let blurred = small.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 19])
            .cropped(to: small.extent)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 2.3, kCIInputBrightnessKey: -0.02, kCIInputContrastKey: 1.08])
        let exposed = blurred.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: -0.8])
        return ambientContext.createCGImage(exposed, from: small.extent)
    }
    func setAmbient(_ image: CGImage?) {
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let fade = CATransition(); fade.type = .fade; fade.duration = 1.1
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ambientSpin.add(fade, forKey: "ambientFade")
        }
        ambientSpin.contents = image
        layoutAmbient()
        if image != nil && ambientSpin.animation(forKey: "ambientRotation") == nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.fromValue = 0; rotation.toValue = Double.pi * 2
            rotation.duration = 100; rotation.repeatCount = .infinity
            rotation.timingFunction = CAMediaTimingFunction(name: .linear)
            rotation.isRemovedOnCompletion = false
            ambientSpin.add(rotation, forKey: "ambientRotation")
        }
    }
    func layoutAmbient() {
        let bounds = ambientView.bounds
        let side = hypot(bounds.width, bounds.height) * 1.12
        CATransaction.begin(); CATransaction.setDisableActions(true)
        ambientSpin.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        ambientSpin.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showMini(); return true }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if selfTest { completeSelfTest(); return }
        artistLabel.stringValue = "Открой библиотеку и выбери трек"
        webView.evaluateJavaScript("window.__moyaMusic?.startPendingSource(true); window.__moyaQueue?.watch(\(queueWatching ? "true" : "false")); null", completionHandler: nil)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        artistLabel.stringValue = "Не удалось загрузить. ⌘R — повторить"
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFailProvisionalNavigation: navigation, withError: error)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        artistLabel.stringValue = "Плеер остановился. ⌘R — перезапустить"
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.uiDelegate = self
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 720), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Вход в Яндекс"; window.contentView = popup; window.isReleasedWhenClosed = false
        popupWindows.append(window); window.center(); window.makeKeyAndOrderFront(nil)
        return popup
    }
    func webViewDidClose(_ webView: WKWebView) {
        popupWindows.filter { $0.contentView === webView }.forEach { $0.close() }
        popupWindows.removeAll { $0.contentView === webView }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if ["https", "http", "about", "file"].contains(url.scheme ?? "") { decisionHandler(.allow) }
        else { decisionHandler(.cancel) }
    }


}

let app = NSApplication.shared
let delegate = MusicApp()
app.delegate = delegate
app.run()
