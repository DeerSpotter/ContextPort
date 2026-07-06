import Foundation
import UIKit
import WebKit

struct ChatConversationExportResult {
    let title: String
    let markdown: String
    let messageCount: Int
    let sourceURL: String
    let exportedAt: String
    let pdfData: Data
}

enum ChatConversationExportError: LocalizedError {
    case invalidPayload
    case unsupportedConversationPage
    case securityInterstitialDetected
    case noMessagesFound
    case invalidConversationStructure
    case cannotCreatePDF

    var errorDescription: String? {
        switch self {
        case .invalidPayload:
            return "The AI page did not return a readable export payload."
        case .unsupportedConversationPage:
            return "ContextPort could not verify that this is a supported AI conversation page. Open a conversation and try again."
        case .securityInterstitialDetected:
            return "ContextPort detected a security or bot-check interstitial instead of a readable conversation. Complete the check, return to the conversation, and try Save Context again."
        case .noMessagesFound:
            return "No positively identified conversation messages were found. The AI page may have changed or may not be a conversation."
        case .invalidConversationStructure:
            return "ContextPort found conversation content but could not verify both a user turn and an AI response. Nothing was saved."
        case .cannotCreatePDF:
            return "The Markdown export was created, but the PDF renderer could not create a PDF."
        }
    }
}

private struct ChatConversationExportTurn: Decodable {
    let role: String
    let content: String
}

private struct ChatConversationExportPayload: Decodable {
    let title: String
    let turns: [ChatConversationExportTurn]
    let sourceURL: String
    let exportedAt: String
    let error: String?
}

private struct ValidatedConversationTurn {
    enum Role {
        case user
        case assistant
    }

    let role: Role
    let content: String
}

@MainActor
final class ChatConversationExporter {
    static func exportConversation(from webView: WKWebView) async throws -> ChatConversationExportResult {
        try await exportConversation(
            from: webView,
            provider: AIProviderID.chatGPT.provider
        )
    }

    static func exportConversation(
        from webView: WKWebView,
        provider: AIProvider
    ) async throws -> ChatConversationExportResult {
        guard provider.isAuthenticatedContentURL(webView.url) else {
            throw ChatConversationExportError.unsupportedConversationPage
        }

        let raw = try await evaluateJavaScript(
            extractionJavaScript(provider: provider),
            in: webView
        )
        guard let json = raw as? String,
              let data = json.data(using: .utf8) else {
            throw ChatConversationExportError.invalidPayload
        }

        let payload = try JSONDecoder().decode(ChatConversationExportPayload.self, from: data)
        if payload.error == "security-interstitial" {
            throw ChatConversationExportError.securityInterstitialDetected
        }

        let turns = payload.turns.compactMap(validateTurn)
        guard !turns.isEmpty else {
            throw ChatConversationExportError.noMessagesFound
        }

        guard turns.contains(where: { $0.role == .user }),
              turns.contains(where: { $0.role == .assistant }) else {
            throw ChatConversationExportError.invalidConversationStructure
        }

        let title = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let exportedAt = payload.exportedAt.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceURL = payload.sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let markdown = makeMarkdown(
            title: title.isEmpty ? "\(provider.displayName) Conversation" : title,
            turns: turns,
            sourceURL: sourceURL,
            exportedAt: exportedAt,
            provider: provider
        )

        let messageCount = turns.count
        let pdfData = try makePDFData(
            title: title,
            markdown: markdown,
            sourceURL: sourceURL,
            exportedAt: exportedAt,
            messageCount: messageCount
        )
        return ChatConversationExportResult(
            title: title.isEmpty ? "\(provider.displayName) Conversation" : title,
            markdown: markdown,
            messageCount: messageCount,
            sourceURL: sourceURL,
            exportedAt: exportedAt,
            pdfData: pdfData
        )
    }

    private static func validateTurn(_ turn: ChatConversationExportTurn) -> ValidatedConversationTurn? {
        let role: ValidatedConversationTurn.Role
        switch turn.role.lowercased() {
        case "user": role = .user
        case "assistant": role = .assistant
        default: return nil
        }

        let content = turn.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard content.count >= 5, !containsSecurityInterstitialMarker(content) else {
            return nil
        }
        return ValidatedConversationTurn(role: role, content: content)
    }

