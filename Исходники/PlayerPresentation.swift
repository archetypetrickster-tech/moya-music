import AppKit
import QuartzCore
import WebKit

extension MusicApp {
    @objc func toggleCompact() { setCompact(!compact) }
    func setCompact(_ enabled: Bool) {
        guard !windowTransition && !fullScreenPhase.isTransitioning else { return }
        if queueOverlay {
            closeQueueOverlay()
            return
        }
        let oldFrame = mini.frame
        let preserveFrame = preservesSystemFrame
        let frozen = queueTransitionSnapshot()
        compact = enabled
        if frozen != nil { playerContainer.alphaValue = 0 }
        resetPlayerFeedback()
        fullPlayerHeight.isActive = false
        compactPlayerHeight.isActive = false
        artworkHeight.isActive = !enabled
        artworkContainer.isHidden = enabled
        compactArtwork.isHidden = !enabled
        timeRow.isHidden = enabled
        if enabled { compactPlayerHeight.isActive = true } else { fullPlayerHeight.isActive = true }
        dockedQueue.isHidden = true
        dockedQueueSuppressed = false
        mini.minSize = NSSize(width: 340, height: 252)
        var target = oldFrame
        if !preserveFrame {
            let height: CGFloat = (enabled ? 222 : min(target.width, 660) + 228) + windowTopReserve
            target.origin.y += target.height - height
            target.size.height = height
        }
        compactButton.selected = enabled
        compactButton.image = IconLibrary.image(enabled ? "minimize" : "minimize-in", size: 16)
        compactButton.toolTip = enabled ? "Развернуть плеер" : "Компактный вид"
        animateQueueChange(to: target, showing: playerContainer, frozen: frozen)
        if !selfTest { UserDefaults.standard.set(enabled, forKey: "compact") }
    }
    func snapshotOverlay(_ source: NSView? = nil) -> NSImageView? {
        guard let root = surface, let content = source ?? playerContainer,
            let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)
        else { return nil }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        let image = NSImage(size: content.bounds.size)
        image.addRepresentation(bitmap)
        let view = NSImageView(frame: content.convert(content.bounds, to: root))
        view.image = image
        view.imageScaling = .scaleNone
        view.imageAlignment = .alignTopLeft
        view.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        root.addSubview(view)
        transitionSnapshot = view
        return view
    }
    func finishWindowTransition() {
        transitionSnapshot?.removeFromSuperview()
        transitionSnapshot = nil
        windowTransition = false
        compactButton.isEnabled = true
        configureWindowLimits()
        layoutPlayerColumn()
        layoutQueueRegion()
    }
    func configureWindowLimits() {
        guard !fullScreenPhase.isTransitioning else { return }
        mini.minSize = NSSize(width: 340, height: (queueOverlay || !compact ? 568 : 222) + 30)
    }
    func setupQueuePanels(root: NSView) {
        for panel in [overlayQueue, dockedQueue] {
            root.addSubview(panel)
            panel.isHidden = true
            panel.onSelect = { [weak self] track in self?.selectQueueTrack(track) }
            panel.onTogglePlayback = { [weak self] in self?.togglePlay() }
        }
        overlayQueue.onBack = { [weak self] in self?.closeQueueOverlay() }
        root.addSubview(connectionPanel)
        connectionPanel.isHidden = true
        NSLayoutConstraint.activate([
            connectionPanel.leadingAnchor.constraint(equalTo: overlayQueue.leadingAnchor),
            connectionPanel.trailingAnchor.constraint(equalTo: overlayQueue.trailingAnchor),
            connectionPanel.topAnchor.constraint(equalTo: overlayQueue.topAnchor),
            connectionPanel.bottomAnchor.constraint(equalTo: overlayQueue.bottomAnchor),
        ])
        connectionPanel.onBack = { [weak self] in self?.closeQueueOverlay() }
        connectionPanel.onSave = { [weak self] value, password in
            guard let self else { return "Плеер закрыт" }
            guard value.username.isEmpty || !password.isEmpty else {
                return "Введите пароль для указанного логина."
            }
            guard ConnectionSettings.savePassword(password) else {
                return "Не удалось сохранить пароль в Связке ключей."
            }
            self.connectionSettings = value
            value.save()
            self.web.stopLoading()
            self.applyConnectionSettings()
            self.installWebScripts(self.web.configuration.userContentController)
            self.web.reload()
            return nil
        }
        dockedQueue.onBack = { [weak self] in self?.collapseDockedQueue() }
        overlayQueue.prepare(docked: false)
        dockedQueue.prepare(docked: true)
        dockedQueue.translatesAutoresizingMaskIntoConstraints = true
        dockedQueue.frame = NSRect(x: 16, y: 12, width: max(1, root.bounds.width - 32), height: 120)
        queueWidth = overlayQueue.widthAnchor.constraint(equalToConstant: 308)
        queueTop = overlayQueue.topAnchor.constraint(equalTo: root.topAnchor, constant: 16 + chromeInset)
        NSLayoutConstraint.activate([
            overlayQueue.centerXAnchor.constraint(equalTo: root.centerXAnchor), queueWidth!,
            queueTop!,
            overlayQueue.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
        ])
    }
    var basePlayerHeight: CGFloat { (compact ? 222 : (playerWidth?.constant ?? 340) + 228) + chromeInset }
    @objc func toggleQueue() { presentOverlay(settings: false) }
    func presentOverlay(settings: Bool) {
        guard !windowTransition && !fullScreenPhase.isTransitioning else { return }
        if queueOverlay {
            closeQueueOverlay()
            return
        }
        let frozen = queueTransitionSnapshot()
        queueReturnFrame = mini.frame
        queueOverlay = true
        settingsOpen = settings
        resetPlayerFeedback()
        if frozen != nil { (settings ? connectionPanel : overlayQueue).alphaValue = 0 }
        connectionPanel.isHidden = !settings
        overlayQueue.prepare(docked: false)
        overlayQueue.showLoading()
        playerContainer.isHidden = true
        dockedQueue.isHidden = true
        overlayQueue.isHidden = settings
        mini.minSize = NSSize(width: 340, height: 222)
        var frame = mini.frame
        if !preservesSystemFrame {
            let height = max(frame.height, min(frame.width, 660) + 228 + windowTopReserve)
            frame.origin.y += frame.height - height
            frame.size.height = height
        }
        animateQueueChange(to: frame, showing: settings ? connectionPanel : overlayQueue, frozen: frozen)
        if !settings { fetchQueue() }
    }
    func closeQueueOverlay() {
        guard queueOverlay && !windowTransition else { return }
        let frozen = queueTransitionSnapshot()
        queueOverlay = false
        settingsOpen = false
        resetPlayerFeedback()
        if frozen != nil { playerContainer.alphaValue = 0 }
        connectionPanel.isHidden = true
        overlayQueue.isHidden = true
        playerContainer.isHidden = false
        mini.minSize = NSSize(width: 340, height: 222)
        var frame = queueReturnFrame ?? mini.frame
        if preservesSystemFrame {
            frame = mini.frame
        } else {
            frame.origin.x = mini.frame.minX
            let height = max(frame.height, (compact ? 222 : min(frame.width, 660) + 228) + windowTopReserve)
            frame.origin.y = mini.frame.maxY - height
            frame.size.height = height
        }
        queueReturnFrame = nil
        animateQueueChange(to: frame, showing: playerContainer, frozen: frozen)
    }
    func queueTransitionSnapshot() -> NSImageView? {
        guard mini.isVisible && !selfTest && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            return nil
        }
        return snapshotOverlay(
            queueOverlay ? (settingsOpen ? connectionPanel : overlayQueue) : playerContainer)
    }
    func animateQueueChange(to frame: NSRect, showing view: NSView, frozen: NSImageView?) {
        guard let frozen else {
            if !preservesSystemFrame && mini.frame != frame { mini.setFrame(frame, display: true) }
            view.alphaValue = 1
            finishWindowTransition()
            return
        }
        transitionGeneration += 1
        let generation = transitionGeneration
        windowTransition = true
        compactButton.isEnabled = false
        view.alphaValue = 0
        let resize = !preservesSystemFrame && mini.frame != frame
        var sizeDone = !resize
        var fadeDone = false
        let complete = { [weak self] in
            guard let self, generation == self.transitionGeneration, sizeDone, fadeDone else { return }
            self.finishWindowTransition()
        }
        if resize {
            frameAnimator.move(mini, to: frame) {
                sizeDone = true
                complete()
            }
        }
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.20
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                frozen.animator().alphaValue = 0
                view.animator().alphaValue = 1
            },
            completionHandler: {
                fadeDone = true
                complete()
            })
    }
    func resetPlayerFeedback() {
        func clear(_ view: NSView) {
            (view as? HoverButton)?.resetFeedback()
            view.subviews.forEach(clear)
        }
        clear(playerContainer)
        queueButton?.selected = dockedQueueVisible || (queueOverlay && !settingsOpen)
    }
    static func trackPageURL(_ raw: String) -> URL? { MusicService.trackPageURL(raw) }
    func openCurrentTrackPage() {
        web.evaluateJavaScript("window.__moyaQueue?.currentURL() || ''") { value, _ in
            guard let raw = value as? String, let url = Self.trackPageURL(raw) else { return }
            NSWorkspace.shared.open(url)
        }
    }
    func collapseDockedQueue() {
        if preservesSystemFrame {
            dockedQueueSuppressed = true
            layoutQueueRegion()
            return
        }
        var frame = mini.frame
        let height = basePlayerHeight + chromeGutter
        frame.origin.y += frame.height - height
        frame.size.height = height
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
        let frame = NSRect(
            x: (root.bounds.width - columnWidth) / 2 + 16, y: 12, width: max(1, columnWidth - 32),
            height: showDocked ? available : 120)
        if dockedQueue.frame != frame {
            dockedQueue.frame = frame
            dockedQueue.needsLayout = true
        }
        if dockedQueue.isHidden == showDocked { dockedQueue.isHidden = !showDocked }
        queueButton?.selected = showDocked || (queueOverlay && !settingsOpen)
        let wants = (queueOverlay && !settingsOpen) || showDocked
        if wants != queueWatching {
            queueWatching = wants
            web?.evaluateJavaScript(
                "window.__moyaQueue?.watch(\(wants ? "true" : "false")); null", completionHandler: nil)
            if wants { fetchQueue() }
        } else if changed && showDocked {
            fetchQueue()
        }
    }
    func fetchQueue() {
        guard !queueFetching, !settingsOpen, queueOverlay || dockedQueueVisible else { return }
        queueFetching = true
        web.callAsyncJavaScript(
            "return await window.__moyaQueue?.refresh()", arguments: [:], in: nil, in: .page
        ) { [weak self] result in
            guard let self else { return }
            self.queueFetching = false
            switch result {
            case .success(let value): if let data = value as? [String: Any] { self.applyQueue(data) }
            case .failure:
                self.overlayQueue.showError()
                self.dockedQueue.showError()
            }
        }
    }
    func applyQueue(_ value: [String: Any]) {
        lastQueue = value
        overlayQueue.apply(value)
        dockedQueue.apply(value)
    }
}
