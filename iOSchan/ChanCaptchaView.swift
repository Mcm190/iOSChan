import SwiftUI
import WebKit

// 1. GLOBAL SHARED WEBVIEW CONTROLLER
// This keeps the WebView alive so cookies & Cloudflare clearance are remembered.
class CaptchaWebViewController: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
    static let shared = CaptchaWebViewController()
    static let sharedProcessPool = WKProcessPool()
    
    var webView: WKWebView!
    var currentSuccessCallback: ((String, String?) -> Void)?
    private var currentBoardID: String?
    private var manualRefererBypass = Set<String>()
    private var warmedBoards = Set<String>()
    private var pendingCaptchaURL: URL?
    
    override private init() {
        super.init()
        setupWebView()
    }
    
    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.processPool = CaptchaWebViewController.sharedProcessPool
        config.defaultWebpagePreferences.preferredContentMode = .mobile
        
        let prefs = WKPreferences()
        prefs.javaScriptCanOpenWindowsAutomatically = true
        config.preferences = prefs
        config.allowsAirPlayForMediaPlayback = true
        config.allowsInlineMediaPlayback = true
        config.websiteDataStore = .default()
        
        // JS Watcher to catch the token automatically
        let js = """
        (function() {
            var interval = setInterval(function() {
                var tokenInput = document.querySelector("[name='h-captcha-response'], [name='g-recaptcha-response']");
                var token = tokenInput ? tokenInput.value : null;
                if (token && token.length > 10) {
                    window.webkit.messageHandlers.captchaHandler.postMessage(token);
                    tokenInput.value = ""; // Clear it so we don't trigger twice
                }
            }, 500);
        })();
        """
        let script = WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        config.userContentController.addUserScript(script)
        config.userContentController.add(self, name: "captchaHandler")
        
        webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        webView.uiDelegate = self
        webView.navigationDelegate = self
        webView.isOpaque = true
        webView.backgroundColor = .systemBackground
    }
    
    // Called when the SwiftUI view appears
    func load(boardID: String, threadNo: Int?, onToken: @escaping (String, String?) -> Void) {
        self.currentBoardID = boardID
        self.currentSuccessCallback = onToken
        
        // Construct the URL
        var components = URLComponents(string: "https://sys.4chan.org/captcha")!
        var queryItems = [URLQueryItem(name: "board", value: boardID)]
        if let thread = threadNo {
            queryItems.append(URLQueryItem(name: "thread_id", value: String(thread)))
        }
        queryItems.append(URLQueryItem(name: "color", value: "light"))
        components.queryItems = queryItems
        
        guard let url = components.url else { return }
        
        // Warm-up Cloudflare clearance on the board domain first
        if !warmedBoards.contains(boardID) {
            pendingCaptchaURL = url
            if let warmURL = URL(string: "https://boards.4chan.org/\(boardID)/") {
                let warmReq = URLRequest(url: warmURL)
                webView.load(warmReq)
                return
            }
        }
        
        // Only reload if we aren't already on this exact page (prevents refreshing the puzzle if you rotate screen)
        if webView.url?.absoluteString != url.absoluteString {
            var request = URLRequest(url: url)
            // Referer is critical for 4chan/Cloudflare trust
            request.setValue("https://boards.4chan.org/\(boardID)/", forHTTPHeaderField: "Referer")
            webView.load(request)
        }
    }
    
    // WKScriptMessageHandler: Captures the token
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let token = message.body as? String {
            print("✅ Token captured!")
            DispatchQueue.main.async {
                self.currentSuccessCallback?(token, nil)
            }
        }
    }
    
    // Cookie Syncing
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // If we just finished loading the board page, proceed to captcha
        if let host = webView.url?.host, let board = currentBoardID {
            if host == "boards.4chan.org" {
                warmedBoards.insert(board)
                if let pending = pendingCaptchaURL {
                    pendingCaptchaURL = nil
                    var req = URLRequest(url: pending)
                    req.setValue("https://boards.4chan.org/\(board)/", forHTTPHeaderField: "Referer")
                    webView.load(req)
                    return
                }
            }
        }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            print("[Cookies] count=\(cookies.count) names=\(cookies.map{ $0.name }.joined(separator: ","))")
            CookieBridge.shared.update(with: cookies)
        }
    }
}

// MARK: - WKUIDelegate (handle target=_blank, JS alerts)
extension CaptchaWebViewController {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Open new windows in the same webView
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webViewDidClose(_ webView: WKWebView) { }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        print("[WKUIDelegate] alert: \(message)")
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        print("[WKUIDelegate] confirm: \(message)")
        completionHandler(true)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        print("[WKUIDelegate] prompt: \(prompt)")
        completionHandler(defaultText)
    }

    // MARK: - Extra logging to diagnose loops
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url {
            let urlString = url.absoluteString
            print("[NavAction] \(urlString)")
            let host = url.host ?? ""
            let path = url.path
            let method = navigationAction.request.httpMethod ?? "GET"
            // Only enforce Referer for the actual captcha endpoint (GET). Do not interfere with CF challenges.
            let isCaptcha = (host == "sys.4chan.org" && path.contains("/captcha"))
            let hasReferer = navigationAction.request.value(forHTTPHeaderField: "Referer") != nil
            if isCaptcha && method == "GET" && !hasReferer && manualRefererBypass.insert(urlString).inserted {
                decisionHandler(.cancel)
                var req = URLRequest(url: url)
                let board = currentBoardID ?? ""
                let referer = board.isEmpty ? "https://boards.4chan.org/" : "https://boards.4chan.org/\(board)/"
                req.setValue(referer, forHTTPHeaderField: "Referer")
                webView.load(req)
                return
            }
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let httpResponse = navigationResponse.response as? HTTPURLResponse {
            print("[NavResponse] status=\(httpResponse.statusCode) url=\(httpResponse.url?.absoluteString ?? "?")")
        }
        decisionHandler(.allow)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        print("[Process] terminated; reloading")
        webView.reload()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("[NavError] provisional: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[NavError] \(error.localizedDescription)")
    }
}

// 2. SWIFTUI WRAPPER
// This is just a thin window into the shared controller
struct ChanCaptchaView: UIViewRepresentable {
    let boardID: String
    let threadNo: Int?
    let onToken: (String, String?) -> Void

    func makeUIView(context: Context) -> WKWebView {
        // Return the existing shared WebView instead of making a new one
        return CaptchaWebViewController.shared.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Tell the controller to load the correct page
        CaptchaWebViewController.shared.load(boardID: boardID, threadNo: threadNo, onToken: onToken)
    }
}

