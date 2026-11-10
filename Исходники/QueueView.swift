import AppKit

struct QueueTrack: Equatable {
    var id: String
    var title: String
    var artist: String
    var duration: Double
    var url: String
    var index: Int
    var current: Bool
    var bucket: String
    init(_ value: [String: Any]) {
        id = value["id"] as? String ?? ""
        title = value["title"] as? String ?? ""
        artist = value["artist"] as? String ?? ""
        duration = value["duration"] as? Double ?? 0
        url = value["url"] as? String ?? ""
        index = value["index"] as? Int ?? -1
        current = value["current"] as? Bool ?? false
        bucket = value["bucket"] as? String ?? "upcoming"
    }
}

private enum QueueRow {
    case heading(String)
    case track(QueueTrack)
}

private final class QueueTrackCell: NSView {
    let title = NSTextField(labelWithString: "")
    let artist = NSTextField(labelWithString: "")
    let duration = NSTextField(labelWithString: "")
    var current = false
    var playing = false
    var hoverAmount: CGFloat = 0 { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for label in [title, artist, duration] {
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            addSubview(label)
        }
        title.font = .systemFont(ofSize: 13, weight: .medium)
        artist.font = .systemFont(ofSize: 11)
        artist.textColor = NSColor.white.withAlphaComponent(0.5)
        duration.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        duration.textColor = NSColor.white.withAlphaComponent(0.42)
        duration.alignment = .right
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    override func layout() {
        super.layout()
        let textWidth = max(1, bounds.width - 48 - 12 - 36 - 12)
        title.frame = NSRect(x: 48, y: bounds.midY - 19, width: textWidth, height: 19)
        artist.frame = NSRect(x: 48, y: bounds.midY + 2, width: textWidth, height: 17)
        duration.frame = NSRect(x: bounds.width - 48, y: bounds.midY - 8, width: 36, height: 17)
    }
    override func draw(_ dirtyRect: NSRect) {
        let hit = NSRect(x: 10, y: bounds.midY - 15, width: 30, height: 30)
        if hoverAmount > 0.001 {
            NSColor.white.withAlphaComponent(0.08 * hoverAmount).setFill()
            NSBezierPath(roundedRect: hit, xRadius: 6, yRadius: 6).fill()
        }
        let color: NSColor = current ? .yellow : .white.withAlphaComponent(0.4 + 0.6 * hoverAmount)
        IconLibrary.draw(
            IconLibrary.image(current && playing ? "pause" : "play", size: 18),
            in: NSRect(x: hit.midX - 9, y: hit.midY - 9, width: 18, height: 18), color: color)
    }
}

private final class QueueTableRow: NSTableRowView {
    var current = false
    var isTrack = false
    private var inside = false
    private var hoverAmount: CGFloat = 0
    private var ticker: Timer?
    func setHovered(_ value: Bool) {
        let value = isTrack && value
        (view(atColumn: 0) as? QueueTrackCell)?.hoverAmount = hoverAmount
        guard inside != value else { return }
        inside = value
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self, self.window != nil else {
                timer.invalidate()
                return
            }
            let target: CGFloat = self.inside ? 1 : 0
            self.hoverAmount +=
                (target - self.hoverAmount)
                * (NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0.35)
            (self.view(atColumn: 0) as? QueueTrackCell)?.hoverAmount = self.hoverAmount
            self.needsDisplay = true
            if abs(target - self.hoverAmount) < 0.005 {
                self.hoverAmount = target
                timer.invalidate()
                self.ticker = nil
            }
        }
        ticker = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            ticker?.invalidate()
            ticker = nil
            inside = false
            hoverAmount = 0
        }
    }
    override func drawBackground(in dirtyRect: NSRect) {
        guard isTrack && (current || hoverAmount > 0.001) else { return }
        (current
            ? NSColor.yellow.withAlphaComponent(0.10 + 0.025 * hoverAmount)
            : NSColor.white.withAlphaComponent(0.055 * hoverAmount)).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 2), xRadius: 7, yRadius: 7).fill()
    }
}

private final class QueueTable: NSTableView {
    private var tracking: NSTrackingArea?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: nil)
        if let clip = enclosingScrollView?.contentView, window != nil {
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(scrolled(_:)), name: NSView.boundsDidChangeNotification,
                object: clip)
        }
        refreshHover()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self)
        addTrackingArea(area)
        tracking = area
        refreshHover()
    }
    override func layout() {
        super.layout()
        refreshHover()
    }
    override func mouseMoved(with event: NSEvent) { refreshHover() }
    override func mouseEntered(with event: NSEvent) { refreshHover() }
    override func mouseExited(with event: NSEvent) { updateHover(row: -1) }
    @objc private func scrolled(_ notification: Notification) { refreshHover() }
    private func refreshHover() {
        guard let window, !isHiddenOrHasHiddenAncestor else {
            updateHover(row: -1)
            return
        }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        updateHover(row: visibleRect.contains(point) ? row(at: point) : -1)
    }
    private func updateHover(row hovered: Int) {
        enumerateAvailableRowViews { view, row in
            (view as? QueueTableRow)?.setHovered(row == hovered)
        }
    }
}

