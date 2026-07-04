import Foundation
import UIKit
import WebKit

@MainActor
final class ChatGPTWebViewStore: ObservableObject {
    let webView: WKWebView
    let coordinator: SecureChatGPTWebViewCoordinator

    private let startURL: URL
    private let initialURL: URL
    private let profile: ChatGPTProfile
    private let cookieVault: ChatGPTProfileCookieVault
    private let onDetectedDisplayName: (String, String) -> Void
    private var didPrepareInitialLoad = false

    init(
        startURL: URL = URL(string: "https://chatgpt.com/")!,
        initialURL: URL? = nil,
        profile: ChatGPTProfile = ChatGPTProfile(
            id: ChatGPTProfile.primaryID,
            displayName: "Current User",
            kind: .primary
        ),
        cookieVault: ChatGPTProfileCookieVault = ChatGPTProfileCookieVault(),
        onDetectedDisplayName: @escaping (String, String) -> Void = { _, _ in }
    ) {
        self.startURL = startURL
        self.initialURL = initialURL ?? startURL
        self.profile = profile
        self.cookieVault = cookieVault
        self.onDetectedDisplayName = onDetectedDisplayName
        self.coordinator = SecureChatGPTWebViewCoordinator()

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = profile.kind == .primary ? .default() : .nonPersistent()
        configuration.allowsInlineMediaPlayback = true

        if #available(iOS 14.0, *) {
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.keyboardDismissMode = .interactive
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"
        self.webView = webView

        coordinator.navigationDidFinishHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.captureProfileState()
            }
        }
    }

    func loadIfNeeded() {
        guard webView.url == nil, !webView.isLoading else {
            return
        }

        guard !didPrepareInitialLoad else {
            webView.load(URLRequest(url: startURL))
            return
        }

        didPrepareInitialLoad = true

        if profile.kind == .saved {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.restoreSavedProfileCookies()
                guard self.webView.url == nil, !self.webView.isLoading else { return }
                self.webView.load(URLRequest(url: self.initialURL))
            }
        } else {
            webView.load(URLRequest(url: initialURL))
        }
    }

    func stopCurrentActivity() {
        webView.stopLoading()
    }

    func reloadCurrentSession() {
        if webView.isLoading {
            webView.stopLoading()
        }

        if webView.url == nil {
            loadIfNeeded()
        } else {
            webView.reload()
        }
    }

    func startNewChat() {
        if webView.isLoading {
            webView.stopLoading()
        }
        webView.load(URLRequest(url: startURL))
    }

    func persistProfileSession() async {
        await captureProfileState()
    }

    func resetGuestSession() async {
        guard profile.kind == .guest else { return }

        webView.stopLoading()
        await removeAllWebsiteData()
        didPrepareInitialLoad = true
        webView.load(URLRequest(url: startURL))
    }

    private func captureProfileState() async {
        if profile.kind == .saved {
            let cookies = await allCookies()
            cookieVault.save(cookies, profileID: profile.id)
        }

        guard profile.kind != .guest,
              let displayName = await detectCurrentAccountDisplayName(),
              !displayName.isEmpty else {
            return
        }

        onDetectedDisplayName(profile.id, displayName)
    }

    private func restoreSavedProfileCookies() async {
        let cookies = cookieVault.load(profileID: profile.id)
        for cookie in cookies {
            await setCookie(cookie)
        }
    }

    private func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private func setCookie(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) {
                continuation.resume()
            }
        }
    }

    private func removeAllWebsiteData() async {
        await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: .distantPast
            ) {
                continuation.resume()
            }
        }
    }

    private func detectCurrentAccountDisplayName() async -> String? {
        let script = #"""
        (() => {
          const clean = (value) => String(value || '')
            .replace(/\s+/g, ' ')
            .trim();
          const emailPattern = /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i;
          const candidates = Array.from(document.querySelectorAll(
            'button,[role="button"],[aria-label],[title],[data-testid]'
          ));

          const values = [];
          for (const element of candidates) {
            const label = clean([
              element.getAttribute('aria-label'),
              element.getAttribute('title'),
              element.innerText,
              element.textContent
            ].filter(Boolean).join(' '));
            if (label) values.push(label);
          }

          for (const value of values) {
            const email = value.match(emailPattern);
            if (email) return email[0];
          }

          for (const element of candidates) {
            const metadata = clean([
              element.getAttribute('aria-label'),
              element.getAttribute('title'),
              element.getAttribute('data-testid')
            ].filter(Boolean).join(' ')).toLowerCase();
            if (!metadata.includes('profile') && !metadata.includes('account') && !metadata.includes('user')) continue;

            const text = clean(element.innerText || element.textContent || '');
            if (!text || text.length > 80) continue;
            if (/^(profile|account|user|menu|open profile menu)$/i.test(text)) continue;
            return text;
          }

          return '';
        })();
        """#

        let value = try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any?, Error>) in
            webView.evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value)
                }
            }
        }

        return value as? String
    }
}

final class SecureChatGPTWebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    var navigationDidFinishHandler: ((WKWebView) -> Void)?

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

    private let internalSchemes = [
        "https",
        "about",
        "blob",
        "data"
    ]

    private let externalSchemes = [
        "http",
        "https",
        "mailto",
        "tel",
        "sms"
    ]

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationDidFinishHandler?(webView)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        if isAllowedInsideWebView(url: url) {
            decisionHandler(.allow)
            return
        }

        if shouldOpenExternally(url: url, navigationAction: navigationAction) {
            openExternally(url)
        }

        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil,
              let url = navigationAction.request.url else {
            return nil
        }

        if isAllowedInsideWebView(url: url) {
            webView.load(URLRequest(url: url))
        } else if shouldOpenExternally(url: url, navigationAction: navigationAction) {
            openExternally(url)
        }

        return nil
    }

    private func isAllowedInsideWebView(url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), internalSchemes.contains(scheme) else {
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

    private func shouldOpenExternally(url: URL, navigationAction: WKNavigationAction) -> Bool {
        guard let scheme = url.scheme?.lowercased(), externalSchemes.contains(scheme) else {
            return false
        }

        if isAllowedInsideWebView(url: url) {
            return false
        }

        switch navigationAction.navigationType {
        case .linkActivated, .formSubmitted, .other:
            return true
        default:
            return navigationAction.targetFrame == nil
        }
    }

    private func openExternally(_ url: URL) {
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
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
