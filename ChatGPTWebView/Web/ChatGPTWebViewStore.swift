import Foundation
import UIKit
import WebKit

@MainActor
final class ChatGPTWebViewStore: ObservableObject {
    let webView: WKWebView
    let coordinator: SecureChatGPTWebViewCoordinator

    private struct CapturedBrowserState: Decodable {
        let origin: String
        let localStorage: [String: String]
        let lastURL: String
    }

    private let startURL: URL
    private let initialURL: URL
    private let profile: ChatGPTProfile
    private let cookieVault: ChatGPTProfileCookieVault
    private let browserStateVault: ChatGPTProfileBrowserStateVault
    private let onDetectedDisplayName: (String, String) -> Void
    private var didPrepareInitialLoad = false
    private var didDetectDisplayName = false
    private var explicitLogoutDetected = false
    private var typingPriorityActive = false
    private var captureDeferredForTyping = false
    private var sessionMutationGeneration = 0
    private var navigationGeneration = 0
    private var logoutNavigationGeneration: Int?
    private var delayedCaptureTask: Task<Void, Never>?

    init(
        startURL: URL = URL(string: "https://chatgpt.com/")!,
        initialURL: URL? = nil,
        profile: ChatGPTProfile = ChatGPTProfile(
            id: ChatGPTProfile.primaryID,
            displayName: "Current User",
            kind: .primary
        ),
        cookieVault: ChatGPTProfileCookieVault = ChatGPTProfileCookieVault(),
        browserStateVault: ChatGPTProfileBrowserStateVault = ChatGPTProfileBrowserStateVault(),
        onDetectedDisplayName: @escaping (String, String) -> Void = { _, _ in }
    ) {
        self.startURL = startURL
        self.profile = profile
        self.cookieVault = cookieVault
        self.browserStateVault = browserStateVault
        self.onDetectedDisplayName = onDetectedDisplayName
        self.coordinator = SecureChatGPTWebViewCoordinator()

        let isPersistentProfile = profile.kind != .guest
        let shouldRestorePersistentSession = !isPersistentProfile
            || browserStateVault.shouldRestoreSession(profileID: profile.id)
        self.explicitLogoutDetected = isPersistentProfile && !shouldRestorePersistentSession
        self.logoutNavigationGeneration = self.explicitLogoutDetected ? 0 : nil

        let restoredURL = isPersistentProfile && shouldRestorePersistentSession
            ? browserStateVault.lastURL(profileID: profile.id)
            : nil
        self.initialURL = restoredURL ?? initialURL ?? startURL

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = profile.kind == .primary ? .default() : .nonPersistent()
        configuration.allowsInlineMediaPlayback = true

        if isPersistentProfile {
            configuration.userContentController.add(
                coordinator,
                name: SecureChatGPTWebViewCoordinator.profileLogoutMessageName
            )
            configuration.userContentController.addUserScript(
                WKUserScript(
                    source: Self.persistentProfileLogoutDetectionScript,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                )
            )

            if shouldRestorePersistentSession,
               let restoreScript = browserStateVault.documentStartRestoreScript(
                profileID: profile.id,
                overwriteExistingValues: profile.kind == .saved
               ) {
                configuration.userContentController.addUserScript(
                    WKUserScript(
                        source: restoreScript,
                        injectionTime: .atDocumentStart,
                        forMainFrameOnly: true
                    )
                )
            }
        }

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
                guard let self else { return }
                self.navigationGeneration += 1
                self.scheduleProfileStateCapture()
            }
        }
        coordinator.logoutDetectedHandler = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleExplicitLogoutDetected()
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

        if profile.kind != .guest {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.restorePersistentProfileCookies()
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

    func setTypingPriority(_ isTyping: Bool) {
        guard typingPriorityActive != isTyping else { return }
        typingPriorityActive = isTyping

        if isTyping {
            if delayedCaptureTask != nil {
                captureDeferredForTyping = true
            }
            delayedCaptureTask?.cancel()
            delayedCaptureTask = nil
            return
        }

        if captureDeferredForTyping {
            captureDeferredForTyping = false
            scheduleProfileStateCapture()
        }
    }

    func persistProfileSession() async {
        await captureProfileState(force: true)
    }

    func removeSavedProfileSession() async {
        guard profile.kind == .saved else { return }

        sessionMutationGeneration += 1
        explicitLogoutDetected = true
        logoutNavigationGeneration = navigationGeneration
        captureDeferredForTyping = false
        delayedCaptureTask?.cancel()
        delayedCaptureTask = nil
        webView.stopLoading()
        cookieVault.delete(profileID: profile.id)
        browserStateVault.delete(profileID: profile.id)
        await removeAllWebsiteData()
    }

    func resetGuestSession() async {
        guard profile.kind == .guest else { return }

        webView.stopLoading()
        await removeAllWebsiteData()
        didPrepareInitialLoad = true
        webView.load(URLRequest(url: startURL))
    }

    private func handleExplicitLogoutDetected() {
        guard profile.kind != .guest else { return }

        sessionMutationGeneration += 1
        explicitLogoutDetected = true
        logoutNavigationGeneration = navigationGeneration
        didDetectDisplayName = false
        captureDeferredForTyping = false
        delayedCaptureTask?.cancel()
        delayedCaptureTask = nil
        cookieVault.delete(profileID: profile.id)
        browserStateVault.markLoggedOut(profileID: profile.id)
    }

    private func scheduleProfileStateCapture() {
        delayedCaptureTask?.cancel()

        guard !typingPriorityActive else {
            captureDeferredForTyping = true
            delayedCaptureTask = nil
            return
        }

        delayedCaptureTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, let self else { return }

            guard !self.typingPriorityActive else {
                self.captureDeferredForTyping = true
                return
            }

            await self.captureProfileState(force: false)
        }
    }

    private func captureProfileState(force: Bool) async {
        if typingPriorityActive && !force {
            captureDeferredForTyping = true
            return
        }

        var detectedDisplayName: String?
        if !didDetectDisplayName || explicitLogoutDetected {
            detectedDisplayName = await detectCurrentAccountDisplayName()
        }

        if explicitLogoutDetected {
            let logoutGeneration = logoutNavigationGeneration ?? navigationGeneration
            guard navigationGeneration > logoutGeneration,
                  isAuthenticatedChatGPTURL(webView.url),
                  let detectedDisplayName,
                  !detectedDisplayName.isEmpty else {
                cookieVault.delete(profileID: profile.id)
                browserStateVault.markLoggedOut(profileID: profile.id)
                return
            }

            sessionMutationGeneration += 1
            browserStateVault.markActive(profileID: profile.id)
            explicitLogoutDetected = false
            logoutNavigationGeneration = nil
            didDetectDisplayName = true
            onDetectedDisplayName(profile.id, detectedDisplayName)
        }

        let captureGeneration = sessionMutationGeneration

        if profile.kind != .guest {
            let cookies = await allCookies()
            guard captureGeneration == sessionMutationGeneration, !explicitLogoutDetected else {
                return
            }

            let browserState = await captureCurrentBrowserState()
            guard captureGeneration == sessionMutationGeneration, !explicitLogoutDetected else {
                return
            }

            cookieVault.save(cookies, profileID: profile.id)
            if let browserState {
                browserStateVault.save(
                    origin: browserState.origin,
                    localStorage: browserState.localStorage,
                    lastURL: browserState.lastURL,
                    profileID: profile.id
                )
            }
        }

        guard profile.kind != .guest, !didDetectDisplayName else {
            return
        }

        let displayName: String?
        if let detectedDisplayName {
            displayName = detectedDisplayName
        } else {
            displayName = await detectCurrentAccountDisplayName()
        }

        guard let displayName, !displayName.isEmpty else {
            return
        }

        didDetectDisplayName = true
        onDetectedDisplayName(profile.id, displayName)
    }

    private func restorePersistentProfileCookies() async {
        guard browserStateVault.shouldRestoreSession(profileID: profile.id) else {
            return
        }

        let existingCookies = await allCookies()
        let existingCookieIDs = Set(existingCookies.map(cookieIdentity))
        let savedCookies = cookieVault.load(profileID: profile.id)

        for cookie in savedCookies where !existingCookieIDs.contains(cookieIdentity(cookie)) {
            await setCookie(cookie)
        }
    }

    private func cookieIdentity(_ cookie: HTTPCookie) -> String {
        "\(cookie.name)\u{0}\(cookie.domain.lowercased())\u{0}\(cookie.path)"
    }

    private func captureCurrentBrowserState() async -> CapturedBrowserState? {
        let script = #"""
        (() => {
          const values = {};
          try {
            for (let index = 0; index < window.localStorage.length; index++) {
              const key = window.localStorage.key(index);
              if (key === null) continue;
              const value = window.localStorage.getItem(key);
              if (value !== null) values[key] = value;
            }
          } catch (_) {}

          return JSON.stringify({
            origin: window.location.origin || '',
            localStorage: values,
            lastURL: window.location.href || ''
          });
        })();
        """#

        guard let raw = await evaluateJavaScript(script) as? String,
              let data = raw.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(CapturedBrowserState.self, from: data)
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

    private func isAuthenticatedChatGPTURL(_ url: URL?) -> Bool {
        guard let url,
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              host == "chatgpt.com" || host.hasSuffix(".chatgpt.com") else {
            return false
        }

        return !url.path.lowercased().hasPrefix("/auth")
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

        return await evaluateJavaScript(script) as? String
    }

    private func evaluateJavaScript(_ script: String) async -> Any? {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(script) { value, _ in
                continuation.resume(returning: value)
            }
        }
    }

    private static let persistentProfileLogoutDetectionScript = #"""
    (() => {
      const normalize = (value) => String(value || '')
        .replace(/\s+/g, ' ')
        .trim()
        .toLowerCase();

      document.addEventListener('click', (event) => {
        const target = event.target instanceof Element
          ? event.target.closest('button,a,[role="menuitem"],[role="button"]')
          : null;
        if (!target) return;

        const labels = [
          target.innerText,
          target.textContent,
          target.getAttribute('aria-label'),
          target.getAttribute('title')
        ].filter(Boolean).map(normalize);

        if (!labels.some((label) => /^(log\s*out|logout|sign\s*out)$/.test(label))) return;
        try {
          window.webkit.messageHandlers.chatGPTProfileLogout.postMessage('logout');
        } catch (_) {}
      }, true);
    })();
    """#
}

final class SecureChatGPTWebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    static let profileLogoutMessageName = "chatGPTProfileLogout"

    var navigationDidFinishHandler: ((WKWebView) -> Void)?
    var logoutDetectedHandler: (() -> Void)?

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

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.profileLogoutMessageName else { return }
        logoutDetectedHandler?()
    }

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
