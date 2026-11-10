import AppKit
import WebKit

final class Render: NSObject, WKScriptMessageHandler {
    var web: WKWebView!
    let folder = URL(fileURLWithPath: CommandLine.arguments[1])
    func start() throws {
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "svg" }
        var icons: [String: String] = [:]
        for f in files {
            icons[f.deletingPathExtension().lastPathComponent] = try String(contentsOf: f, encoding: .utf8)
        }
        let json = String(data: try JSONSerialization.data(withJSONObject: icons), encoding: .utf8)!
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "done")
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 120, height: 120), configuration: config)
        web.loadHTMLString(
            """
            <html><script>
            (async()=>{let output={};for(const [name,svg] of Object.entries(\(json))){
             const image=new Image();image.src='data:image/svg+xml;base64,'+btoa(svg);
             await image.decode();const canvas=document.createElement('canvas');canvas.width=96;canvas.height=96;
             canvas.getContext('2d').drawImage(image,0,0,96,96);output[name]=canvas.toDataURL('image/png').split(',')[1];
            }window.webkit.messageHandlers.done.postMessage(output)})().catch(e=>window.webkit.messageHandlers.done.postMessage({error:String(e)}));
            </script></html>
            """, baseURL: nil)
    }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        guard let values = m.body as? [String: String], values["error"] == nil else {
            print("Render failed: \(m.body)")
            exit(1)
        }
        for (name, value) in values {
            try! Data(base64Encoded: value)!.write(to: folder.appendingPathComponent(name + ".png"))
        }
        print("Rendered \(values.count) icons")
        NSApp.terminate(nil)
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let render = Render()
try render.start()
DispatchQueue.main.asyncAfter(deadline: .now() + 20) { exit(1) }
app.run()
