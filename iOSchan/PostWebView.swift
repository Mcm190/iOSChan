import SwiftUI
import WebKit

// Access shared process pool for consistent cookies/clearance with captcha

struct PostWebView: UIViewRepresentable {
    let boardID: String
    let threadNo: Int? // nil = new thread
    let prefillName: String
    let prefillSubject: String
    let prefillComment: String

    func makeCoordinator() -> Coordinator {
        Coordinator(
            boardID: boardID,
            threadNo: threadNo,
            prefillName: prefillName,
            prefillSubject: prefillSubject,
            prefillComment: prefillComment
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Share process pool with captcha so cookies/clearance are consistent
        config.processPool = CaptchaWebViewController.sharedProcessPool
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Only load once
        if webView.url != nil { return }

        let urlString: String
        if let threadNo {
            urlString = "https://boards.4chan.org/\(boardID)/thread/\(threadNo)"
        } else {
            urlString = "https://boards.4chan.org/\(boardID)/"
        }

        guard let url = URL(string: urlString) else { return }
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        webView.load(req)
    }

    // MARK: - Coordinator
    final class Coordinator: NSObject, WKNavigationDelegate {
        let boardID: String
        let threadNo: Int?

        let prefillName: String
        let prefillSubject: String
        let prefillComment: String

        private var didPrefill = false

        init(boardID: String, threadNo: Int?, prefillName: String, prefillSubject: String, prefillComment: String) {
            self.boardID = boardID
            self.threadNo = threadNo
            self.prefillName = prefillName
            self.prefillSubject = prefillSubject
            self.prefillComment = prefillComment
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Some pages do an extra internal navigation; keep it simple
            // but don’t spam.
            guard !didPrefill else { return }
            didPrefill = true

            let js = makePrefillJS(
                name: prefillName,
                subject: prefillSubject,
                comment: prefillComment,
                isReply: threadNo != nil
            )

            webView.evaluateJavaScript(js) { result, error in
                if let error {
                    print("Prefill JS error: \(error)")
                } else {
                    // print("Prefill JS result:", result ?? "nil")
                }
            }
        }

        private func makePrefillJS(name: String, subject: String, comment: String, isReply: Bool) -> String {
            let nameJS = jsonStringLiteral(name)
            let subjectJS = jsonStringLiteral(subject)
            let commentJS = jsonStringLiteral(comment)

            // Strategy:
            // 1) Try to click "Start a New Thread" (board page) or "Reply" (thread page).
            // 2) Find the post form inputs by name attributes.
            // 3) Fill them and scroll into view.

            return """
            (function() {
              function clickIfExists(sel) {
                var el = document.querySelector(sel);
                if (el) { el.click(); return true; }
                return false;
              }

              function setVal(sel, val) {
                var el = document.querySelector(sel);
                if (!el) return false;
                el.value = val;
                el.dispatchEvent(new Event('input', { bubbles: true }));
                el.dispatchEvent(new Event('change', { bubbles: true }));
                return true;
              }

              // Try common UI triggers
              // Board page: "Start a New Thread" is often a link/button with class/ID variations
              if (!\(isReply ? "true" : "false")) {
                clickIfExists('a[href*="#post"], a[href*="post"], a:contains("Start a New Thread")');
                // Some pages use a button with id "togglePostFormLink" or similar
                clickIfExists('#togglePostFormLink');
                clickIfExists('.new-thread-button');
              } else {
                // Thread page: there’s usually a Reply button/link
                clickIfExists('a.replylink, a#replylink, .reply-button, a[href*="#post"]');
              }

              // Fill fields (these are stable across many themes)
              var nameSet = \(nameJS).length ? setVal('input[name="name"]', \(nameJS)) : true;

              var subSet = true;
              if (!\(isReply ? "true" : "false")) {
                subSet = \(subjectJS).length ? setVal('input[name="sub"]', \(subjectJS)) : true;
              }

              var comSet = \(commentJS).length ? setVal('textarea[name="com"]', \(commentJS)) : true;

              // Scroll to comment box
              var com = document.querySelector('textarea[name="com"]');
              if (com) com.scrollIntoView({ behavior: 'smooth', block: 'center' });

              return { nameSet: nameSet, subSet: subSet, comSet: comSet, url: location.href };
            })();
            """
        }

        private func jsonStringLiteral(_ s: String) -> String {
            // Encode string as JSON string literal (safe for JS)
            if let data = try? JSONSerialization.data(withJSONObject: [s], options: []),
               let json = String(data: data, encoding: .utf8),
               json.count >= 4 {
                // ["..."] -> "..."
                let start = json.index(after: json.startIndex)
                let end = json.index(before: json.endIndex)
                return String(json[start..<end])
            }
            return "\"\""
        }
    }
}

