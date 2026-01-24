import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.backgroundColor = .black
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        let ext = url.pathExtension.lowercased()

        let html: String
        if ext == "gif" || ext == "webp" {
            html = """
            <html>
            <body style=\"background-color:black; margin:0; display:flex; justify-content:center; align-items:center; height:100vh;\">
                <img src=\"\(url.absoluteString)\" style=\"max-width:100%; max-height:100%; width:auto; height:auto; display:block; margin:auto;\" />
            </body>
            </html>
            """
        } else {
            // Determine the correct MIME type for video (when possible).
            let mimeType: String?
            switch ext {
            case "mp4":
                mimeType = "video/mp4"
            case "webm":
                mimeType = "video/webm"
            default:
                mimeType = nil
            }
            let sourceTag: String
            if let mimeType {
                sourceTag = "<source src=\"\(url.absoluteString)\" type=\"\(mimeType)\">"
            } else {
                sourceTag = "<source src=\"\(url.absoluteString)\">"
            }
            html = """
            <html>
            <body style=\"background-color:black; margin:0; display:flex; justify-content:center; align-items:center; height:100vh;\">
                <video controls autoplay playsinline style=\"width:100%; max-height:100%;\">
                    \(sourceTag)
                </video>
            </body>
            </html>
            """
        }

        uiView.loadHTMLString(html, baseURL: nil)
    }
}
