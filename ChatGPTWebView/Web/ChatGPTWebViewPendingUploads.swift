import UIKit
import UniformTypeIdentifiers
import WebKit

private final class WebViewOpenPanelDelegate: NSObject, UIDocumentPickerDelegate {
    private let completion: ([URL]?) -> Void

    init(completion: @escaping ([URL]?) -> Void) {
        self.completion = completion
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        completion(urls)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completion(nil)
    }
}

private enum PendingUploadRegistry {
    static var pendingURLsByCoordinator: [ObjectIdentifier: [URL]] = [:]
    static var delegatesByCoordinator: [ObjectIdentifier: WebViewOpenPanelDelegate] = [:]
}

extension SecureChatGPTWebViewCoordinator {
    func setPendingUploadURLs(_ urls: [URL]) {
        let key = ObjectIdentifier(self)
        PendingUploadRegistry.pendingURLsByCoordinator[key] = urls
    }

    func hasPendingUploadURLs() -> Bool {
        let key = ObjectIdentifier(self)
        return !(PendingUploadRegistry.pendingURLsByCoordinator[key] ?? []).isEmpty
    }

    @available(iOS 18.4, *)
    func webView(_ webView: WKWebView,
                 runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        let key = ObjectIdentifier(self)
        let pendingURLs = PendingUploadRegistry.pendingURLsByCoordinator[key] ?? []

        if !pendingURLs.isEmpty {
            PendingUploadRegistry.pendingURLsByCoordinator[key] = []
            let urls = parameters.allowsMultipleSelection ? pendingURLs : Array(pendingURLs.prefix(1))
            completionHandler(urls)
            return
        }

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = parameters.allowsMultipleSelection

        let delegate = WebViewOpenPanelDelegate { urls in
            PendingUploadRegistry.delegatesByCoordinator[key] = nil
            completionHandler(urls)
        }

        PendingUploadRegistry.delegatesByCoordinator[key] = delegate
        picker.delegate = delegate

        guard let presenter = Self.topViewController() else {
            PendingUploadRegistry.delegatesByCoordinator[key] = nil
            completionHandler(nil)
            return
        }

        presenter.present(picker, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController

        return topViewController(from: root)
    }

    private static func topViewController(from controller: UIViewController?) -> UIViewController? {
        if let navigation = controller as? UINavigationController {
            return topViewController(from: navigation.visibleViewController)
        }

        if let tab = controller as? UITabBarController {
            return topViewController(from: tab.selectedViewController)
        }

        if let presented = controller?.presentedViewController {
            return topViewController(from: presented)
        }

        return controller
    }
}

@MainActor
extension ChatGPTWebViewStore {
    func preparePendingUploadURLs(_ urls: [URL]) {
        coordinator.setPendingUploadURLs(urls)
    }

    func startNewChatWithPendingUploadURLs(_ urls: [URL]) {
        coordinator.setPendingUploadURLs(urls)
        startNewChat()
    }

    func triggerPendingAttachmentPicker() async {
        guard coordinator.hasPendingUploadURLs() else { return }
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        guard coordinator.hasPendingUploadURLs() else { return }
        _ = await activateComposerAndOpenAttachmentPicker()
    }

