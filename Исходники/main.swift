import AppKit
import CoreImage
import QuartzCore
import Sparkle
import WebKit

final class MusicApp: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate,
    WKScriptMessageHandler
{
    var updateStateObserver: NSKeyValueObservation?
    var updaterController: SPUStandardUpdaterController?
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
    var alwaysOnTop = UserDefaults.standard.bool(forKey: "alwaysOnTop")
    var connectionSettings = ConnectionSettings.load()
    var artworkSession = URLSession(configuration: .default)
    let connectionPanel = ConnectionPanel(frame: .zero)
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
    var shadowUpdateScheduled = false
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
    var lastQueue: [String: Any]?

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
    var selfTest =
        ProcessInfo.processInfo.arguments.contains("--self-test")
        || ProcessInfo.processInfo.arguments.contains("--window-test")
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
            DistributedNotificationCenter.default().addObserver(
                self, selector: #selector(inspectPlayer(_:)),
                name: Notification.Name("ru.ninesquares.moyamusic.inspect"), object: nil)
        }
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(headphonesConnected(_:)),
            name: Notification.Name("ru.ninesquares.moyamusic.headphones"), object: nil)
        mini.makeKeyAndOrderFront(nil)
        updateCardShadow()
        NSApp.activate(ignoringOtherApps: true)
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(
                self, selector: #selector(pauseOnWake), name: name, object: nil)
        }
        if selfTest {
            runSelfTest()
            return
        }
        setupUpdates()
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
                NSBezierPath(
                    roundedRect: NSRect(x: 118 + Double(i) * 56, y: (512 - h) / 2, width: 32, height: h),
                    xRadius: 16, yRadius: 16
                ).fill()
            }
            return true
        }
    }

    func setupMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Открыть библиотеку", action: #selector(showLibrary), keyEquivalent: "o")
            .target = self
        appMenu.addItem(withTitle: "Показать плеер", action: #selector(showMini), keyEquivalent: "1").target =
            self
        appMenu.addItem(
            withTitle: "Проверить обновления…", action: #selector(checkForUpdates(_:)), keyEquivalent: ""
        ).target = self
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Скрыть Мою музыку", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(
            withTitle: "Завершить Мою музыку", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Правка")
        editItem.submenu = edit
        for (name, selector, key) in [
            ("Отменить", "undo:", "z"), ("Вырезать", "cut:", "x"), ("Копировать", "copy:", "c"),
            ("Вставить", "paste:", "v"), ("Выбрать всё", "selectAll:", "a"),
        ] {
            edit.addItem(withTitle: name, action: Selector(selector), keyEquivalent: key)
        }
        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let windowMenu = NSMenu(title: "Окно")
        windowItem.submenu = windowMenu
        windowMenu.addItem(
            withTitle: "Закрыть окно", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(
            withTitle: "Настройки…", action: #selector(showConnectionSettings), keyEquivalent: ","
        ).target = self
        windowMenu.addItem(withTitle: "Обновить библиотеку", action: #selector(reload), keyEquivalent: "r")
            .target = self
        windowMenu.addItem(withTitle: "Свернуть плеер", action: #selector(minimizePlayer), keyEquivalent: "m")
            .target = self
        let fullscreen = windowMenu.addItem(
            withTitle: "На весь экран / выйти", action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f")
        fullscreen.keyEquivalentModifierMask = [.control, .command]
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = main
    }

    func installWebScripts(_ controller: WKUserContentController) {
        controller.removeAllUserScripts()
        let bridgeURL = Bundle.main.url(forResource: "bridge", withExtension: "js")!
        let bridge =
            "window.__moyaPlaybackAllowed = \(UserDefaults.standard.bool(forKey:"autoplay") && !selfTest ? "true":"false");\n"
            + (try! String(contentsOf: bridgeURL, encoding: .utf8))
        controller.addUserScript(
            WKUserScript(source: bridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        if let queueURL = Bundle.main.url(forResource: "queue-engine", withExtension: "js"),
            let queueScript = try? String(contentsOf: queueURL, encoding: .utf8)
        {
            let history = MusicService.sanitizeHistory(
                UserDefaults.standard.array(forKey: "queueHistory") as? [[String: Any]] ?? [])
            let historyData = (try? JSONSerialization.data(withJSONObject: history)) ?? Data("[]".utf8)
            let historyJSON = String(data: historyData, encoding: .utf8) ?? "[]"
            controller.addUserScript(
                WKUserScript(
                    source:
                        "if (/^music\\.yandex\\.(ru|com|by|kz|uz)$/.test(location.hostname)) { window.__moyaQueueHistory=\(historyJSON);\n"
                        + queueScript + "\n}", injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
    }
    func setupWeb() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        if !selfTest {
            connectionSettings.apply(
                to: configuration.websiteDataStore,
                password: connectionSettings.enabled && !connectionSettings.username.isEmpty
                    ? ConnectionSettings.password() : "")
        }
        configuration.mediaTypesRequiringUserActionForPlayback = []
        if #available(macOS 14.0, *) { configuration.preferences.inactiveSchedulingPolicy = .none }
        installWebScripts(configuration.userContentController)
        configuration.userContentController.add(self, name: "music")
        web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
        web.allowsBackForwardNavigationGestures = true
        library = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1060, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        library.title = "Моя музыка — библиотека Яндекса"
        library.contentMinSize = NSSize(width: 700, height: 500)
        library.contentView = web
        library.delegate = self
        library.isReleasedWhenClosed = false
        library.center()
    }

    func setupMini() {
        mini = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        mini.title = "Моя музыка"
        mini.titleVisibility = .hidden
        mini.titlebarAppearsTransparent = true
        mini.isMovableByWindowBackground = true
        mini.titlebarSeparatorStyle = .none
        mini.acceptsMouseMovedEvents = true
        mini.isOpaque = false
        mini.backgroundColor = .clear
        mini.hasShadow = false
        mini.minSize = NSSize(width: 340, height: 598)
        mini.minFullScreenContentSize = NSSize(width: 340, height: 598)
        mini.collectionBehavior = [.fullScreenPrimary, .fullScreenAllowsTiling]
        mini.tabbingMode = .disallowed
        mini.delegate = self
        mini.isReleasedWhenClosed = false
        if !selfTest { mini.setFrameAutosaveName("MiniPlayer") }
        let host = ChromeHostView(frame: mini.contentView!.bounds)
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        host.onTopHover = { [weak self] visible in self?.revealChrome(visible) }
        host.onLayout = { [weak self] in self?.positionChrome() }
        let root = PlayerSurface(
            frame: NSRect(x: 0, y: 0, width: host.bounds.width, height: max(1, host.bounds.height - 30)))
        surface = root
        root.autoresizingMask = [.width, .height]
        root.wantsLayer = true
        root.layer?.masksToBounds = true
        root.layer?.cornerCurve = .continuous
        root.layer?.cornerRadius = 14
        root.onTopHover = { [weak self] visible in self?.revealChrome(visible) }
        root.onLayout = { [weak self] in
            self?.layoutAmbient()
            self?.layoutPlayerColumn()
            self?.layoutQueueRegion()
            self?.updateCardShadow()
        }
        root.material = .hudWindow
        root.blendingMode = .behindWindow
        root.state = .active
        host.addSubview(root)
        mini.contentView = host
        ambientView.frame = root.bounds
        ambientView.autoresizingMask = [.width, .height]
        ambientView.wantsLayer = true
        ambientView.layer?.contentsGravity = .resizeAspectFill
        ambientView.layer?.masksToBounds = true
        ambientView.alphaValue = 0.95
        ambientSpin.contentsGravity = .resizeAspectFill
        ambientView.layer?.addSublayer(ambientSpin)
        root.addSubview(ambientView)
        let shade = NSView(frame: root.bounds)
        shade.autoresizingMask = [.width, .height]
        shade.wantsLayer = true
        shade.layer?.backgroundColor =
            NSColor(calibratedRed: 0.075, green: 0.075, blue: 0.105, alpha: 0.30).cgColor
        root.addSubview(shade)
        playerContainer = NSView()
        playerContainer.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(playerContainer)
        fullPlayerHeight = playerContainer.heightAnchor.constraint(
            equalTo: playerContainer.widthAnchor, constant: 228)
        compactPlayerHeight = playerContainer.heightAnchor.constraint(equalToConstant: 222)
        playerWidth = playerContainer.widthAnchor.constraint(equalToConstant: 340)
        playerTop = playerContainer.topAnchor.constraint(equalTo: root.topAnchor, constant: 0)
        NSLayoutConstraint.activate([
            playerContainer.centerXAnchor.constraint(equalTo: root.centerXAnchor), playerWidth!,
            playerTop!, fullPlayerHeight,
        ])
        sourceSwitch = SourceSwitch(frame: .zero)
        sourceSwitch.target = self
        sourceSwitch.action = #selector(sourceSwitchChanged(_:))
        sourceSwitch.translatesAutoresizingMaskIntoConstraints = false
        sourceSwitch.widthAnchor.constraint(equalToConstant: 164).isActive = true
        sourceSwitch.heightAnchor.constraint(equalToConstant: 32).isActive = true
        shuffleButton = iconButton("shuffle", "Случайный порядок", #selector(toggleShuffle), 16, 32)
        shuffleButton.isEnabled = false
        compactButton = iconButton("minimize-in", "Компактный вид", #selector(toggleCompact), 16, 32)
        let libraryButton = iconButton(
            "square.grid.2x2", "Открыть библиотеку", #selector(showLibrary), 16, 32)
        repeatButton = iconButton("repeat", "Повтор выключен", #selector(toggleRepeat), 16, 32)
        repeatButton.isEnabled = false
        pinButton = iconButton("pushpin", "Поверх окон", #selector(togglePin), 16, 32)
        pinButton.selected = alwaysOnTop
        pinButton.image = IconLibrary.image(alwaysOnTop ? "pushpin-filled" : "pushpin", size: 16)
        let symbol = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)!
        let shield = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            symbol.draw(in: rect)
            return true
        }
        shield.isTemplate = true
        settingsButton = IconButton(image: shield, target: self, action: #selector(showConnectionSettings))
        settingsButton.isBordered = false
        settingsButton.bezelStyle = .regularSquare
        settingsButton.focusRingType = .none
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.widthAnchor.constraint(equalToConstant: 32).isActive = true
        settingsButton.heightAnchor.constraint(equalToConstant: 32).isActive = true
        settingsButton.setAccessibilityLabel("Настройки")
        let proxyMenu = NSMenu()
        proxyMenu.addItem(
            withTitle: "Настройки…", action: #selector(showConnectionSettings), keyEquivalent: ""
        ).target = self
        settingsButton.menu = proxyMenu
        let top = NSStackView(views: [
            libraryButton, settingsButton!, sourceSwitch!, pinButton!, compactButton,
        ])
        top.orientation = .horizontal
        top.spacing = 4
        top.distribution = .equalSpacing
        top.alignment = .centerY
        for artwork in [cover, compactArtwork] {
            artwork.image = nil
            artwork.contentTintColor = accent
            artwork.imageScaling = .scaleProportionallyUpOrDown
            artwork.wantsLayer = true
            artwork.layer?.cornerRadius = 6
            artwork.layer?.cornerCurve = .continuous
            artwork.layer?.masksToBounds = true
            artwork.layer?.backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 1).cgColor
        }
        compactArtwork.isHidden = true
        compactArtwork.translatesAutoresizingMaskIntoConstraints = false
        compactArtwork.widthAnchor.constraint(equalToConstant: 64).isActive = true
        compactArtwork.heightAnchor.constraint(equalToConstant: 64).isActive = true
        artworkContainer = NSView()
        cover.translatesAutoresizingMaskIntoConstraints = false
        artworkContainer.addSubview(cover)
        NSLayoutConstraint.activate([
            cover.centerXAnchor.constraint(equalTo: artworkContainer.centerXAnchor),
            cover.centerYAnchor.constraint(equalTo: artworkContainer.centerYAnchor),
            cover.heightAnchor.constraint(equalTo: artworkContainer.heightAnchor),
            cover.widthAnchor.constraint(equalTo: cover.heightAnchor),
            cover.widthAnchor.constraint(equalTo: artworkContainer.widthAnchor),
        ])
        titleLabel.onOpen = { [weak self] in self?.openCurrentTrackPage() }
        titleLabel.toolTip = "Открыть страницу песни в Яндекс Музыке"
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        artistLabel.font = .systemFont(ofSize: 14)
        artistLabel.textColor = .secondaryLabelColor
        for label in [titleLabel, artistLabel] {
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        queueButton = IconButton(
            image: IconLibrary.image("playlist", size: 18), target: self, action: #selector(toggleQueue))
        queueButton.isBordered = false
        queueButton.toolTip = "Очередь треков"
        queueButton.setAccessibilityLabel("Открыть очередь треков")
        queueButton.translatesAutoresizingMaskIntoConstraints = false
        queueButton.widthAnchor.constraint(equalToConstant: 32).isActive = true
        queueButton.heightAnchor.constraint(equalToConstant: 32).isActive = true
        let artistRow = NSStackView(views: [
            artistLabel, NSView(), shuffleButton!, repeatButton!, queueButton!,
        ])
        artistRow.orientation = .horizontal
        artistRow.alignment = .centerY
        artistRow.spacing = 4
        let metadataLabels = NSStackView(views: [titleLabel, artistRow])
        metadataLabels.orientation = .vertical
        metadataLabels.alignment = .leading
        metadataLabels.spacing = 0
        for view in [titleLabel, artistRow] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: metadataLabels.widthAnchor).isActive = true
        }
        let metadataRow = NSStackView(views: [compactArtwork, metadataLabels])
        metadataRow.orientation = .horizontal
        metadataRow.alignment = .centerY
        metadataRow.spacing = 12
        metadataRow.detachesHiddenViews = true
        progress.cell = PlayerSliderCell()
        progress.minValue = 0
        progress.maxValue = 1
        progress.doubleValue = 0
        progress.target = self
        progress.action = #selector(seek)
        progress.isContinuous = false
        progress.controlSize = .small
        progress.isEnabled = false
        timeLabel.stringValue = "0:00"
        for label in [timeLabel, durationLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            label.textColor = .secondaryLabelColor
        }
        durationLabel.alignment = .right
        timeRow = NSStackView(views: [timeLabel, NSView(), durationLabel])
        timeRow.orientation = .horizontal
        timeRow.heightAnchor.constraint(equalToConstant: 14).isActive = true
        for label in [timeLabel, durationLabel] {
            label.heightAnchor.constraint(equalToConstant: 14).isActive = true
        }
        playButton = RoundPlayButton(frame: .zero)
        playButton.target = self
        playButton.action = #selector(togglePlay)
        playButton.isBordered = false
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.setAccessibilityLabel("Воспроизвести / пауза")
        playButton.widthAnchor.constraint(equalToConstant: 56).isActive = true
        playButton.heightAnchor.constraint(equalToConstant: 56).isActive = true
        previousButton = iconButton("backward.end.fill", "Предыдущий трек", #selector(previous), 20)
        nextButton = iconButton("forward.end.fill", "Следующий трек", #selector(next), 20)
        likeButton = iconButton("heart", "Нравится", #selector(like), 20)
        dislikeButton = iconButton("heart.slash", "Не нравится", #selector(dislike), 20)
        likeButton.isEnabled = false
        dislikeButton.isEnabled = false
        let controls = NSStackView(views: [dislikeButton, previousButton, playButton, nextButton, likeButton])
        controls.orientation = .horizontal
        controls.distribution = .equalSpacing
        controls.alignment = .centerY
        controlsRow = controls
        let stack = NSStackView(views: [top, artworkContainer, metadataRow, progress, timeRow, controls])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
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
        artworkHeight = artworkContainer.heightAnchor.constraint(
            equalTo: playerContainer.heightAnchor, constant: -260)
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
            artworkHeight!,
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

    func iconButton(
        _ symbol: String, _ help: String, _ action: Selector, _ size: CGFloat, _ edge: CGFloat = 32
    ) -> IconButton {
        let image = IconLibrary.image(symbol, size: size)
        let button = IconButton(image: image, target: self, action: action)
        button.isBordered = false
        button.toolTip = help
        button.setAccessibilityLabel(help)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: edge).isActive = true
        button.heightAnchor.constraint(equalToConstant: edge).isActive = true
        return button
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = IconLibrary.image("audio-waveform", size: 18)
        let menu = NSMenu()
        for (title, action) in [
            ("Показать плеер", #selector(showMini)), ("Воспроизвести / пауза", #selector(togglePlay)),
            ("Следующий трек", #selector(next)), ("Библиотека", #selector(showLibrary)),
        ] {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Завершить", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusItem.menu = menu
    }

    @objc func headphonesConnected(_ notification: Notification) {
        if !mini.isVisible { showMini() }
    }
    @objc func showLibrary() {
        library.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func showMini() {
        mini.makeKeyAndOrderFront(nil)
        layoutQueueRegion()
        updateCardShadow()
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func reload() { web.reload() }
    @objc func sourceSwitchChanged(_ sender: SourceSwitch) {
        let source = sender.selectedSegment == 0 ? "wave" : "likes"
        sender.showSelection(sender.selectedSegment)
        pendingSource = source
        pendingSourceAt = Date()
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
    func selectQueueTrack(_ track: QueueTrack) {
        guard
            let data = try? JSONSerialization.data(withJSONObject: [
                "id": track.id, "index": track.index,
                "url": MusicService.trackPageURL(track.url)?.absoluteString ?? "",
            ]), let json = String(data: data, encoding: .utf8)
        else { return }
        web.evaluateJavaScript(
            "(() => { const t=\(json); (window.__moyaMusic?.allowPlayback(),window.__moyaQueue?.select(t.id,t.index,t.url)).then(() => window.__moyaQueue?.refresh()).then(value=>{if(value)window.webkit.messageHandlers.music.postMessage({queueSnapshot:value})}); return true; })()",
            completionHandler: nil)
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

    func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        guard message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.protocol == "https",
            [0, 443].contains(message.frameInfo.securityOrigin.port),
            let host = message.frameInfo.securityOrigin.host as String?,
            MusicService.hosts.contains(host),
            let data = message.body as? [String: Any]
        else { return }
        if let history = data["queueHistory"] as? [[String: Any]] {
            if !selfTest {
                UserDefaults.standard.set(MusicService.sanitizeHistory(history), forKey: "queueHistory")
            }
            return
        }
        if let snapshot = data["queueSnapshot"] as? [String: Any] {
            applyQueue(snapshot)
            return
        }
        if data["queuePlayReady"] as? Bool == true {
            web.evaluateJavaScript(
                "window.__moyaQueue?.startPendingTrack(true); null", completionHandler: nil)
            return
        }
        if data["startSource"] as? Bool == true {
            web.evaluateJavaScript(
                "window.__moyaMusic?.startPendingSource(true); null", completionHandler: nil)
            return
        }
        if data["sourceFailed"] as? Bool == true {
            pendingSource = nil
            sourceSwitch.showSelection(confirmedSource == "wave" ? 0 : 1)
            artistLabel.stringValue = "Открой библиотеку и нажми «Слушать»"
            showLibrary()
            return
        }
        if data["commandResult"] as? String == "unavailable" {
            artistLabel.stringValue = "Открой библиотеку для этого действия"
            showLibrary()
            return
        }
        if data["commandResult"] != nil { return }
        update(data)
    }
    func update(_ data: [String: Any]) {
        let ready = data["ready"] as? Bool ?? false
        if titleLabel.linkEnabled != ready {
            titleLabel.linkEnabled = ready
            mini.invalidateCursorRects(for: titleLabel)
        }
        if ready {
            titleLabel.stringValue = data["title"] as? String ?? ""
            artistLabel.stringValue = data["artist"] as? String ?? ""
            if !selfTest && !UserDefaults.standard.bool(forKey: "hasPlayed") {
                UserDefaults.standard.set(true, forKey: "hasPlayed")
            }
        }
        if let source = data["source"] as? String, ["wave", "likes"].contains(source) {
            confirmedSource = source
            if pendingSource == source || Date().timeIntervalSince(pendingSourceAt) > 20 {
                pendingSource = nil
            }
            if pendingSource == nil {
                sourceSwitch.showSelection(source == "wave" ? 0 : 1, animated: !selfTest)
            }
        }
        playing = data["playing"] as? Bool ?? false
        playButton.playing = playing
        overlayQueue.updatePlayback(
            title: titleLabel.stringValue, artist: artistLabel.stringValue, playing: playing)
        dockedQueue.updatePlayback(
            title: titleLabel.stringValue, artist: artistLabel.stringValue, playing: playing)
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
        shuffleButton.toolTip =
            shuffleButton.isEnabled
            ? (shuffleButton.selected ? "Случайный порядок включён" : "Случайный порядок выключен")
            : "Волна сама подбирает порядок треков"
        repeatButton.isEnabled = data["canRepeat"] as? Bool ?? false
        let repeatMode = data["repeat"] as? String ?? "off"
        repeatButton.image = IconLibrary.image(repeatMode == "one" ? "repeat-one" : "repeat", size: 16)
        repeatButton.selected = repeatMode != "off"
        repeatButton.toolTip =
            repeatMode == "one"
            ? "Повтор одного трека" : repeatMode == "all" ? "Повтор всех треков" : "Повтор выключен"
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
            timeLabel.stringValue = "0:00"
            durationLabel.stringValue = "0:00"
        }
        progress.isEnabled = duration > 0
        let url = data["artwork"] as? String ?? ""
        if url != artworkURL { loadArtwork(url) }
        statusItem.button?.toolTip =
            ready ? "\(titleLabel.stringValue) — \(artistLabel.stringValue)" : "Моя музыка"
    }
    func formatTime(_ value: Double) -> String {
        let seconds = value.isFinite ? max(0, Int(value)) : 0
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
    func setArtworkImage(_ image: NSImage?, animated: Bool) {
        for artwork in [cover, compactArtwork] {
            if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                let fade = CATransition()
                fade.type = .fade
                fade.duration = 0.35
                artwork.layer?.add(fade, forKey: "artworkFade")
            }
            artwork.image = image
        }
    }
    func loadArtwork(_ string: String) {
        artworkTask?.cancel()
        artworkURL = string
        guard let url = URL(string: string), url.scheme == "https" else {
            setArtworkImage(nil, animated: false)
            setAmbient(nil)
            return
        }
        artworkTask = artworkSession.dataTask(with: url) { data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            let ambient = self.makeAmbient(data)
            DispatchQueue.main.async {
                if self.artworkURL == string {
                    self.setArtworkImage(image, animated: true)
                    self.setAmbient(ambient)
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
            .applyingFilter(
                "CIColorControls",
                parameters: [
                    kCIInputSaturationKey: 2.3, kCIInputBrightnessKey: -0.02, kCIInputContrastKey: 1.08,
                ])
        let exposed = blurred.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: -0.8])
        return ambientContext.createCGImage(exposed, from: small.extent)
    }
    func setAmbient(_ image: CGImage?) {
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 1.1
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ambientSpin.add(fade, forKey: "ambientFade")
        }
        ambientSpin.contents = image
        layoutAmbient()
        if image != nil && ambientSpin.animation(forKey: "ambientRotation") == nil
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        {
            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.fromValue = 0
            rotation.toValue = Double.pi * 2
            rotation.duration = 100
            rotation.repeatCount = .infinity
            rotation.timingFunction = CAMediaTimingFunction(name: .linear)
            rotation.isRemovedOnCompletion = false
            ambientSpin.add(rotation, forKey: "ambientRotation")
        }
    }
    func layoutAmbient() {
        let bounds = ambientView.bounds
        let side = hypot(bounds.width, bounds.height) * 1.12
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ambientSpin.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        ambientSpin.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMini()
        return true
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === web else { return }
        if selfTest {
            completeSelfTest()
            return
        }
        artistLabel.stringValue = "Открой библиотеку и выбери трек"
        webView.evaluateJavaScript(
            "window.__moyaMusic?.startPendingSource(true); window.__moyaQueue?.watch(\(queueWatching ? "true" : "false")); null",
            completionHandler: nil)
    }
    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error
    ) {
        guard webView === web else { return }
        if (error as NSError).code == NSURLErrorCancelled { return }
        artistLabel.stringValue = "Не удалось загрузить. ⌘R — повторить"
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard webView === web else { return }
        self.webView(webView, didFailProvisionalNavigation: navigation, withError: error)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === web else { return }
        artistLabel.stringValue = "Плеер остановился. ⌘R — перезапустить"
    }
    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.uiDelegate = self
        popup.navigationDelegate = self
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 720),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Вход в Яндекс"
        window.contentView = popup
        window.isReleasedWhenClosed = false
        popupWindows.append(window)
        window.center()
        window.makeKeyAndOrderFront(nil)
        return popup
    }
    func webViewDidClose(_ webView: WKWebView) {
        for window in popupWindows where window.contentView === webView { window.close() }
        popupWindows.removeAll { $0.contentView === webView }
    }
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        if MusicService.allowsNavigation(url, testing: selfTest) {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }

}

let app = NSApplication.shared
let delegate = MusicApp()
app.delegate = delegate
app.run()
