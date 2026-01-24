import SwiftUI
import WebKit

//this is pretty fucked tbh will work on at some point just open in safari to post

class CaptchaWebViewController: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
    static let shared = CaptchaWebViewController()
    
    var webView: WKWebView!
    var currentSuccessCallback: ((String, String?) -> Void)?
    private var currentBoardID: String?
    private var warmedBoards = Set<String>()
    private var warmedHosts = Set<String>()
    private var pendingCaptchaURL: URL?
    private var primeQueue: [URL] = []
    private var isPriming = false
    private var didPrimeHCaptcha = false
    
    override private init() {
        super.init()
        setupWebView()
    }
    
    private func setupWebView() {
        let config = WKWebViewConfiguration()
//        config.processPool = CaptchaWebViewController.sharedProcessPool
        config.defaultWebpagePreferences.preferredContentMode = .mobile
        
        let prefs = WKPreferences()
        prefs.javaScriptCanOpenWindowsAutomatically = true
        config.preferences = prefs
        config.allowsAirPlayForMediaPlayback = true
        config.allowsInlineMediaPlayback = true
        config.websiteDataStore = .default()
        
        let js = """
        (function() {
            // Proactively request storage access for third-party frames (hCaptcha) to avoid CF loops
            function tryRequestStorageAccessGestureBound() {
                try {
                    // Safari 17+: requestStorageAccessFor (best effort)
                    if (typeof document.requestStorageAccessFor === 'function') {
                        try { document.requestStorageAccessFor('https://hcaptcha.com').catch(function(){}); } catch(e) {}
                        try { document.requestStorageAccessFor('https://newassets.hcaptcha.com').catch(function(){}); } catch(e) {}
                        try { document.requestStorageAccessFor('https://assets.hcaptcha.com').catch(function(){}); } catch(e) {}
                    }
                    // Fallback: requestStorageAccess on gesture
                    if (typeof document.requestStorageAccess === 'function') {
                        try { document.requestStorageAccess().catch(function(){}); } catch(e) {}
                    }
                } catch (e) {}
            }

            function installGestureHandlers() {
                var events = ['pointerdown', 'click', 'touchstart', 'keydown'];
                events.forEach(function(ev){
                    try {
                        document.addEventListener(ev, function(e){
                            // Only treat keydown for Space/Enter as a gesture
                            if (ev === 'keydown') {
                                var code = e.code || e.key || '';
                                var ok = (code === 'Space' || code === 'Enter' || code === 'NumpadEnter');
                                if (!ok) return;
                            }
                            tryRequestStorageAccessGestureBound();
                        }, true);
                    } catch (e) {}
                });
            }

            try {
                if (typeof document.hasStorageAccess === 'function') {
                    document.hasStorageAccess().then(function(has) {
                        if (!has) { tryRequestStorageAccessGestureBound(); }
                    }).catch(function(){});
                } else {
                    tryRequestStorageAccessGestureBound();
                }
            } catch (e) {}

            installGestureHandlers();

            function postTokenIfAvailable() {
                try {
                    var tokenInput = document.querySelector('[name="h-captcha-response"], [name="g-recaptcha-response"]');
                    var token = tokenInput ? tokenInput.value : null;
                    if (token && token.length > 10) {
                        try { window.webkit.messageHandlers.captchaHandler.postMessage(token); } catch(e) {}
                        return true;
                    }
                } catch (e) {}
                return false;
            }

            function hookHCaptcha() {
                try {
                    if (window.hcaptcha && typeof window.hcaptcha.on === 'function') {
                        window.hcaptcha.on('pass', function(token){
                            try { window.webkit.messageHandlers.captchaHandler.postMessage(token); } catch(e) {}
                        });
                        return true;
                    }
                } catch (e) {}
                return false;
            }

            function hookFormSubmit() {
                try {
                    var form = document.querySelector('form');
                    if (!form) return false;
                    form.addEventListener('submit', function(ev){
                        try {
                            var tokenInput = document.querySelector('[name="h-captcha-response"], [name="g-recaptcha-response"]');
                            var token = tokenInput ? tokenInput.value : null;
                            if (token && token.length > 10) {
                                try { window.webkit.messageHandlers.captchaHandler.postMessage(token); } catch(e) {}
                            }
                        } catch(e) {}
                    }, true);
                    return true;
                } catch (e) {}
                return false;
            }

            var attempts = 0;
            var iv = setInterval(function(){
                attempts++;
                var ok = postTokenIfAvailable() || hookHCaptcha() || hookFormSubmit();
                if (ok || attempts > 200) { clearInterval(iv); }
            }, 250);

            document.addEventListener('visibilitychange', function(){ if (!document.hidden) { postTokenIfAvailable(); hookHCaptcha(); } }, true);
        })();
        """
        let script = WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(script)
        config.userContentController.add(self, name: "captchaHandler")
        
        webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/121.0.6167.172 Mobile/15E148 Safari/604.1"
        webView.uiDelegate = self
        webView.navigationDelegate = self
        webView.isOpaque = true
        webView.backgroundColor = .systemBackground
    }
    
    func load(boardID: String, threadNo: Int?, onToken: @escaping (String, String?) -> Void) {
        self.currentBoardID = boardID
        self.currentSuccessCallback = onToken
        
        var components = URLComponents(string: "https://sys.4chan.org/captcha")!
        var queryItems = [URLQueryItem(name: "board", value: boardID)]
        if let thread = threadNo {
            queryItems.append(URLQueryItem(name: "thread_id", value: String(thread)))
        }
        queryItems.append(URLQueryItem(name: "color", value: "light"))
        components.queryItems = queryItems
        
        guard let url = components.url else { return }
        
        if !warmedHosts.contains("sys.4chan.org") {
            pendingCaptchaURL = url
            if let warmSys = URL(string: "https://sys.4chan.org/") {
                let warmReq = URLRequest(url: warmSys)
                webView.load(warmReq)
                return
            }
        }
        
        if !warmedBoards.contains(boardID) {
            pendingCaptchaURL = url
            if let warmURL = URL(string: "https://boards.4chan.org/\(boardID)/") {
                let warmReq = URLRequest(url: warmURL)
                webView.load(warmReq)
                return
            }
        }
        
        if !didPrimeHCaptcha && !isPriming {
            pendingCaptchaURL = url
            let store = webView.configuration.websiteDataStore.httpCookieStore
            store.getAllCookies { cookies in
                for c in cookies {
                    if c.domain.contains("hcaptcha.com") { store.delete(c) }
                }
            }
            primeQueue = [
                URL(string: "https://hcaptcha.com/")!,
                URL(string: "https://newassets.hcaptcha.com/")!,
                URL(string: "https://assets.hcaptcha.com/")!
            ]
            isPriming = true
            if let first = primeQueue.first {
                primeQueue.removeFirst()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.webView.load(URLRequest(url: first))
                }
                return
            }
        }
        
        if webView.url?.absoluteString != url.absoluteString {
            var request = URLRequest(url: url)
            // Referer is critical for 4chan/Cloudflare trust
            request.setValue("https://boards.4chan.org/\(boardID)/", forHTTPHeaderField: "Referer")
            webView.load(request)
        }
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let token = message.body as? String {
            print("✅ Token captured!")
            print("[Captcha] token length=\(token.count)")
            DispatchQueue.main.async {
                self.currentSuccessCallback?(token, nil)
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let host = webView.url?.host {
            if host == "hcaptcha.com" || host == "newassets.hcaptcha.com" || host == "assets.hcaptcha.com" {
                if isPriming {
                    if let next = primeQueue.first {
                        primeQueue.removeFirst()
                        webView.load(URLRequest(url: next))
                        return
                    } else {
                        isPriming = false
                        didPrimeHCaptcha = true
                    }
                } else {
                    didPrimeHCaptcha = true
                }
            }
        }
        // If we just finished loading the board page, proceed to captcha
        if let host = webView.url?.host, let board = currentBoardID {
            if host == "boards.4chan.org" {
                warmedBoards.insert(board)
                warmedHosts.insert(host)
            }
            if host == "sys.4chan.org" {
                warmedHosts.insert(host)
            }
            if let pending = pendingCaptchaURL, warmedHosts.contains("sys.4chan.org") && warmedBoards.contains(board) {
                pendingCaptchaURL = nil
                var req = URLRequest(url: pending)
                req.setValue("https://boards.4chan.org/\(board)/", forHTTPHeaderField: "Referer")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    webView.load(req)
                }
                return
            }
        }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            print("[Cookies] count=\(cookies.count) names=\(cookies.map{ $0.name }.joined(separator: ","))")
            CookieBridge.shared.update(with: cookies)
        }
    }
}

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

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url {
            let urlString = url.absoluteString
            print("[NavAction] \(urlString)")
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

struct ChanCaptchaView: UIViewRepresentable {
    let boardID: String
    let threadNo: Int?
    let onToken: (String, String?) -> Void

    func makeUIView(context: Context) -> WKWebView {
        return CaptchaWebViewController.shared.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        CaptchaWebViewController.shared.load(boardID: boardID, threadNo: threadNo, onToken: onToken)
    }
}

