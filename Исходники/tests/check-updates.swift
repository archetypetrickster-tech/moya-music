// Run: swift tests/check-updates.swift /path/App.app /path/appcast.xml /path/update.zip
// Uses only the PUBLIC key embedded in the built app; no Keychain or network access.
import CryptoKit
import Foundation

let arguments = CommandLine.arguments
precondition(arguments.count == 4, "Expected: app, signed appcast, update archive")
let app = URL(fileURLWithPath: arguments[1])
let plist =
    try PropertyListSerialization.propertyList(
        from: Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")), format: nil)
    as! [String: Any]
for flag in ["SUEnableAutomaticChecks", "SUVerifyUpdateBeforeExtraction", "SURequireSignedFeed"] {
    precondition(plist[flag] as? Bool == true, "Missing updater protection: \(flag)")
}
precondition(plist["SUAutomaticallyUpdate"] as? Bool == false)
precondition(plist["SUAllowsAutomaticUpdates"] as? Bool == false)
precondition(plist["SUEnableSystemProfiling"] as? Bool == false)
let key = try Curve25519.Signing.PublicKey(
    rawRepresentation: Data(base64Encoded: plist["SUPublicEDKey"] as! String)!)
let feed = try Data(contentsOf: URL(fileURLWithPath: arguments[2]))
let marker = Data("<!-- sparkle-signatures:".utf8)
let signatureStart = feed.range(of: marker, options: .backwards)!.lowerBound
let signatureText = String(decoding: feed[signatureStart...], as: UTF8.self)
func field(_ name: String) -> String {
    signatureText.components(separatedBy: "\n").first { $0.hasPrefix(name + ": ") }!
        .components(separatedBy: ": ").last!
}
precondition(Int(field("length")) == signatureStart, "Unsigned data in feed")
let feedSignature = Data(base64Encoded: field("edSignature"))!
let signedFeed = feed.prefix(signatureStart)
precondition(key.isValidSignature(feedSignature, for: signedFeed), "Invalid feed signature")
var damagedFeed = Data(signedFeed)
damagedFeed[0] ^= 1
precondition(!key.isValidSignature(feedSignature, for: damagedFeed), "Modified feed was accepted")
let document = try XMLDocument(data: feed)
let item = try document.nodes(forXPath: "/rss/channel/item").first!
let version = try item.nodes(forXPath: "sparkle:version").first!.stringValue!
precondition(version == plist["CFBundleVersion"] as? String)
let enclosure = try item.nodes(forXPath: "enclosure").first as! XMLElement
let archive = try Data(contentsOf: URL(fileURLWithPath: arguments[3]))
precondition(Int(enclosure.attribute(forName: "length")!.stringValue!) == archive.count)
let signature = Data(base64Encoded: enclosure.attribute(forName: "sparkle:edSignature")!.stringValue!)!
precondition(key.isValidSignature(signature, for: archive), "Invalid archive signature")
var damagedArchive = archive
damagedArchive[0] ^= 1
precondition(!key.isValidSignature(signature, for: damagedArchive), "Modified archive was accepted")
let verify = Process()
verify.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
verify.arguments = ["--verify", "--deep", "--strict", app.path]
try verify.run()
verify.waitUntilExit()
precondition(verify.terminationStatus == 0)
print(
    "UPDATES_OK: signed feed and ZIP match embedded public key; altered bytes rejected; nested signatures valid"
)
