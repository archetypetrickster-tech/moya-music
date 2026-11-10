# Local end-to-end WKWebView routing tests; requires macOS 14+ and Swift.
import socket,threading,subprocess,tempfile,shutil
from pathlib import Path
base=Path(__file__).resolve().parents[1]
root=Path(tempfile.mkdtemp(prefix='moya-proxy-test-'))
ports=[]
def server(kind):
 s=socket.socket();s.bind(('127.0.0.1',0));s.listen();ports.append(s.getsockname()[1])
 def run():
  while True:
   c,_=s.accept();c.settimeout(10)
   try:
    def read(n):
     b=b''
     while len(b)<n:
      chunk=c.recv(n-len(b))
      if not chunk: raise EOFError()
      b+=chunk
     return b
    def headers():
     b=b''
     while b'\r\n\r\n' not in b:b+=read(1)
     return b
    if kind=='SOCKS':
     h=read(2);read(h[1]);c.sendall(b'\x05\x00');h=read(4)
     read(4 if h[3]==1 else 16 if h[3]==4 else read(1)[0]);read(2)
     c.sendall(b'\x05\x00\x00\x01\x7f\x00\x00\x01\x00\x50');headers()
    else:
     h=headers()
     if h.startswith(b'CONNECT '):c.sendall(b'HTTP/1.1 200 Connection Established\r\n\r\n');headers()
    body=('PROXY_'+kind).encode();c.sendall(b'HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: '+str(len(body)).encode()+b'\r\nConnection: close\r\n\r\n'+body)
   except Exception:pass
   finally:c.close()
 threading.Thread(target=run,daemon=True).start()
server('HTTP');server('SOCKS')
model=(base/'ConnectionSettings.swift').read_text().split('private final class ProxyChoice:')[0]
(root/'proxy-test.swift').write_text(model+'''
final class Test: NSObject, WKNavigationDelegate {
 var views:[WKWebView] = []; var passed=0
 func run() {
  for (index,port) in PORTS.enumerated() {
   let settings=ConnectionSettings(enabled:true,socks:index==1,host:"127.0.0.1",port:String(port))
   let config=WKWebViewConfiguration();config.websiteDataStore = .nonPersistent()
   settings.apply(to:config.websiteDataStore,password:"")
   let web=WKWebView(frame:.zero,configuration:config);views.append(web);web.navigationDelegate=self
   web.load(URLRequest(url:URL(string:"http://proxy-fixture.invalid/")!))
  }
 }
 func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) {
  webView.evaluateJavaScript("document.body.innerText") { value,error in
   guard let text=value as? String,text.hasPrefix("PROXY_") else {print("PROXY_TEST_FAILED",String(describing:error));exit(1)}
   print(text+"_OK");fflush(stdout);self.passed+=1;if self.passed==2 {NSApp.terminate(nil)}
  }
 }
 func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error) {print("PROXY_TEST_FAILED",error);exit(1)}
}
let app=NSApplication.shared;app.setActivationPolicy(.accessory)
let test=Test();DispatchQueue.main.async {test.run()}
DispatchQueue.main.asyncAfter(deadline:.now()+25) {print("PROXY_TEST_TIMEOUT");exit(1)}
app.run()
'''.replace('PORTS',str(ports)))
try:
 subprocess.run(['swift',str(root/'proxy-test.swift')],check=True)
finally:
 shutil.rmtree(root)
