import SwiftUI
import WebKit

struct SecureChatGPTWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true

        if #available(iOS 14.0, *) {
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.keyboardDismissMode = .interactive
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url == nil {
            webView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let allowedHostSuffixes = [
            "chatgpt.com",
            "openai.com",
            "oaistatic.com",
            "oaiusercontent.com",
            "auth0.com",
            "google.com",
            "gstatic.com",
            "googleusercontent.com",
            "apple.com",
            "icloud.com",
            "microsoft.com",
            "microsoftonline.com",
            "live.com",
            "msauth.net"
        ]

        private let allowedSchemes = [
            "https",
            "about",
            "blob",
            "data"
        ]

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            decisionHandler(isAllowed(url: url) ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard navigationAction.targetFrame == nil,
                  let url = navigationAction.request.url,
                  isAllowed(url: url) else {
                return nil
            }

            webView.load(URLRequest(url: url))
            return nil
        }

        private func isAllowed(url: URL) -> Bool {
            guard let scheme = url.scheme?.lowercased(), allowedSchemes.contains(scheme) else {
                return false
            }

            if scheme == "about" || scheme == "blob" || scheme == "data" {
                return true
            }

            guard scheme == "https", let host = url.host?.lowercased() else {
                return false
            }

            return allowedHostSuffixes.contains { suffix in
                host == suffix || host.hasSuffix("." + suffix)
            }
        }

        @available(iOS 15.0, *)
        func webView(_ webView: WKWebView,
                     requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.prompt)
        }
    }
}
