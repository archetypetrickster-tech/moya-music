import AppKit
import CoreAudio

let appIdentifier = "ru.ninesquares.moyamusic"
let appURL = URL(fileURLWithPath: "/Applications/Моя музыка.app")

func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}
func number(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
    var key = address(selector, scope: scope), value: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(object, &key, 0, nil, &size, &value) == noErr else { return nil }
    return value
}
func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
    var key = address(selector), value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = withUnsafeMutablePointer(to: &value) { pointer in
        AudioObjectGetPropertyData(object, &key, 0, nil, &size, UnsafeMutableRawPointer(pointer))
    }
    guard status == noErr, let value else { return "" }
    return value.takeRetainedValue() as String
}
func objects(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
    var key = address(selector, scope: scope), size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(object, &key, 0, nil, &size) == noErr, size > 0 else { return [] }
    var values = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    let status = values.withUnsafeMutableBytes { bytes in AudioObjectGetPropertyData(object, &key, 0, nil, &size, bytes.baseAddress!) }
    return status == noErr ? values : []
}
func connectedHeadphones() -> [String: String] {
    var found: [String:String] = [:]
    for device in objects(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices) {
        guard number(device, kAudioDevicePropertyDeviceIsAlive) == 1 else { continue }
        let streams = objects(device, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        guard !streams.isEmpty else { continue }
        let name = string(device, kAudioObjectPropertyName)
        let terminalIsHeadphones = streams.contains { number($0, kAudioStreamPropertyTerminalType) == kAudioStreamTerminalTypeHeadphones }
        let source = number(device, kAudioDevicePropertyDataSource, scope: kAudioObjectPropertyScopeOutput) ?? 0
        let isHeadphoneJack = source == 0x6864706e || source == 0x68647068
        let knownHeadphones = name.range(of: "airpods|headphones?|headset|наушник|beats|wh-1000|wf-1000|quietcomfort|qc35|qc45|buds", options: [.regularExpression, .caseInsensitive]) != nil
        let isMicrophone = name.range(of: "microphone|микрофон", options: [.regularExpression, .caseInsensitive]) != nil
        guard (terminalIsHeadphones && !isMicrophone) || isHeadphoneJack || knownHeadphones else { continue }
        let uid = string(device, kAudioDevicePropertyDeviceUID)
        found["\(uid.isEmpty ? String(device) : uid):\(source)"] = name
    }
    return found
}
func openPlayer() {
    let runningPlayer = NSRunningApplication.runningApplications(withBundleIdentifier: appIdentifier).contains {
        !$0.isTerminated && $0.executableURL?.lastPathComponent == "MoyaMusic"
    }
    if runningPlayer {
        DistributedNotificationCenter.default().postNotificationName(Notification.Name("ru.ninesquares.moyamusic.headphones"), object: nil, userInfo: nil, deliverImmediately: true)
        return
    }
    let launcher = Process()
    launcher.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    launcher.arguments = [appURL.path]
    do {
        try launcher.run(); launcher.waitUntilExit()
        print(launcher.terminationStatus == 0 ? "Opened player after headphones connection" : "Could not open player")
        fflush(stdout)
        if CommandLine.arguments.contains("--simulate-connection") { exit(launcher.terminationStatus) }
    } catch {
        print("Could not open player: \(error.localizedDescription)"); fflush(stdout)
        if CommandLine.arguments.contains("--simulate-connection") { exit(1) }
    }

}

if CommandLine.arguments.contains("--list") {
    let devices = connectedHeadphones()
    print(devices.isEmpty ? "No headphones connected" : devices.values.sorted().joined(separator: "\n"))
    exit(0)
}
if CommandLine.arguments.contains("--simulate-connection") {
    openPlayer()
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { exit(0) }
    RunLoop.main.run()
    exit(0)
}

var previous = Set(connectedHeadphones().keys)
var checkScheduled = false
func checkConnections() {
    let current = connectedHeadphones()
    let added = Set(current.keys).subtracting(previous)
    previous = Set(current.keys)
    if !added.isEmpty {
        print("Connected: \(added.compactMap { current[$0] }.joined(separator: ", "))")
        fflush(stdout)
        openPlayer()
    }
}
for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
    var key = address(selector)
    AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &key, DispatchQueue.main) { _, _ in
        guard !checkScheduled else { return }
        checkScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            checkScheduled = false
            checkConnections()
        }
    }
}
let timer = DispatchSource.makeTimerSource(queue: .main)
timer.schedule(deadline: .now() + 3, repeating: 3, leeway: .seconds(1))
timer.setEventHandler { checkConnections() }
timer.resume()
print("Headphones watcher started")
fflush(stdout)
RunLoop.main.run()
