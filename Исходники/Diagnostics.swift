import AppKit
import WebKit

private final class SourceSwitchProbe: NSObject {
    var selections: [Int] = []
    @objc func changed(_ sender: SourceSwitch) { selections.append(sender.selectedSegment) }
}

extension MusicApp {
    func runSelfTest() {
        mini.contentView?.layoutSubtreeIfNeeded()
        precondition(playerTop.constant == chromeInset, "Startup header inset is stale")
        let controls = controlsRow.convert(controlsRow.bounds, to:surface)
        precondition(controls.minY >= surface.bounds.minY && controls.maxY <= surface.bounds.maxY, "Startup controls are clipped")
        if let path = ProcessInfo.processInfo.environment["MOYA_PREVIEW_PATH"] {
            savePreview(URL(fileURLWithPath:path).deletingPathExtension().path + "-startup.png")
        }
        print("STARTUP_LAYOUT_OK: header inset and playback controls fit")
        web.loadHTMLString("""
        <html><body><section data-test-id="VIBE_PLAYERBAR">
        <button data-test-id="LIKE_BUTTON" aria-pressed="false" onclick="this.setAttribute('aria-pressed','true')">Like</button>
        <button data-test-id="DISLIKE_BUTTON" aria-pressed="false" onclick="this.setAttribute('aria-pressed','true')">Dislike</button>
        <button data-test-id="REPEAT_BUTTON_NO_REPEAT" onclick="this.setAttribute('data-test-id','REPEAT_BUTTON_REPEAT_ONE')">Repeat</button>
        </section><script>
        navigator.mediaSession.metadata = new MediaMetadata({title:'Проверка',artist:'Моя музыка'});
        navigator.mediaSession.setActionHandler('nexttrack', () => { document.body.dataset.next = 'ok'; });
        navigator.mediaSession.setPositionState({duration:147,position:23,playbackRate:1});
        navigator.mediaSession.playbackState = 'playing';
        </script></body></html>
        """, baseURL: Bundle.main.resourceURL)
    }
    func completeSelfTest() {
        let script = """
        await new Promise(resolve => setTimeout(resolve, 120));
        const clock = window.__moyaMusic.state();
        const audio = new Audio(); audio.play().catch(()=>{}); audio.currentTime = 31;
        await window.__moyaMusic.command('nexttrack');
        const seekRequests = [];
        // Reproduce the site's handler: exact zero is ignored, positive times work.
        navigator.mediaSession.setActionHandler('seekto', ({seekTime}) => {
            seekRequests.push(seekTime);
            if (seekTime) audio.currentTime = seekTime;
        });
        await window.__moyaMusic.command('seekto', 0);
        const handlerZero = audio.currentTime;
        await window.__moyaMusic.command('seekto', 59);
        const handlerMiddle = audio.currentTime;
        navigator.mediaSession.setActionHandler('seekto', null);
        await window.__moyaMusic.command('seekto', 0);
        const mediaZero = audio.currentTime;
        await window.__moyaMusic.command('seekto', 41);
        await window.__moyaMusic.command('like');
        await window.__moyaMusic.command('dislike');
        await window.__moyaMusic.command('repeat');
        return {state:window.__moyaMusic.state(),clock,next:document.body.dataset.next,handlerZero,handlerMiddle,mediaZero,seekRequests};
        """
        web.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
            guard case .success(let value) = result, let dict = value as? [String: Any], dict["next"] as? String == "ok",
                  let clock = dict["clock"] as? [String: Any], (clock["position"] as? Double ?? 0) > 23,
                  let state = dict["state"] as? [String: Any], state["title"] as? String == "Проверка",
                  state["position"] as? Double == 41, state["duration"] as? Double == 147,
                  dict["handlerZero"] as? Double == 0.001, dict["handlerMiddle"] as? Double == 59,
                  dict["mediaZero"] as? Double == 0, dict["seekRequests"] as? [Double] == [0.001,59],
                  state["liked"] as? Bool == true, state["disliked"] as? Bool == true,
                  state["repeat"] as? String == "one" else {
                print("SELF_TEST_FAILED: \(result)"); exit(1)
            }
            self.update(state)
            self.checkSourceSwitch()
            let original = self.compact
            if let path = ProcessInfo.processInfo.environment["MOYA_PREVIEW_ARTWORK"], let data = try? Data(contentsOf: URL(fileURLWithPath: path)), let image = NSImage(data: data) {
                self.setArtworkImage(image,animated:false); self.setAmbient(self.makeAmbient(data))
            }
            self.setCompact(true)
            self.mini.contentView?.layoutSubtreeIfNeeded()
            if let path = ProcessInfo.processInfo.environment["MOYA_PREVIEW_PATH"] {
                self.savePreview(URL(fileURLWithPath: path).deletingPathExtension().path + "-compact.png")
            }
            self.setCompact(false)
            self.mini.contentView?.layoutSubtreeIfNeeded()
            if let path = ProcessInfo.processInfo.environment["MOYA_PREVIEW_PATH"] { self.savePreview(path) }
            let beforeArtwork = self.mini.frame.size
            self.setArtworkImage(NSImage(size:NSSize(width:3000,height:3000)),animated:false)
            self.titleLabel.stringValue = String(repeating: "Очень длинное название трека ", count: 12)
            self.mini.contentView?.layoutSubtreeIfNeeded()
            guard self.mini.frame.size == beforeArtwork,
                  self.cover.intrinsicContentSize.width == NSView.noIntrinsicMetric,
                  self.mini.frame.width <= 500 else {
                print("SELF_TEST_FAILED: artwork enlarged window"); exit(1)
            }
            self.checkQueuePresentation()
            self.setCompact(original)
            if ProcessInfo.processInfo.arguments.contains("--window-test") { self.runNativeWindowTest(); return }
            print("SELF_TEST_OK: elapsed time, detached audio, zero/middle seeks through handler and media, like/dislike/repeat, compact layout and large artwork")
            NSApp.terminate(nil)
        }
    }
    func checkSourceSwitch() {
        let probe = SourceSwitchProbe()
        let oldTarget = sourceSwitch.target, oldAction = sourceSwitch.action
        sourceSwitch.target = probe; sourceSwitch.action = #selector(SourceSwitchProbe.changed(_:))
        defer {
            sourceSwitch.target = oldTarget; sourceSwitch.action = oldAction
            sourceSwitch.showSelection(0, animated:false)
        }
        for code: UInt16 in [124,123] {
            guard let event = NSEvent.keyEvent(with:.keyDown, location:.zero, modifierFlags:[], timestamp:0,
                windowNumber:mini.windowNumber, context:nil, characters:"", charactersIgnoringModifiers:"", isARepeat:false, keyCode:code) else { fatalError("No key event") }
            sourceSwitch.keyDown(with:event)
        }
        precondition(probe.selections == [1,0])
        sourceSwitch.showSelection(1, animated:false)
        precondition(sourceSwitch.selectedSegment == 1 && probe.selections == [1,0])
        if let path = ProcessInfo.processInfo.environment["MOYA_PREVIEW_PATH"] {
            mini.contentView?.layoutSubtreeIfNeeded()
            savePreview(URL(fileURLWithPath:path).deletingPathExtension().path + "-mine.png")
        }
        let bounds = sourceSwitch.bounds
        precondition(bounds.width >= 164 && bounds.height >= 32)
        print("SOURCE_SWITCH_OK: arrows select both sources; state updates send no playback command")
    }
    func checkQueuePresentation() {
        var sample: [String:Any] = ["source":"wave", "playing":true, "ready":true,
            "current":["title":"Сейчас играет", "artist":"Исполнитель"],
            "tracks":[
                ["id":"old", "title":"Предыдущая песня", "artist":"Исполнитель", "duration":185.0,"index":0,"bucket":"history","current":false],
                ["id":"now", "title":"Сейчас играет", "artist":"Исполнитель", "duration":210.0,"index":1,"bucket":"current","current":true],
                ["id":"next", "title":"Следующая песня", "artist":"Другой исполнитель", "duration":245.0,"index":2,"bucket":"upcoming","current":false]
            ]]
        // A three-digit count exercises the queue header at the minimum window width.
        let history: [[String:Any]] = (0..<100).map { index in
            ["id":"history-\(index)", "title":"Песня \(index+1)", "artist":"Исполнитель", "duration":185.0,
             "index":index+3, "bucket":"history", "current":false]
        }
        sample["tracks"] = history + (sample["tracks"] as? [[String:Any]] ?? [])
        setCompact(true)
        let before = mini.frame
        toggleQueue(); applyQueue(sample)
        mini.contentView?.layoutSubtreeIfNeeded()
        precondition(queueOverlay && mini.frame.height >= min(mini.frame.width, 660) + 228 + windowTopReserve)
        if let path = ProcessInfo.processInfo.environment["MOYA_PREVIEW_PATH"] { savePreview(URL(fileURLWithPath:path).deletingPathExtension().path + "-queue.png") }
        closeQueueOverlay()
        precondition(compact && abs(mini.frame.height - before.height) < 1)
        setCompact(false)
        var frame = mini.frame; frame.origin.y -= 280; frame.size.height += 280
        mini.setFrame(frame, display:true); layoutQueueRegion(); applyQueue(sample)
        mini.contentView?.layoutSubtreeIfNeeded()
        precondition(dockedQueueVisible)
        precondition(dockedQueue.frame.maxY <= playerContainer.frame.minY - 7)
        print("QUEUE_LAYOUT root=\(mini.contentView!.bounds) player=\(playerContainer.frame) dock=\(dockedQueue.frame)")
        if let path = ProcessInfo.processInfo.environment["MOYA_PREVIEW_PATH"] { savePreview(URL(fileURLWithPath:path).deletingPathExtension().path + "-docked.png") }
        collapseDockedQueue()
        mini.contentView?.layoutSubtreeIfNeeded()
        precondition(timeRow.frame.height >= 14 && timeLabel.frame.height >= 14 && durationLabel.frame.height >= 14)
        let priorFrame = mini.frame
        if let screen = mini.screen {
            var topFrame = priorFrame
            topFrame.origin.y = screen.visibleFrame.maxY - topFrame.height
            mini.setFrame(topFrame, display: true); positionChrome()
            mini.contentView?.layoutSubtreeIfNeeded()
            precondition(chromeInset == 30)
            precondition(playerContainer.frame.maxY <= mini.contentView!.bounds.maxY - 29)
            if let path = ProcessInfo.processInfo.environment["MOYA_PREVIEW_PATH"] { savePreview(URL(fileURLWithPath:path).deletingPathExtension().path + "-header.png") }
            mini.setFrame(priorFrame, display: true); positionChrome()
        }
    }
    func savePreview(_ path: String) {
        guard let root = mini.contentView, let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return }
        root.cacheDisplay(in: root.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        if let chrome = chromeView,
           let chromeBitmap = chrome.bitmapImageRepForCachingDisplay(in: chrome.bounds) {
            let wasHovered = (chrome.subviews.first as? ChromeButton)?.groupHovered ?? false
            chrome.updateGroupHover(true)
            chrome.cacheDisplay(in: chrome.bounds, to: chromeBitmap)
            let chromePath = URL(fileURLWithPath: path).deletingPathExtension().path + "-chrome.png"
            try? chromeBitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: chromePath))
            chrome.updateGroupHover(wasHovered)
        }
    }
    func waitForWindowTest(_ label: String, until ready: @escaping () -> Bool, then finish: @escaping () -> Void) {
        let deadline = Date().addingTimeInterval(15)
        func poll() {
            if ready() { finish(); return }
            if Date() > deadline { print("WINDOW_TEST_FAILED: \(label)"); fflush(stdout); exit(1) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: poll)
        }
        poll()
    }
    func runNativeWindowTest() {
        guard let screen = mini.screen else { print("WINDOW_TEST_FAILED: no screen"); exit(1) }
        let area = screen.visibleFrame
        setCompact(false)
        var frames = [
            NSRect(x: area.minX, y: area.minY, width: area.width/2, height: area.height),
            NSRect(x: area.midX, y: area.minY, width: area.width/2, height: area.height),
            area
        ]
        if area.height/2 >= 598 {
            frames += [NSRect(x: area.minX, y: area.midY, width: area.width/2, height: area.height/2),
                       NSRect(x: area.midX, y: area.minY, width: area.width/2, height: area.height/2)]
        }
        for target in frames {
            mini.setFrame(target, display: true)
            mini.contentView?.layoutSubtreeIfNeeded()
            let before = mini.frame
            windowDidMove(Notification(name: NSWindow.didMoveNotification, object: mini))
            windowDidResize(Notification(name: NSWindow.didResizeNotification, object: mini))
            windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification, object: mini))
            mini.contentView?.layoutSubtreeIfNeeded()
            precondition(mini.frame == before && mini.frame.width >= target.width - 1)
            precondition(chromeGutter == 0 && chromeInset >= 30)
            precondition(playerContainer.frame.width <= 660 && playerContainer.frame.width <= mini.contentView!.bounds.width)
        }
        let baseline = NSRect(x: area.midX - 170, y: area.midY - 299, width: 340, height: 598)
        mini.setFrame(baseline, display: true)
        positionChrome()
        precondition(chromeGutter == 30 && chromeInset == 0)
        precondition(chromeView.frame.minY >= surface.frame.maxY)
        precondition(chromeView.window === mini)
        precondition(surface.frame.minX == 0 && surface.frame.minY == 0 && surface.frame.width == mini.contentView!.bounds.width)
        precondition(cardShadowWindow?.parent === mini && cardShadowWindow?.isVisible == true)
        precondition(cardShadowWindow?.ignoresMouseEvents == true && cardShadowWindow?.canBecomeKey == false)
        precondition(cardShadowWindow?.collectionBehavior.contains(.transient) == true)
        print("SHADOW_BOUNDS_OK: player frame fits card; separate shadow ignores input and Mission Control")
        print("WINDOW_GEOMETRY_OK: halves, corners, screen bounds; no resize feedback")
        fflush(stdout)
        let checkFullscreen = { [self] in
            toggleNativeFullScreen()
            waitForWindowTest("enter fullscreen", until: { self.fullScreenPhase == .fullScreen && self.mini.styleMask.contains(.fullScreen) }) {
                print("WINDOW_ENTER_STATE frame=\(self.mini.frame) closeHidden=\(String(describing:self.mini.standardWindowButton(.closeButton)?.isHidden)) zoomHidden=\(String(describing:self.mini.standardWindowButton(.zoomButton)?.isHidden)) customHidden=\(self.chromeView.isHidden)")
                fflush(stdout)
                precondition(self.mini.standardWindowButton(.closeButton)?.isHidden == false)
                precondition(self.mini.standardWindowButton(.zoomButton)?.isHidden == false)
                precondition(self.chromeView.isHidden)
                precondition(self.cardShadowWindow?.isVisible != true && self.cardShadowWindow?.parent == nil)
                let fullscreenFrame = self.mini.frame
                self.setCompact(true); self.toggleQueue(); self.closeQueueOverlay(); self.setCompact(false)
                print("WINDOW_MODE_STATE before=\(fullscreenFrame) after=\(self.mini.frame) phase=\(self.fullScreenPhase)")
                fflush(stdout)
                precondition(self.mini.frame == fullscreenFrame)
                precondition(self.chromeView.window === self.mini)
                print("WINDOW_FULLSCREEN_OK: native buttons; compact and queue keep system frame")
                fflush(stdout)
                self.minimizePlayer()
                self.waitForWindowTest("exit and minimize", until: { self.fullScreenPhase == .windowed && self.mini.isMiniaturized }) {
                    precondition(!self.mini.styleMask.contains(.fullScreen))
                    precondition(self.cardShadowWindow?.isVisible != true)
                    self.mini.deminiaturize(nil)
                    print("WINDOW_MINIMIZE_OK: exited fullscreen before minimizing")
                    fflush(stdout)
                    self.toggleNativeFullScreen()
                    self.waitForWindowTest("reenter fullscreen", until: { self.fullScreenPhase == .fullScreen }) {
                        self.closePlayer()
                        self.waitForWindowTest("exit before close", until: { self.fullScreenPhase == .windowed && !self.mini.isVisible }) {
                            precondition(!self.mini.styleMask.contains(.fullScreen))
                            precondition(self.cardShadowWindow?.isVisible != true && self.cardShadowWindow?.parent == nil)
                            print("WINDOW_TEST_OK: reenter, exit before hiding; no fullscreen space left behind")
                            fflush(stdout); NSApp.terminate(nil)
                        }
                    }
                }
            }
        }
        var enlarged = baseline
        enlarged.size.height += 80; enlarged.origin.y -= 80
        animateQueueChange(to: enlarged, showing: playerContainer, frozen: snapshotOverlay())
        waitForWindowTest("size animation", until: { !self.windowTransition }) {
            precondition(abs(self.mini.frame.height - enlarged.height) < 1)
            print("WINDOW_ANIMATION_OK: animated resize completed")
            fflush(stdout)
            self.animateQueueChange(to: baseline, showing: self.playerContainer, frozen: self.snapshotOverlay())
            checkFullscreen()
        }
    }

    @objc func inspectPlayer(_ notification: Notification) {
        if let action = notification.userInfo?["ui"] as? String {
            if action == "queue" { toggleQueue() }
            if action == "compact" { toggleCompact() }
            if action == "back" { closeQueueOverlay() }
            if action == "tall" { var f=mini.frame; f.origin.y -= 300; f.size.height += 300; mini.setFrame(f, display:true) }
            if let output = notification.userInfo?["preview"] as? String { DispatchQueue.main.asyncAfter(deadline:.now()+1) { self.savePreview(output) } }
            return
        }
        if notification.userInfo?["queue"] as? Bool == true {
            inspectQueue(output: notification.userInfo?["output"] as? String)
            return
        }
        if let source = notification.userInfo?["source"] as? String, ["wave", "likes"].contains(source) {
            command(source)
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { self.reportLivePage() }
        } else { reportLivePage() }
    }
    func inspectQueue(output: String?) {
        guard let url = Bundle.main.url(forResource: "queue-inspect", withExtension: "js"), let script = try? String(contentsOf: url, encoding: .utf8) else { return }
        web.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
            switch result {
            case .success(let value):
                guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) else { return }
                if let output { try? data.write(to: URL(fileURLWithPath: output)) }
                print("QUEUE_INSPECTION: \(data.count) bytes")
            case .failure(let error): print("QUEUE_INSPECTION_FAILED: \(error.localizedDescription)")
            }
            fflush(stdout)
        }
    }
    func reportLivePage() {
        web.evaluateJavaScript("JSON.stringify({bridge:!!window.__moyaMusic,title:document.title,head:document.body.innerText.slice(0,1000),path:location.pathname,pending:sessionStorage.getItem('moyaPending'),player:window.__moyaMusic?.state(),buttons:[...document.querySelectorAll('button,[role=button]')].map(b=>({id:b.dataset.testId,label:b.getAttribute('aria-label'),title:b.title,pressed:b.getAttribute('aria-pressed'),disabled:b.disabled,cls:b.className,parent:b.parentElement?.className})).slice(-45),links:[...document.querySelectorAll('a[href]')].filter(a=>/shelf|liked|collection|playlist/.test(a.getAttribute('href'))).map(a=>({href:a.getAttribute('href'),text:a.textContent.slice(0,40)})).slice(0,15),sliders:[...document.querySelectorAll('[role=slider],input[type=range]')].map(b=>({role:b.getAttribute('role'),label:b.getAttribute('aria-label'),now:b.getAttribute('aria-valuenow'),max:b.getAttribute('aria-valuemax')}))})") { result, error in
            print("LIVE_PAGE: \(result ?? String(describing: error))")
            print("UI: compact=\(self.compact), size=\(self.mini.frame.size), ambient=\(self.ambientSpin.contents != nil)")
            fflush(stdout)
        }
    }
}
