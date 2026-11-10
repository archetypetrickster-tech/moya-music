import AppKit
import WebKit
import Network
import Security

private final class ArtworkProxyAuth: NSObject, URLSessionDelegate {
    let username: String, password: String
    init(username: String,password: String) { self.username = username; self.password = password }
    func urlSession(_ session: URLSession,didReceive challenge: URLAuthenticationChallenge,completionHandler: @escaping (URLSession.AuthChallengeDisposition,URLCredential?) -> Void) {
        if challenge.protectionSpace.isProxy() && !username.isEmpty && challenge.previousFailureCount == 0 {
            completionHandler(.useCredential,URLCredential(user:username,password:password,persistence:.forSession))
        } else { completionHandler(.performDefaultHandling,nil) }
    }
}

struct ConnectionSettings {
    var enabled: Bool = false
    var socks: Bool = false
    var host: String = "127.0.0.1"
    var port: String = ""
    var username: String = ""
    var configured: Bool { !host.isEmpty && UInt16(port).map { $0 > 0 } == true }
    static func load() -> Self {
        let d = UserDefaults.standard
        return Self(enabled:d.bool(forKey:"proxy.enabled"),socks:d.bool(forKey:"proxy.socks"),
            host:d.string(forKey:"proxy.host") ?? "127.0.0.1",port:d.string(forKey:"proxy.port") ?? "",username:d.string(forKey:"proxy.username") ?? "")
    }
    func save() {
        let d = UserDefaults.standard
        d.set(enabled,forKey:"proxy.enabled"); d.set(socks,forKey:"proxy.socks")
        d.set(host,forKey:"proxy.host"); d.set(port,forKey:"proxy.port"); d.set(username,forKey:"proxy.username")
    }
    static var credentialQuery: [String:Any] { [kSecClass as String:kSecClassGenericPassword,
        kSecAttrService as String:"ru.ninesquares.moyamusic.proxy",kSecAttrAccount as String:"proxy"] }
    static func password() -> String {
        var query = credentialQuery; query[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary,&result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(data:data,encoding:.utf8) ?? ""
    }
    static func savePassword(_ password: String) -> Bool {
        if password.isEmpty { let status = SecItemDelete(credentialQuery as CFDictionary); return status == errSecSuccess || status == errSecItemNotFound }
        let values = [kSecValueData as String:Data(password.utf8)]
        let status = SecItemUpdate(credentialQuery as CFDictionary,values as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        return SecItemAdd(credentialQuery.merging(values){_,new in new} as CFDictionary,nil) == errSecSuccess
    }
    func apply(to store: WKWebsiteDataStore, password: String) {
        if #available(macOS 14.0, *) {
            guard enabled, configured, let number = UInt16(port), let endpointPort = NWEndpoint.Port(rawValue:number) else { store.proxyConfigurations = []; return }
            let endpoint = NWEndpoint.hostPort(host:NWEndpoint.Host(host),port:endpointPort)
            let config = socks ? ProxyConfiguration(socksv5Proxy:endpoint) : ProxyConfiguration(httpCONNECTProxy:endpoint)
            if !username.isEmpty { config.applyCredential(username:username,password:password) }
            store.proxyConfigurations = [config]
        }
    }
    func artworkSession(password: String) -> URLSession {
        let config = URLSessionConfiguration.default
        if enabled && configured {
            var proxy: [AnyHashable:Any] = socks
                ? ["SOCKSEnable":1,"SOCKSProxy":host,"SOCKSPort":Int(port) ?? 0]
                : ["HTTPEnable":1,"HTTPProxy":host,"HTTPPort":Int(port) ?? 0,"HTTPSEnable":1,"HTTPSProxy":host,"HTTPSPort":Int(port) ?? 0]
            if socks && !username.isEmpty { proxy["SOCKSUser"] = username; proxy["SOCKSPassword"] = password }
            config.connectionProxyDictionary = proxy
        }
        return URLSession(configuration:config,delegate:ArtworkProxyAuth(username:enabled ? username:"",password:password),delegateQueue:nil)
    }
}

private final class ProxyChoice: HoverButton {
    var caption = ""
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(hoverAmount * 0.045).setFill(); bounds.fill()
        let text = caption as NSString
        let attrs: [NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:12),.foregroundColor:NSColor.labelColor]
        text.draw(at:NSPoint(x:12,y:bounds.midY-text.size(withAttributes:attrs).height/2),withAttributes:attrs)
        if selected,let icon = NSImage(systemSymbolName:"checkmark.circle.fill",accessibilityDescription:nil) {
            icon.size = NSSize(width:16,height:16)
            IconLibrary.draw(icon,in:NSRect(x:bounds.maxX-28,y:bounds.midY-8,width:16,height:16),color:.yellow)
        }
    }
}

