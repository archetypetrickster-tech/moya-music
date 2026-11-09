import AppKit

// A transparent part of the main window hosts the floating controls. No extra window or Space is created.
final class ChromeHostView: NSView {
    var onTopHover: ((Bool) -> Void)?
    var onLayout: (() -> Void)?
    private var tracking: NSTrackingArea?
    override var isOpaque: Bool { false }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved,.mouseEnteredAndExited,.activeAlways,.inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    private func hover(_ event: NSEvent) {
        onTopHover?(convert(event.locationInWindow,from:nil).y > bounds.maxY - 46)
    }
    override func mouseEntered(with event: NSEvent) { hover(event) }
    override func mouseMoved(with event: NSEvent) { hover(event) }
    override func mouseExited(with event: NSEvent) { onTopHover?(false) }
    override func layout() { super.layout(); onLayout?() }
}

enum FullScreenPhase {
    case windowed, entering, fullScreen, exiting
    var isTransitioning: Bool { self == .entering || self == .exiting }
}
enum PendingWindowAction { case hide, minimize, exit }

// Our size animation can be cancelled before macOS takes control of the window.
final class PlayerFrameAnimator: NSObject, NSAnimationDelegate {
    private var animation: NSViewAnimation?
    private var completion: (() -> Void)?
    func move(_ window: NSWindow, to frame: NSRect, completion: @escaping () -> Void) {
        cancel()
        let animation = NSViewAnimation(viewAnimations: [[
            .target: window,
            .startFrame: NSValue(rect: window.frame),
            .endFrame: NSValue(rect: frame)
        ]])
        self.animation = animation; self.completion = completion
        animation.duration = 0.24; animation.animationCurve = .easeInOut
        animation.animationBlockingMode = .nonblocking; animation.delegate = self
        animation.start()
    }
    func cancel() {
        let previous = animation
        animation = nil; completion = nil
        previous?.stop()
    }
    func animationDidEnd(_ animation: NSAnimation) {
        guard self.animation === animation else { return }
        let completed = completion
        self.animation = nil; completion = nil
        completed?()
    }
}

