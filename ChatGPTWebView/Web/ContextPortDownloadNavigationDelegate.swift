import Foundation
import UIKit
import WebKit

@MainActor
final class ContextPortDownloadNavigationDelegate: NSObject, WKNavigationDelegate, WKDownloadDelegate {
    weak var forwardingDelegate: WKNavigationDelegate?

    private var downloadDestinations: [ObjectIdentifier: URL] = [:]

    init(forwardingDelegate: WKNavigationDelegate) {
        self.forwardingDelegate = forwardingDelegate
        super.init()
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector)
            || (forwardingDelegate?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if forwardingDelegate?.responds(to: aSelector) == true {
            return forwardingDelegate
        }
        return super.forwardingTarget(for: aSelector)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if Self.isPowerPointURL(navigationAction.request.url) {
            decisionHandler(.download)
            return
        }

        if let forwardingDelegate,
           forwardingDelegate.responds(
            to: #selector(WKNavigationDelegate.webView(_:decidePolicyFor:decisionHandler:))
           ) {
            forwardingDelegate.webView?(
                webView,
                decidePolicyFor: navigationAction,
                decisionHandler: decisionHandler
            )
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        let response = navigationResponse.response
        if Self.isPowerPointURL(response.url)
            || Self.isPowerPointMIMEType(response.mimeType) {
            decisionHandler(.download)
            return
        }

        if let forwardingDelegate,
           forwardingDelegate.responds(
            to: #selector(WKNavigationDelegate.webView(_:decidePolicyFor:decisionHandler:) as (WKNavigationDelegate) -> (WKWebView, WKNavigationResponse, @escaping (WKNavigationResponsePolicy) -> Void) -> Void)
           ) {
            forwardingDelegate.webView?(
                webView,
                decidePolicyFor: navigationResponse,
                decisionHandler: decisionHandler
            )
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        download.delegate = self
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        download.delegate = self
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        let filename = Self.safeFilename(suggestedFilename, response: response)
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)

        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            downloadDestinations[ObjectIdentifier(download)] = destination
            completionHandler(destination)
        } catch {
            completionHandler(nil)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let destination = downloadDestinations.removeValue(
            forKey: ObjectIdentifier(download)
        ) else {
            return
        }

        presentExporter(for: destination)
    }

    func download(
        _ download: WKDownload,
        didFailWithError error: Error,
        resumeData: Data?
    ) {
        downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
    }

    private func presentExporter(for fileURL: URL) {
        guard let presenter = Self.topViewController() else { return }

        let picker = UIDocumentPickerViewController(
            forExporting: [fileURL],
            asCopy: true
        )
        presenter.present(picker, animated: true)
    }

    private static func isPowerPointURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        let extensionName = url.pathExtension.lowercased()
        if extensionName == "ppt" || extensionName == "pptx" || extensionName == "pps" || extensionName == "ppsx" {
            return true
        }

        let decoded = url.absoluteString.removingPercentEncoding?.lowercased() ?? url.absoluteString.lowercased()
        return decoded.contains(".pptx")
            || decoded.contains(".ppt")
            || decoded.contains(".ppsx")
            || decoded.contains(".pps")
    }

    private static func isPowerPointMIMEType(_ mimeType: String?) -> Bool {
        guard let mimeType = mimeType?.lowercased() else { return false }
        return mimeType.contains("presentationml")
            || mimeType.contains("ms-powerpoint")
            || mimeType == "application/vnd.ms-powerpoint"
    }

    private static func safeFilename(
        _ suggestedFilename: String,
        response: URLResponse
    ) -> String {
        let fallbackExtension = response.mimeType?.contains("presentationml") == true ? "pptx" : "ppt"
        let rawName = suggestedFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = rawName.isEmpty ? "ContextPort Download.\(fallbackExtension)" : rawName
        let sanitized = baseName.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")

        if sanitized.contains(".") {
            return sanitized
        }
        return "\(sanitized).\(fallbackExtension)"
    }

    private static func topViewController(
        from root: UIViewController? = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    ) -> UIViewController? {
        if let navigation = root as? UINavigationController {
            return topViewController(from: navigation.visibleViewController)
        }
        if let tab = root as? UITabBarController {
            return topViewController(from: tab.selectedViewController)
        }
        if let presented = root?.presentedViewController {
            return topViewController(from: presented)
        }
        return root
    }
}