final class ConnectionPanel: NSView {
    var onBack: (() -> Void)?
    var onSave: ((ConnectionSettings,String) -> String?)?
    private let startup = NSButton(checkboxWithTitle:"Запускать виджет при входе",target:nil,action:nil)
    private let autoplay = NSButton(checkboxWithTitle:"Начинать музыку автоматически",target:nil,action:nil)
    private let enabled = NSButton(checkboxWithTitle:"Использовать прокси",target:nil,action:nil)
    private let http = ProxyChoice(), socks = ProxyChoice()
    private let back = NSButton(title:"‹ Плеер",target:nil,action:nil)
    private let heading = NSTextField(labelWithString:"Настройки")
    private let proxyLink = NSButton(title:"Прокси…",target:nil,action:nil)
    private var basic: NSStackView!, proxyForm: NSStackView!
    private var proxyPage = false
    private let host = NSTextField(), port = NSTextField(), username = NSTextField()
    private let password = NSSecureTextField()
    private let status = NSTextField(wrappingLabelWithString:"")
    private func section(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString:text)
        label.font = .systemFont(ofSize:10,weight:.medium); label.textColor = .secondaryLabelColor
        return label
    }
    private func group(_ rows: [NSView]) -> NSView {
        let box = NSView(); box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.055).cgColor
        box.layer?.cornerRadius = 10; box.layer?.masksToBounds = true
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .centerX; stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false; box.addSubview(stack)
        for (index,row) in rows.enumerated() {
            if index > 0 {
                let line = NSView(); line.wantsLayer = true; line.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.09).cgColor
                stack.addArrangedSubview(line); line.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([line.heightAnchor.constraint(equalToConstant:0.5),line.widthAnchor.constraint(equalTo:stack.widthAnchor,constant:-24)])
                line.centerXAnchor.constraint(equalTo:stack.centerXAnchor).isActive = true
            }
            let holder = NSView(); stack.addArrangedSubview(holder)
            holder.translatesAutoresizingMaskIntoConstraints = false; row.translatesAutoresizingMaskIntoConstraints = false
            holder.addSubview(row)
            NSLayoutConstraint.activate([holder.widthAnchor.constraint(equalTo:stack.widthAnchor),holder.heightAnchor.constraint(equalToConstant:32),row.centerYAnchor.constraint(equalTo:holder.centerYAnchor),row.leadingAnchor.constraint(equalTo:holder.leadingAnchor,constant:row is ProxyChoice ? 0:12),row.trailingAnchor.constraint(equalTo:holder.trailingAnchor,constant:row is ProxyChoice ? 0:-12)])
            if row is ProxyChoice { row.heightAnchor.constraint(equalTo:holder.heightAnchor).isActive = true }
        }
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo:box.topAnchor),stack.bottomAnchor.constraint(equalTo:box.bottomAnchor),stack.leadingAnchor.constraint(equalTo:box.leadingAnchor),stack.trailingAnchor.constraint(equalTo:box.trailingAnchor)])
        return box
    }
    override init(frame frameRect: NSRect) {
        super.init(frame:frameRect); translatesAutoresizingMaskIntoConstraints = false
        back.target = self; back.action = #selector(goBack); back.isBordered = false
        let title = heading; title.font = .systemFont(ofSize:15,weight:.semibold)
        let header = NSStackView(views:[back,NSView(),title]); header.orientation = .horizontal
        http.caption = "HTTP CONNECT"; socks.caption = "SOCKS5"
        for (index,choice) in [http,socks].enumerated() {
            choice.tag = index; choice.target = self; choice.action = #selector(chooseType(_:)); choice.isBordered = false
            choice.setButtonType(.radio); choice.setAccessibilityLabel(choice.caption)
        }
        for (label,field) in [("Сервер",host),("Порт",port),("Логин",username),("Пароль",password)] {
            field.placeholderString = label; field.setAccessibilityLabel(label)
            field.isBezeled = false; field.drawsBackground = false; field.focusRingType = .none
            field.font = .systemFont(ofSize:13)
        }
        proxyLink.target = self; proxyLink.action = #selector(openProxy); proxyLink.isBordered = false; proxyLink.alignment = .left
        let quiet = NSTextField(wrappingLabelWithString:"Виджет и музыка запускаются независимо. Выключите автовоспроизведение, чтобы открывать виджет без звука.")
        quiet.font = .systemFont(ofSize:12); quiet.textColor = .secondaryLabelColor
        basic = NSStackView(views:[startup,autoplay,proxyLink,quiet])
        basic.orientation = .vertical; basic.alignment = .leading; basic.spacing = 18
        let help = NSTextField(wrappingLabelWithString:"Адрес и порт предоставляет ваш прокси-сервер или VPN-клиент. Прокси не отключает VPN; при проблемах может понадобиться исключение для музыки в самом VPN.")
        help.font = .systemFont(ofSize:11); help.textColor = .secondaryLabelColor
        let note = NSTextField(wrappingLabelWithString:"Изменение подключения перезагрузит библиотеку. Пароль хранится в Связке ключей macOS.")
        note.font = .systemFont(ofSize:11); note.textColor = .secondaryLabelColor
        proxyForm = NSStackView(views:[enabled,section("ТИП ПРОКСИ"),group([http,socks]),section("СОЕДИНЕНИЕ"),group([host,port]),section("АУТЕНТИФИКАЦИЯ · НЕОБЯЗАТЕЛЬНО"),group([username,password]),help,note])
        proxyForm.orientation = .vertical; proxyForm.alignment = .leading; proxyForm.spacing = 10; proxyForm.isHidden = true
        for container in [basic!,proxyForm!] { for view in container.arrangedSubviews { view.translatesAutoresizingMaskIntoConstraints = false; view.widthAnchor.constraint(equalTo:container.widthAnchor).isActive = true } }
        let save = NSButton(title:"Сохранить",target:self,action:#selector(saveSettings)); save.bezelStyle = .rounded
        status.font = .systemFont(ofSize:11)
        let stack = NSStackView(views:[header,basic!,proxyForm!,save,status])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16; stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        for view in [header,basic!,proxyForm!,status] { view.translatesAutoresizingMaskIntoConstraints = false; view.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true }
        let fit = stack.bottomAnchor.constraint(lessThanOrEqualTo:bottomAnchor); fit.priority = .defaultLow
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo:topAnchor),stack.leadingAnchor.constraint(equalTo:leadingAnchor),stack.trailingAnchor.constraint(equalTo:trailingAnchor),fit])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    func load(_ value: ConnectionSettings, password secret: String) {
        startup.state = FileManager.default.fileExists(atPath: Self.loginURL.path) ? .on:.off
        autoplay.state = UserDefaults.standard.bool(forKey:"autoplay") ? .on:.off
        enabled.state = value.enabled ? .on : .off; selectType(socks:value.socks)
        host.stringValue = value.host; port.stringValue = value.port
        username.stringValue = value.username; password.stringValue = secret; status.stringValue = ""
        proxyLink.title = value.enabled ? "Прокси: включён ›":"Прокси: системное подключение ›"
        showProxy(false)
        if #unavailable(macOS 14.0) { enabled.isEnabled = false; status.stringValue = "Настройка прокси доступна начиная с macOS 14." }
    }
    private static var loginURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/ru.ninesquares.moyamusic.login.plist") }
    private static func setLogin(_ enabled: Bool) throws {
        let fm = FileManager.default, url = loginURL
        guard fm.fileExists(atPath:url.path) != enabled else { return }
        if !enabled {
            let process = Process(); process.executableURL = URL(fileURLWithPath:"/bin/launchctl")
            process.arguments = ["bootout","gui/\(getuid())",url.path]; process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit(); try fm.removeItem(at:url); return
        }
        try fm.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        let plist: [String:Any] = ["Label":"ru.ninesquares.moyamusic.login","ProgramArguments":["/usr/bin/open","-a",Bundle.main.bundleURL.path],"RunAtLoad":true]
        try PropertyListSerialization.data(fromPropertyList:plist,format:.xml,options:0).write(to:url,options:.atomic)
        let process = Process(); process.executableURL = URL(fileURLWithPath:"/bin/launchctl")
        process.arguments = ["bootstrap","gui/\(getuid())",url.path]; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        if process.terminationStatus != 0 { try? fm.removeItem(at:url); throw NSError(domain:"MoyaMusic",code:Int(process.terminationStatus),userInfo:[NSLocalizedDescriptionKey:"macOS не разрешила включить автозапуск"]) }
    }
    func showProxy(_ show: Bool) {
        proxyPage = show; basic.isHidden = show; proxyForm.isHidden = !show
        heading.stringValue = show ? "Прокси":"Настройки"
        back.title = show ? "‹ Настройки":"‹ Плеер"
    }
    private func selectType(socks selected: Bool) {
        socks.selected = selected; http.selected = !selected
        socks.state = selected ? .on:.off; http.state = selected ? .off:.on
    }
    @objc private func chooseType(_ sender: NSButton) { selectType(socks:sender.tag == 1) }
    @objc private func openProxy() { showProxy(true) }
    @objc private func goBack() { if proxyPage { showProxy(false) } else { onBack?() } }
    @objc private func saveSettings() {
        let value = ConnectionSettings(enabled:enabled.state == .on,socks:socks.selected,
            host:host.stringValue.trimmingCharacters(in:.whitespacesAndNewlines),port:port.stringValue.trimmingCharacters(in:.whitespacesAndNewlines),username:username.stringValue)
        guard !value.enabled || (value.configured && !value.host.contains("://") && !value.host.contains("/") && !value.host.contains(" ")) else { status.stringValue = "Укажите адрес без http:// и порт от 1 до 65535."; return }
        do { try Self.setLogin(startup.state == .on) } catch { status.stringValue = "Не удалось изменить автозапуск: \(error.localizedDescription)"; return }
        UserDefaults.standard.set(autoplay.state == .on,forKey:"autoplay")
        status.stringValue = onSave?(value,password.stringValue) ?? "Сохранено. Библиотека перезагружена."
    }
}

