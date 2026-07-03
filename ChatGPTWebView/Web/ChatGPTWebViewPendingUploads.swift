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
    func startNewChatWithPendingUploadURLs(_ urls: [URL]) {
        coordinator.setPendingUploadURLs(urls)
        startNewChat()
    }

    func triggerPendingAttachmentPicker() async {
        guard coordinator.hasPendingUploadURLs() else { return }
        guard #available(iOS 18.4, *) else { return }

        try? await Task.sleep(nanoseconds: 1_200_000_000)

        guard coordinator.hasPendingUploadURLs() else { return }

        let script = #"""
        (() => {
          const input = document.querySelector('input[type="file"]');
          if (input) {
            input.click();
            return 'clicked-file-input';
          }

          const buttons = Array.from(document.querySelectorAll('button,[role="button"]'));
          const button = buttons.find((candidate) => {
            const label = [candidate.innerText, candidate.getAttribute('aria-label'), candidate.getAttribute('title')]
              .filter(Boolean)
              .join(' ')
              .toLowerCase();
            return label.includes('attach') || label.includes('upload') || label.includes('file') || label.includes('add');
          });

          if (button) {
            button.click();
            setTimeout(() => document.querySelector('input[type="file"]')?.click(), 350);
            return 'clicked-attach-button';
          }

          return 'no-file-control-found';
        })();
        """#

        _ = try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any?, Error>) in
            webView.evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value)
                }
            }
        }
    }

    func injectComposerText(_ text: String) async -> Bool {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        try? await Task.sleep(nanoseconds: 300_000_000)

        let script = """
        (() => {
          const text = `\(escaped)`;
          const targets = Array.from(document.querySelectorAll('textarea, [contenteditable="true"]'));
          const input = targets.find((el) => {
            const r = el.getBoundingClientRect();
            return r.width > 100 && r.height > 20;
          });
          if (!input) return false;
          input.focus();
          if (input.tagName === 'TEXTAREA') {
            input.value = text;
            input.dispatchEvent(new Event('input', { bubbles: true }));
            input.dispatchEvent(new Event('change', { bubbles: true }));
            return true;
          }
          input.textContent = text;
          input.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: text }));
          return true;
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

    func hasStartedConversation() async -> Bool {
        let script = #"""
        (() => {
          const roleMessages = document.querySelectorAll('[data-message-author-role="user"], [data-message-author-role="assistant"]');
          if (roleMessages.length > 0) return true;
          const turns = document.querySelectorAll('article[data-testid*="conversation-turn"], [data-testid*="conversation-turn"]');
          return turns.length > 0;
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
}