    private static func containsSecurityInterstitialMarker(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.contains("__cf$cv$params")
            || lower.contains("/cdn-cgi/challenge-platform/")
            || lower.contains("cf-turnstile")
            || lower.contains("challenge-platform/scripts")
    }

    private static func makeMarkdown(
        title: String,
        turns: [ValidatedConversationTurn],
        sourceURL: String,
        exportedAt: String,
        provider: AIProvider
    ) -> String {
        var lines = [
            "# \(title)",
            "",
            "**Exported:** \(exportedAt)",
            "**Source:** \(sourceURL)",
            "**Messages:** \(turns.count)",
            "",
            "---",
            ""
        ]

        for turn in turns {
            let sender = turn.role == .user ? "You" : provider.displayName
            lines.append("### **\(sender)**")
            lines.append("")
            lines.append(turn.content)
            lines.append("")
            lines.append("---")
            lines.append("")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static func evaluateJavaScript(_ script: String, in webView: WKWebView) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: ChatConversationExportError.invalidPayload)
                }
            }
        }
    }

    private static func makePDFData(
        title: String,
        markdown: String,
        sourceURL: String,
        exportedAt: String,
        messageCount: Int
    ) throws -> Data {
        let html = """
        <!doctype html><html><head><meta charset=\"utf-8\"><style>
        body{font-family:-apple-system,BlinkMacSystemFont,Helvetica,Arial,sans-serif;font-size:12px;line-height:1.45;color:#111}h1{font-size:22px;margin-bottom:6px}.meta{color:#555;font-size:10px;margin-bottom:18px;word-break:break-word}pre{white-space:pre-wrap;word-break:break-word;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:10px}
        </style></head><body><h1>\(escapeHTML(title))</h1><div class=\"meta\">Exported: \(escapeHTML(exportedAt))<br>Messages: \(messageCount)<br>Source: \(escapeHTML(sourceURL))</div><pre>\(escapeHTML(markdown))</pre></body></html>
        """
        let formatter = UIMarkupTextPrintFormatter(markupText: html)
        formatter.perPageContentInsets = UIEdgeInsets(top: 36, left: 36, bottom: 36, right: 36)
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        renderer.setValue(pageRect, forKey: "paperRect")
        renderer.setValue(pageRect.insetBy(dx: 36, dy: 36), forKey: "printableRect")
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: 0))
        guard renderer.numberOfPages > 0 else {
            throw ChatConversationExportError.cannotCreatePDF
        }

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, .zero, nil)
        for page in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: page, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func extractionJavaScript(provider: AIProvider) -> String {
        let providerIDs = javascriptArray([provider.id.rawValue])
        let providerNames = javascriptArray([provider.displayName])
        let providerURLs = javascriptArray([provider.startURL.absoluteString])

        return #"""
        (() => {
          const providerID = \#(providerIDs)[0];
          const providerName = \#(providerNames)[0];
          const providerStartURL = \#(providerURLs)[0];
          const normalize = v => String(v || '').replace(/\u00a0/g,' ').replace(/\r\n?/g,'\n').replace(/[ \t]+\n/g,'\n').replace(/\n[ \t]+/g,'\n').replace(/\n{3,}/g,'\n\n').trim();
          const all = (root, selector) => { try { return Array.from(root.querySelectorAll(selector)); } catch { return []; } };
          const text = el => normalize(el ? (el.innerText || el.textContent || '') : '');
          const topLevel = items => items.filter((item, index) => !items.some((other, otherIndex) => otherIndex !== index && other.contains(item)));
          const interstitialMarkers = [/__CF\$cv\$params/i,/\/cdn-cgi\/challenge-platform\//i,/cf-turnstile/i,/challenge-platform\/scripts/i];
          const isInterstitial = value => interstitialMarkers.some(pattern => pattern.test(String(value || '')));
          const title = (() => {
            for (const selector of ['h1:not([class*=hidden])','[data-testid*=conversation-title]','[class*=conversation-title]','[aria-label*=conversation][aria-label*=title]']) {
              const value = normalize(document.querySelector(selector)?.textContent || '');
              if (value && ![providerName.toLowerCase(),'new chat','untitled','chat'].includes(value.toLowerCase())) return value;
            }
            let doc = normalize(document.title || '');
            const lower = doc.toLowerCase();
            const providerLower = providerName.toLowerCase();
            for (const separator of [' - ', ' | ']) {
              const suffix = separator + providerLower;
              if (lower.endsWith(suffix)) {
                doc = doc.slice(0, doc.length - suffix.length).trim();
                break;
              }
            }
            return doc && ![providerLower,'new chat','untitled','chat'].includes(doc.toLowerCase())
              ? doc
              : `${providerName} Conversation`;
          })();
          const fenceFor = code => '`'.repeat(((String(code).match(/`{3,}/g) || []).reduce((m, r) => Math.max(m, r.length), 2)) + 1);
          const tableMD = table => {
            const rows = Array.from(table.querySelectorAll('tr')).map(row => Array.from(row.children).filter(cell => ['TH','TD'].includes(cell.tagName)).map(cell => normalize(cell.innerText || cell.textContent || '').replace(/\|/g,'\\|') || ' ')).filter(row => row.length);
            if (!rows.length) return text(table);
            const width = Math.max(...rows.map(row => row.length));
            const filled = rows.map(row => row.concat(Array(Math.max(0, width - row.length)).fill(' ')));
            return [`| ${filled[0].join(' | ')} |`,`| ${filled[0].map(() => '---').join(' | ')} |`,...filled.slice(1).map(row => `| ${row.join(' | ')} |`)].join('\n');
          };
          const serialize = root => {
            const clone = root.cloneNode(true);
            all(clone, 'button,svg,style,script,textarea,input,[contenteditable=true],[aria-label*=Copy],[aria-label*=More],[data-testid*=copy],[class*=sr-only],[class*=visually-hidden]').forEach(node => node.remove());
            topLevel(all(clone, 'pre,code-block,[data-testid*=code-block]')).forEach(block => { const code = (block.querySelector?.('code')?.innerText || block.innerText || block.textContent || '').replace(/\u00a0/g,' ').trimEnd(); const fence = fenceFor(code); block.replaceWith(document.createTextNode(`\n\n${fence}\n${code}\n${fence}\n\n`)); });
            topLevel(all(clone, 'table')).forEach(table => table.replaceWith(document.createTextNode(`\n\n${tableMD(table)}\n\n`)));
            all(clone, 'a[href]').forEach(link => { const href = String(link.href || link.getAttribute('href') || '').trim(); if (!href || /^(javascript|data|vbscript):/i.test(href)) return; const label = normalize(link.innerText || link.textContent || href).replace(/[\[\]]/g,''); link.replaceWith(document.createTextNode(`[${label}](${href.replace(/\)/g,'%29')})`)); });
            all(clone, 'img,canvas,video,audio').forEach(media => media.replaceWith(document.createTextNode(`[${media.tagName.toLowerCase()}]`)));
            return text(clone);
          };
          const pushTurn = (turns, seen, role, content) => {
            const value = normalize(content);
            if (!['user','assistant'].includes(role) || value.length < 5 || value.length >= 300000 || isInterstitial(value)) return;
            const key = `${role}:${value.slice(0,220)}`;
            if (seen.has(key)) return;
            seen.add(key);
            turns.push({ role, content: value });
          };
          const extractChatGPT = () => {
            const turns = [], seen = new Set();
            topLevel(all(document, '[data-message-author-role]')).forEach(node => {
              const role = String(node.getAttribute('data-message-author-role') || '').toLowerCase();
              pushTurn(turns, seen, role, serialize(node));
            });
            return turns;
          };
          const extractClaude = () => {
            const turns = [], seen = new Set();
            const assistantHeadingSelector = 'h1[data-find-omitted],h2[data-find-omitted],h3[data-find-omitted]';
            const assistantBodySelector = '.font-claude-response-body,.progressive-markdown,.standard-markdown';
            const rows = topLevel(all(document, '[data-test-render-count]'));

            rows.forEach(row => {
              const user = row.querySelector('[data-testid="user-message"]');
              if (user) {
                pushTurn(turns, seen, 'user', serialize(user));
                return;
              }

              const responseHeading = all(row, assistantHeadingSelector).some(heading => /^Claude responded:/i.test(text(heading)));
              const responseBlocks = topLevel(all(row, assistantBodySelector)).filter(block => !block.closest('[data-testid="user-message"]'));
              if (responseHeading || responseBlocks.length > 0) {
                const content = responseBlocks.length > 0
                  ? responseBlocks.map(serialize).filter(Boolean).join('\n\n')
                  : serialize(row);
                pushTurn(turns, seen, 'assistant', content);
              }
            });

            if (turns.length > 0) return turns;

            const candidates = [];
            topLevel(all(document, '[data-testid="user-message"]')).forEach(node => {
              candidates.push({ node, role: 'user', content: serialize(node) });
            });
            all(document, assistantHeadingSelector)
              .filter(heading => /^Claude responded:/i.test(text(heading)))
              .forEach(heading => {
                const root = heading.parentElement || heading;
                const responseBlocks = topLevel(all(root, assistantBodySelector));
                candidates.push({
                  node: root,
                  role: 'assistant',
                  content: responseBlocks.length > 0
                    ? responseBlocks.map(serialize).filter(Boolean).join('\n\n')
                    : serialize(root)
                });
              });
            candidates.sort((left, right) => {
              if (left.node === right.node) return 0;
              return left.node.compareDocumentPosition(right.node) & Node.DOCUMENT_POSITION_FOLLOWING ? -1 : 1;
            });
            candidates.forEach(candidate => pushTurn(turns, seen, candidate.role, candidate.content));
            return turns;
          };
          const extractGrok = () => {
            const turns = [], seen = new Set();
            topLevel(all(document, '[data-testid="user-message"],[data-testid="assistant-message"]')).forEach(node => {
              const testID = String(node.getAttribute('data-testid') || '').toLowerCase();
              const role = testID === 'user-message' ? 'user' : testID === 'assistant-message' ? 'assistant' : '';
              pushTurn(turns, seen, role, serialize(node));
            });
            return turns;
          };
          const extractGemini = () => {
            const turns = [], seen = new Set();
            const selectors = 'user-query,model-response,[data-message-author-role],[data-test-id="user-query"],[data-test-id="model-response"],[data-testid="user-query"],[data-testid="model-response"]';
            topLevel(all(document, selectors)).forEach(node => {
              const explicitRole = String(node.getAttribute('data-message-author-role') || '').toLowerCase();
              const identity = [node.tagName,node.getAttribute('data-test-id'),node.getAttribute('data-testid')].filter(Boolean).join(' ').toLowerCase();
              const role = explicitRole === 'user' || /user-query/.test(identity)
                ? 'user'
                : explicitRole === 'assistant' || /model-response/.test(identity)
                  ? 'assistant'
                  : '';
              pushTurn(turns, seen, role, serialize(node));
            });
            return turns;
          };
          const extractor = {
            chatgpt: extractChatGPT,
            claude: extractClaude,
            gemini: extractGemini,
            grok: extractGrok
          }[providerID];
          const turns = extractor ? extractor() : [];
          const exportedAt = new Date().toISOString();
          const source = window.location.href || providerStartURL;
          const pageHasInterstitial = isInterstitial(document.documentElement?.innerHTML || '') || isInterstitial(text(document.body));
          const error = turns.length === 0 && pageHasInterstitial ? 'security-interstitial' : null;
          return JSON.stringify({ title, turns, sourceURL: source, exportedAt, error });
        })();
        """#
    }

    private static func javascriptArray(_ values: [String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: values, options: []),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }
}

typealias ChatGPTConversationExporter = ChatConversationExporter

@MainActor
extension ChatGPTWebViewStore {
    func exportCurrentConversation() async throws -> ChatConversationExportResult {
        try await ChatConversationExporter.exportConversation(from: webView, provider: provider)
    }
}
