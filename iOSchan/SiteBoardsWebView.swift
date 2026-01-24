import SwiftUI
import WebKit

struct SiteBoardsWebView: View {
    let site: SiteDirectory.Site
    @State private var canGoBack = false
    @State private var goBackRequestTick = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            SiteWebViewRepresentable(site: site, canGoBack: $canGoBack, goBackRequestTick: $goBackRequestTick)
                .edgesIgnoringSafeArea(.all)

            if canGoBack {
                Button(action: { goBackRequestTick &+= 1 }) {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                        .padding([.top, .leading], 12)
                }
            }
        }
    }
}

private struct SiteWebViewRepresentable: UIViewRepresentable {
    let site: SiteDirectory.Site
    @Binding var canGoBack: Bool
    @Binding var goBackRequestTick: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.preferredContentMode = .mobile

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        var request = URLRequest(url: site.baseURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        webView.load(request)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Respond to back button taps
        if context.coordinator.lastGoBackTick != goBackRequestTick {
            context.coordinator.lastGoBackTick = goBackRequestTick
            if webView.canGoBack { webView.goBack() }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: SiteWebViewRepresentable
        var lastGoBackTick: Int = 0
        init(_ parent: SiteWebViewRepresentable) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.canGoBack = webView.canGoBack
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.canGoBack = webView.canGoBack
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Open target=_blank in same webview
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            completionHandler()
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            completionHandler(true)
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            completionHandler(defaultText)
        }
    }
}