private final class QueueScroller: NSScroller {
    private var hovered = false
    private var tracking: NSTrackingArea?
    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style)
        -> CGFloat
    { 7 }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseEntered(with event: NSEvent) {
        hovered = true
        needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) { drawKnob() }
    override func drawKnob() {
        let knob = rect(for: .knob)
        let start = max(bounds.minY + 4, knob.minY + 4)
        let end = min(bounds.maxY - 4, knob.maxY - 4)
        guard end > start else { return }
        NSColor.white.withAlphaComponent(hovered ? 0.22 : 0.12).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 2
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: bounds.midX, y: start))
        path.line(to: NSPoint(x: bounds.midX, y: end))
        path.stroke()
    }
}

final class QueuePanel: NSView, NSTableViewDataSource, NSTableViewDelegate {
    var onBack: (() -> Void)?
    var onSelect: ((QueueTrack) -> Void)?
    var onTogglePlayback: (() -> Void)?
    private let heading = NSTextField(labelWithString: "Волна")
    private let queueLabel = NSTextField(labelWithString: "Очередь")
    private let countLabel = NSTextField(labelWithString: "")
    private let back = NSButton(title: "Плеер", target: nil, action: nil)
    private let table = QueueTable()
    private let scroll = NSScrollView()
    private let status = NSTextField(wrappingLabelWithString: "Загружаю очередь…")
    private let currentTitle = NSTextField(labelWithString: "Выберите музыку")
    private let currentArtist = NSTextField(labelWithString: "")
    private let playback = RoundPlayButton(frame: .zero)
    private var rows: [QueueRow] = []
    private var tracks: [QueueTrack] = []
    private var source = ""
    private var playing = false
    private var scrolledToCurrent = false
    private var footerView: NSView!
    private var scrollToFooter: NSLayoutConstraint!
    private var scrollToBottom: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        back.target = self
        back.action = #selector(goBack)
        back.isBordered = false
        back.font = .systemFont(ofSize: 12, weight: .medium)
        back.contentTintColor = .secondaryLabelColor
        back.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium))
        back.imagePosition = .imageLeading
        back.imageHugsTitle = true
        back.alignment = .left
        back.focusRingType = .none
        back.setAccessibilityLabel("Вернуться к плееру")
        heading.font = .systemFont(ofSize: 12, weight: .semibold)
        queueLabel.font = .systemFont(ofSize: 12, weight: .medium)
        countLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        for field in [queueLabel, countLabel] { field.textColor = NSColor.white.withAlphaComponent(0.65) }
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        for view in [back, heading, queueLabel, countLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(view)
        }
        NSLayoutConstraint.activate([
            back.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            back.heightAnchor.constraint(equalToConstant: 32),
            back.centerYAnchor.constraint(equalTo: heading.centerYAnchor),
            heading.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            heading.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            heading.leadingAnchor.constraint(greaterThanOrEqualTo: back.trailingAnchor, constant: 8),
            queueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: heading.trailingAnchor, constant: 8),
            queueLabel.firstBaselineAnchor.constraint(equalTo: heading.firstBaselineAnchor),
            countLabel.leadingAnchor.constraint(equalTo: queueLabel.trailingAnchor, constant: 6),
            countLabel.firstBaselineAnchor.constraint(equalTo: heading.firstBaselineAnchor),
            countLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor),
        ])
        addSubview(header)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("track"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.backgroundColor = .clear
        table.rowHeight = 60
        table.intercellSpacing = NSSize(width: 0, height: 4)
        table.selectionHighlightStyle = .none
        table.allowsEmptySelection = true
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(selectRow)
        table.setAccessibilityLabel("Очередь треков")
        let scroller = QueueScroller()
        scroller.controlSize = .small
        scroller.scrollerStyle = .overlay
        scroll.verticalScroller = scroller
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.scrollerStyle = .overlay
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        status.alignment = .center
        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 12)
        status.translatesAutoresizingMaskIntoConstraints = false
        addSubview(status)
        for field in [currentTitle, currentArtist] {
            field.lineBreakMode = .byTruncatingTail
            field.maximumNumberOfLines = 1
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        currentTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        currentArtist.font = .systemFont(ofSize: 11)
        currentArtist.textColor = .secondaryLabelColor
        let labels = NSStackView(views: [currentTitle, currentArtist])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        playback.target = self
        playback.action = #selector(togglePlayback)
        playback.isBordered = false
        playback.translatesAutoresizingMaskIntoConstraints = false
        playback.widthAnchor.constraint(equalToConstant: 38).isActive = true
        playback.heightAnchor.constraint(equalToConstant: 38).isActive = true
        let footer = NSView()
        labels.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(labels)
        footer.addSubview(playback)
        for field in [currentTitle, currentArtist] {
            field.widthAnchor.constraint(equalTo: labels.widthAnchor).isActive = true
        }
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.wantsLayer = true
        footer.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.025).cgColor
        footer.layer?.cornerRadius = 10
        addSubview(footer)
        footerView = footer
        scrollToFooter = scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8)
        scrollToBottom = scroll.bottomAnchor.constraint(equalTo: bottomAnchor)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 32),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollToFooter!,
            footer.leadingAnchor.constraint(equalTo: leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 64),
            labels.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 14),
            labels.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            labels.trailingAnchor.constraint(equalTo: playback.leadingAnchor, constant: -12),
            playback.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -12),
            playback.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            status.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            status.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            status.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    override func layout() {
        super.layout()
        var frame = table.frame
        frame.size.width = scroll.contentView.bounds.width
        table.frame = frame
        table.sizeLastColumnToFit()
    }
    func prepare(docked: Bool) {
        footerView.isHidden = docked
        scrollToFooter.isActive = !docked
        scrollToBottom.isActive = docked
        back.title = "Плеер"
        back.toolTip = docked ? "Убрать список под плеером" : "Вернуться к плееру"
        scrolledToCurrent = false
    }
    func showLoading() {
        if tracks.isEmpty {
            status.stringValue = "Загружаю очередь…"
            status.isHidden = false
        }
    }
    func showError() {
        if tracks.isEmpty {
            status.stringValue = "Не удалось загрузить очередь. Попробуйте ещё раз."
            status.isHidden = false
        }
    }
    func apply(_ value: [String: Any]) {
        let updated = (value["tracks"] as? [[String: Any]] ?? []).map(QueueTrack.init)
        let updatedSource = value["source"] as? String ?? "wave"
        let updatedPlaying = value["playing"] as? Bool ?? false
        let changed = updated != tracks || updatedSource != source || updatedPlaying != playing
        tracks = updated
        source = updatedSource
        playing = updatedPlaying
        heading.stringValue = source == "wave" ? "Волна" : "Моё"
        countLabel.stringValue = tracks.isEmpty ? "" : String(tracks.count)
        rows.removeAll()
        if source == "wave" {
            let history = tracks.filter { $0.bucket == "history" && !$0.current }
            let now = tracks.filter { $0.current }
            let next = tracks.filter { $0.bucket != "history" && !$0.current }
            if !history.isEmpty {
                rows.append(.heading("История"))
                rows += history.map(QueueRow.track)
            }
            if !now.isEmpty {
                rows.append(.heading("Сейчас играет"))
                rows += now.map(QueueRow.track)
            }
            if !next.isEmpty {
                rows.append(.heading(next.count == 1 ? "Следующий трек" : "Далее в очереди"))
                rows += next.map(QueueRow.track)
            }
        } else {
            rows = tracks.map(QueueRow.track)
        }
        if changed { table.reloadData() }
        status.isHidden = !tracks.isEmpty
        status.stringValue = value["notice"] as? String ?? "Очередь пуста"
        if let now = value["current"] as? [String: Any] {
            updatePlayback(
                title: now["title"] as? String ?? "", artist: now["artist"] as? String ?? "", playing: playing
            )
        }
        if !scrolledToCurrent, !rows.isEmpty {
            if let index = rows.firstIndex(where: {
                if case .track(let t) = $0 { return t.current }
                return false
            }) {
                table.scrollRowToVisible(index)
            }
            scrolledToCurrent = true
        }
    }
    func updatePlayback(title: String, artist: String, playing: Bool) {
        let playbackChanged = self.playing != playing
        self.playing = playing
        if playbackChanged { table.reloadData() }
        if !title.isEmpty {
            currentTitle.stringValue = title
            currentArtist.stringValue = artist
        }
        playback.playing = playing
        playback.setAccessibilityLabel(playing ? "Пауза" : "Воспроизвести")
    }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .heading = rows[row] { return 36 }
        return 60
    }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .track = rows[row] { return true }
        return false
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = QueueTableRow()
        if case .track(let track) = rows[row] {
            view.current = track.current
            view.isTrack = true
        }
        return view
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .heading(let text):
            let cell = NSView()
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 11, weight: .semibold)
            label.textColor = NSColor.white.withAlphaComponent(0.42)
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
                label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -12),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        case .track(let track):
            let cell = QueueTrackCell()
            cell.current = track.current
            cell.playing = playing
            cell.title.stringValue = track.title
            cell.title.textColor = track.current ? .yellow : .labelColor
            cell.artist.stringValue = track.artist
            cell.duration.stringValue =
                track.duration > 0
                ? String(format: "%d:%02d", Int(track.duration) / 60, Int(track.duration) % 60) : ""
            cell.setAccessibilityLabel(
                "\(track.title), \(track.artist)\(track.current ? ", сейчас играет" : "")")
            return cell
        }
    }
    @objc private func selectRow() {
        let row = table.clickedRow
        guard row >= 0, row < rows.count, case .track(let track) = rows[row] else { return }
        onSelect?(track)
    }
    @objc private func goBack() { onBack?() }
    @objc private func togglePlayback() { onTogglePlayback?() }
}