extension MusicApp {
    var usesNativeWindowControls: Bool {
        fullScreenPhase != .windowed || mini.styleMask.contains(.fullScreen)
    }
    var preservesSystemFrame: Bool {
        if usesNativeWindowControls || mini.isZoomed || mini.frame.width > 660 { return true }
        guard let bounds = mini.screen?.visibleFrame else { return false }
        let frame = mini.frame
        let gridWidth = [1.0, 0.5, 1.0/3.0, 2.0/3.0].contains { abs(frame.width - bounds.width * $0) <= 24 }
        let gridHeight = [1.0, 0.5].contains { abs(frame.height - bounds.height * $0) <= 32 }
        return gridWidth && gridHeight
    }
    var windowTopReserve: CGFloat { chromeGutter + chromeInset }
    var floatsChromeAboveCard: Bool {
        guard !preservesSystemFrame, let area = mini.screen?.visibleFrame else { return false }
        let frame = mini.frame
        return frame.minX > area.minX + 12 && frame.maxX < area.maxX - 12 && frame.minY > area.minY + 12 && frame.maxY < area.maxY - 12
    }
    func layoutPlayerColumn() {
        guard let root = surface, playerWidth != nil, queueWidth != nil, root.bounds.width >= 340 else { return }
        let heightLimit = compact ? 660 : max(340, root.bounds.height - chromeInset - 228)
        let width = min(660, root.bounds.width, heightLimit)
        if abs(playerWidth.constant - width) > 0.5 { playerWidth.constant = width }
        if abs(queueWidth.constant - (width - 32)) > 0.5 { queueWidth.constant = width - 32 }
    }
    func setupWindowChrome() {
        guard let root = mini.contentView else { return }
        chromeView = ChromeHoverView(frame: NSRect(x: 12, y: root.bounds.maxY - 35, width: 76, height: 24))
        chromeView.autoresizingMask = [.minYMargin]
        chromeView.alphaValue = 0
        chromeView.onHover = { [weak self] value in self?.revealChrome(value) }
        for (index, item) in [
            (ChromeButton.Kind.close, #selector(closePlayer), "Закрыть плеер"),
            (.minimize, #selector(minimizePlayer), "Свернуть плеер"),
            (.zoom, #selector(zoomPlayer), "На весь экран")
        ].enumerated() {
            let button = ChromeButton(frame: NSRect(x: 4 + index * 24, y: 5, width: 14, height: 14))
            button.kind = item.0; button.target = self; button.action = item.1
            button.isBordered = false; button.setButtonType(.momentaryChange)
            button.toolTip = item.2; button.setAccessibilityLabel(item.2)
            chromeView.addSubview(button)
        }
        root.addSubview(chromeView)
        positionChrome(); refreshChromeColors(); updateWindowControls()
    }
    func reconcileWindowState() {
        guard !fullScreenPhase.isTransitioning else { return }
        let phase: FullScreenPhase = mini.styleMask.contains(.fullScreen) ? .fullScreen : .windowed
        if phase != fullScreenPhase { fullScreenPhase = phase; updateWindowControls() }
    }
    func refreshChromeColors() {
        chromeView?.subviews.compactMap { $0 as? ChromeButton }.forEach { $0.parentActive = mini.isKeyWindow }
    }
    func updateWindowControls() {
        let native = usesNativeWindowControls
        for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            mini.standardWindowButton(type)?.isHidden = !native
        }
        chromeView?.isHidden = native
        if native { chromeHide?.cancel(); chromeView?.alphaValue = 0; chromeVisible = false }
        mini.isMovableByWindowBackground = !native
        surface?.layer?.cornerRadius = native ? 0 : 14
    }
    func updateChromeInset() {
        guard let host = mini?.contentView, let surface, playerTop != nil else { return }
        let gutter: CGFloat = floatsChromeAboveCard ? 30 : 0
        let inset: CGFloat = gutter > 0 ? 0 : (usesNativeWindowControls ? max(30, host.safeAreaInsets.top) : 30)
        chromeGutter = gutter
        let frame = NSRect(x:0,y:0,width:host.bounds.width,height:max(1,host.bounds.height-gutter))
        if surface.frame != frame { surface.frame = frame }
        if chromeInset != inset {
            chromeInset = inset
            playerTop.constant = inset; queueTop?.constant = 16 + inset
        }
    }
    func positionChrome() {
        guard let host = mini?.contentView, surface != nil else { return }
        updateChromeInset()
        let y = chromeGutter > 0 ? surface.frame.maxY + 2 : host.bounds.maxY - 35
        let frame = NSRect(x:12,y:y,width:76,height:24)
        if let chromeView, chromeView.frame != frame { chromeView.frame = frame }
    }
    func revealChrome(_ visible: Bool) {
        guard !usesNativeWindowControls else { return }
        chromeHide?.cancel()
        if visible { setChromeVisible(true) }
        else {
            let work = DispatchWorkItem { [weak self] in self?.setChromeVisible(false) }
            chromeHide = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        }
    }
    func setChromeVisible(_ visible: Bool) {
        guard chromeView != nil, visible != chromeVisible, !usesNativeWindowControls else { return }
        chromeVisible = visible; refreshChromeColors()
        if !visible { chromeView.updateGroupHover(false) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18; chromeView.animator().alphaValue = visible ? 1 : 0
        }
    }
    func cancelWindowTransition() {
        transitionGeneration += 1; frameAnimator.cancel()
        transitionSnapshot?.removeFromSuperview(); transitionSnapshot = nil
        for view in [playerContainer, overlayQueue] {
            view?.layer?.removeAllAnimations(); view?.alphaValue = 1
        }
        windowTransition = false; compactButton?.isEnabled = true
    }
    @objc func closePlayer() { mini.performClose(nil) }
    @objc func minimizePlayer() {
        reconcileWindowState()
        if usesNativeWindowControls {
            pendingWindowAction = .minimize
            if fullScreenPhase == .entering || fullScreenPhase == .exiting { return }
            toggleNativeFullScreen(); return
        }
        setChromeVisible(false); mini.miniaturize(nil)
    }
    @objc func zoomPlayer() {
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true && !usesNativeWindowControls { mini.zoom(nil) }
        else { toggleNativeFullScreen() }
    }
    @objc func toggleNativeFullScreen() {
        reconcileWindowState()
        if fullScreenPhase == .entering { pendingWindowAction = .exit; return }
        guard fullScreenPhase != .exiting else { return }
        cancelWindowTransition()
        mini.toggleFullScreen(nil)
    }
    func finishPendingWindowAction() {
        let action = pendingWindowAction; pendingWindowAction = nil
        switch action {
        case .hide: hidePlayerWindow()
        case .minimize: mini.miniaturize(nil)
        case .exit, .none: break
        }
    }
    func hidePlayerWindow() {
        setChromeVisible(false); mini.orderOut(nil)
        queueWatching = false
        web.evaluateJavaScript("window.__moyaQueue?.watch(false); null", completionHandler: nil)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === mini else { return true }
        reconcileWindowState()
        if usesNativeWindowControls {
            pendingWindowAction = .hide
            if !fullScreenPhase.isTransitioning {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.pendingWindowAction == .hide, !self.fullScreenPhase.isTransitioning else { return }
                    self.toggleNativeFullScreen()
                }
            }
        } else { hidePlayerWindow() }
        return false
    }
    func windowWillEnterFullScreen(_ notification: Notification) {
        guard notification.object as? NSWindow === mini else { return }
        cancelWindowTransition(); queueReturnFrame = nil
        fullScreenPhase = .entering; updateWindowControls()
    }
    func windowDidEnterFullScreen(_ notification: Notification) {
        guard notification.object as? NSWindow === mini else { return }
        fullScreenPhase = .fullScreen
        updateWindowControls(); positionChrome(); layoutPlayerColumn(); layoutQueueRegion()
        if pendingWindowAction != nil { toggleNativeFullScreen() }
    }
    func windowWillExitFullScreen(_ notification: Notification) {
        guard notification.object as? NSWindow === mini else { return }
        cancelWindowTransition(); fullScreenPhase = .exiting; updateWindowControls()
    }
    func windowDidExitFullScreen(_ notification: Notification) {
        guard notification.object as? NSWindow === mini else { return }
        fullScreenPhase = .windowed
        updateWindowControls(); configureWindowLimits(); positionChrome(); layoutPlayerColumn(); layoutQueueRegion()
        finishPendingWindowAction()
    }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        guard window === mini else { return }
        fullScreenPhase = .windowed
        updateWindowControls(); configureWindowLimits(); finishPendingWindowAction()
    }
    func windowDidFailToExitFullScreen(_ window: NSWindow) {
        guard window === mini else { return }
        fullScreenPhase = .fullScreen; pendingWindowAction = nil
        updateWindowControls()
    }
    func windowDidBecomeKey(_ notification: Notification) {
        if notification.object as? NSWindow === mini { reconcileWindowState(); refreshChromeColors(); updateWindowControls() }
    }
    func windowDidResignKey(_ notification: Notification) {
        if notification.object as? NSWindow === mini { refreshChromeColors() }
    }
    func windowDidMove(_ notification: Notification) {
        if notification.object as? NSWindow === mini { positionChrome() }
    }
    func windowDidResize(_ notification: Notification) {
        if notification.object as? NSWindow === mini {
            reconcileWindowState(); positionChrome(); layoutAmbient(); layoutPlayerColumn(); layoutQueueRegion()
        }
    }
    func windowWillStartLiveResize(_ notification: Notification) {
        if notification.object as? NSWindow === mini { cancelWindowTransition() }
    }
    func windowDidEndLiveResize(_ notification: Notification) {
        if notification.object as? NSWindow === mini { layoutPlayerColumn(); layoutQueueRegion() }
    }
    func windowDidChangeScreen(_ notification: Notification) {
        if notification.object as? NSWindow === mini { positionChrome(); layoutPlayerColumn(); layoutQueueRegion() }
    }
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize { frameSize }
}