    func activateComposerAndOpenAttachmentPicker() async -> Bool {
        let script = #"""
        (() => {
          const visible = (el) => {
            if (!el) return false;
            const r = el.getBoundingClientRect();
            const style = window.getComputedStyle(el);
            return r.width > 12 && r.height > 12 && style.visibility !== 'hidden' && style.display !== 'none';
          };

          const tapLikeUser = (el) => {
            if (!el) return false;
            const r = el.getBoundingClientRect();
            const x = Math.max(1, Math.floor(r.left + Math.min(Math.max(r.width - 1, 1), Math.max(18, r.width / 2))));
            const y = Math.max(1, Math.floor(r.top + Math.min(Math.max(r.height - 1, 1), Math.max(12, r.height / 2))));
            const mouse = { bubbles: true, cancelable: true, view: window, clientX: x, clientY: y };
            const pointer = { bubbles: true, cancelable: true, pointerId: 1, pointerType: 'touch', isPrimary: true, clientX: x, clientY: y };
            el.scrollIntoView({ block: 'center', inline: 'nearest' });
            try { el.dispatchEvent(new PointerEvent('pointerover', pointer)); } catch (_) {}
            try { el.dispatchEvent(new PointerEvent('pointerdown', pointer)); } catch (_) {}
            el.dispatchEvent(new MouseEvent('mouseover', mouse));
            el.dispatchEvent(new MouseEvent('mousedown', mouse));
            el.dispatchEvent(new MouseEvent('mouseup', mouse));
            try { el.dispatchEvent(new PointerEvent('pointerup', pointer)); } catch (_) {}
            el.dispatchEvent(new MouseEvent('click', mouse));
            el.focus?.({ preventScroll: true });
            return true;
          };

          const composerSelectors = [
            'textarea',
            '[contenteditable="true"]',
            '.ProseMirror',
            '[data-testid="composer"] [contenteditable="true"]',
            '[data-testid="composer"] textarea',
            'form textarea',
            'form [contenteditable="true"]'
          ];

          const findComposer = () => {
            for (const selector of composerSelectors) {
              const candidates = Array.from(document.querySelectorAll(selector)).filter(visible);
              if (candidates.length) return candidates[candidates.length - 1];
            }
            return null;
          };

          const composer = findComposer();
          const composerRect = composer?.getBoundingClientRect?.() || null;
          if (composer) {
            tapLikeUser(composer);
          } else {
            const shell = Array.from(document.querySelectorAll('form, [data-testid="composer"], main')).reverse().find(visible);
            if (shell) tapLikeUser(shell);
          }

          const labelFor = (candidate) => [
            candidate.innerText,
            candidate.textContent,
            candidate.getAttribute('aria-label'),
            candidate.getAttribute('title'),
            candidate.getAttribute('data-testid')
          ].filter(Boolean).join(' ').trim().toLowerCase();

          const attachScore = (candidate) => {
            const label = labelFor(candidate);
            let score = 0;
            if (label.includes('attach')) score += 100;
            if (label.includes('upload')) score += 100;
            if (label.includes('file')) score += 80;
            if (label.includes('add')) score += 40;
            if (label === '+' || label.includes('plus')) score += 40;
            if (!score) return -1;
            const r = candidate.getBoundingClientRect();
            if (composerRect) {
              score -= Math.min(80, Math.abs(r.top - composerRect.top) / 4);
              score -= Math.min(40, Math.abs(r.left - composerRect.left) / 8);
            }
            if (r.top > window.innerHeight * 0.55) score += 20;
            return score;
          };

          const buttons = Array.from(document.querySelectorAll('button,[role="button"],a,input[type="button"]')).filter(visible);
          const attachButton = buttons
            .map((candidate) => ({ candidate, score: attachScore(candidate) }))
            .filter((item) => item.score >= 0)
            .sort((a, b) => b.score - a.score)[0]?.candidate;

          if (attachButton) {
            tapLikeUser(attachButton);
            setTimeout(() => {
              const menuItem = Array.from(document.querySelectorAll('button,[role="button"],a,[role="menuitem"]'))
                .filter(visible)
                .find((candidate) => {
                  const label = labelFor(candidate);
                  return label.includes('upload') || label.includes('file') || label.includes('computer') || label.includes('photo');
                });
              if (menuItem) tapLikeUser(menuItem);
              setTimeout(() => document.querySelector('input[type="file"]')?.click(), 250);
            }, 250);
            return true;
          }

          const input = document.querySelector('input[type="file"]');
          if (input) {
            input.click();
            return true;
          }

          return false;
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

        return (value as? Bool) == true
    }

    func injectComposerText(_ text: String) async -> Bool {
        let encodedText: String
        if let data = try? JSONSerialization.data(withJSONObject: [text], options: []),
           let json = String(data: data, encoding: .utf8) {
            encodedText = json
        } else {
            encodedText = "[\"\"]"
        }

        try? await Task.sleep(nanoseconds: 300_000_000)

        let script = """
        (() => {
          const text = \(encodedText)[0];

          const selectors = [
            'textarea',
            '[contenteditable="true"]',
            '.ProseMirror',
            '[data-testid="composer"] [contenteditable="true"]',
            '[data-testid="composer"] textarea',
            'form textarea',
            'form [contenteditable="true"]'
          ];

          const visible = (el) => {
            if (!el) return false;
            const r = el.getBoundingClientRect();
            const style = window.getComputedStyle(el);
            return r.width > 80 && r.height > 12 && style.visibility !== 'hidden' && style.display !== 'none';
          };

          const findComposer = () => {
            for (const selector of selectors) {
              const candidates = Array.from(document.querySelectorAll(selector)).filter(visible);
              if (candidates.length) return candidates[candidates.length - 1];
            }
            return null;
          };

          const tapLikeUser = (el) => {
            const r = el.getBoundingClientRect();
            const x = Math.max(1, Math.floor(r.left + Math.min(r.width - 1, 24)));
            const y = Math.max(1, Math.floor(r.top + Math.min(r.height - 1, Math.max(12, r.height / 2))));
            const opts = { bubbles: true, cancelable: true, view: window, clientX: x, clientY: y };
            el.scrollIntoView({ block: 'center', inline: 'nearest' });
            el.dispatchEvent(new MouseEvent('mouseover', opts));
            el.dispatchEvent(new MouseEvent('mousedown', opts));
            el.dispatchEvent(new MouseEvent('mouseup', opts));
            el.dispatchEvent(new MouseEvent('click', opts));
            el.focus?.({ preventScroll: true });
          };

          const setNativeValue = (el, value) => {
            const proto = Object.getPrototypeOf(el);
            const descriptor = Object.getOwnPropertyDescriptor(proto, 'value');
            if (descriptor && descriptor.set) {
              descriptor.set.call(el, value);
            } else {
              el.value = value;
            }
          };

          const insertInto = (input) => {
            tapLikeUser(input);

            if (input.tagName === 'TEXTAREA' || input.tagName === 'INPUT') {
              setNativeValue(input, text);
              input.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: text }));
              input.dispatchEvent(new Event('change', { bubbles: true }));
              return input.value === text || input.value.length > 0;
            }

            const selection = window.getSelection();
            const range = document.createRange();
            range.selectNodeContents(input);
            range.collapse(false);
            selection.removeAllRanges();
            selection.addRange(range);

            const inserted = document.execCommand && document.execCommand('insertText', false, text);
            if (!inserted) {
              input.textContent = text;
              input.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: text }));
            }

            return (input.innerText || input.textContent || '').length > 0;
          };

          const directInput = findComposer();
          if (directInput && insertInto(directInput)) return true;

          const composerShell = Array.from(document.querySelectorAll('form, [data-testid="composer"], main'))
            .reverse()
            .find(visible);
          if (composerShell) {
            tapLikeUser(composerShell);
            const retryInput = findComposer();
            if (retryInput && insertInto(retryInput)) return true;
          }

          return false;
        })();
        """

        let value = try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any?, Error>) in
            webView.evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value)
                }
            }
        }

        return (value as? Bool) == true
    }

    func userMessageCount() async -> Int {
        let script = #"""
        (() => document.querySelectorAll('[data-message-author-role="user"]').length)();
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

        if let intValue = value as? Int { return intValue }
        if let numberValue = value as? NSNumber { return numberValue.intValue }
        return 0
    }
}
