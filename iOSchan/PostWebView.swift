import SwiftUI
import WebKit


struct PostWebView: UIViewRepresentable {
    let boardID: String
    let threadNo: Int?
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
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
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
                }
            }
        }

        private func makePrefillJS(name: String, subject: String, comment: String, isReply: Bool) -> String {
            let nameJS = jsonStringLiteral(name)
            let subjectJS = jsonStringLiteral(subject)
            let commentJS = jsonStringLiteral(comment)

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

              if (!\(isReply ? "true" : "false")) {
                clickIfExists('a[href*="#post"], a[href*="post"], a:contains("Start a New Thread")');
                clickIfExists('#togglePostFormLink');
                clickIfExists('.new-thread-button');
              } else {
                clickIfExists('a.replylink, a#replylink, .reply-button, a[href*="#post"]');
              }

              var nameSet = \(nameJS).length ? setVal('input[name="name"]', \(nameJS)) : true;

              var subSet = true;
              if (!\(isReply ? "true" : "false")) {
                subSet = \(subjectJS).length ? setVal('input[name="sub"]', \(subjectJS)) : true;
              }

              var comSet = \(commentJS).length ? setVal('textarea[name="com"]', \(commentJS)) : true;

              var com = document.querySelector('textarea[name="com"]');
              if (com) com.scrollIntoView({ behavior: 'smooth', block: 'center' });

              return { nameSet: nameSet, subSet: subSet, comSet: comSet, url: location.href };
            })();
            """
        }

        private func jsonStringLiteral(_ s: String) -> String {
            if let data = try? JSONSerialization.data(withJSONObject: [s], options: []),
               let json = String(data: data, encoding: .utf8),
               json.count >= 4 {
                let start = json.index(after: json.startIndex)
                let end = json.index(before: json.endIndex)
                return String(json[start..<end])
            }
            return "\"\""
        }
    }
}