extension MusicApp {
    @objc func togglePin() {
        alwaysOnTop.toggle(); if !selfTest { UserDefaults.standard.set(alwaysOnTop,forKey:"alwaysOnTop") }
        updateWindowControls(); pinButton.selected = alwaysOnTop
        pinButton.image = IconLibrary.image(alwaysOnTop ? "pushpin-filled":"pushpin",size:16)
    }
    @objc func pauseOnWake() {
        if !UserDefaults.standard.bool(forKey:"autoplay") { web.evaluateJavaScript("window.__moyaMusic?.silence(); null",completionHandler:nil) }
    }
    @objc func showConnectionSettings() {
        guard !windowTransition else { return }
        connectionPanel.load(connectionSettings,password:selfTest || connectionSettings.username.isEmpty ? "":ConnectionSettings.password())
        presentOverlay(settings:true)
    }
    func applyConnectionSettings() {
        let password = connectionSettings.enabled && !connectionSettings.username.isEmpty ? ConnectionSettings.password():""
        connectionSettings.apply(to:web.configuration.websiteDataStore,password:password)
        artworkTask?.cancel(); artworkSession.invalidateAndCancel()
        artworkSession = connectionSettings.artworkSession(password:password)
        settingsButton.selected = false
        settingsButton.toolTip = "Настройки виджета и подключения"
    }
}
