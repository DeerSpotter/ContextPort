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
    case noMessagesFound
    case cannotCreatePDF

    var errorDescription: String? {
        switch self {
        case .invalidPayload: return "The AI page did not return a readable export payload."
        case .noMessagesFound: return "No conversation messages were found. Open a conversation and try again."
        case .cannotCreatePDF: return "The Markdown export was created, but the PDF renderer could not create a PDF."
        }
    }
}

private struct ChatConversationExportPayload: Decodable {
    let title: String
    let markdown: String
    let messageCount: Int
    let sourceURL: String
    let exportedAt: String
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
        let raw = try await evaluateJavaScript(
            extractionJavaScript(provider: provider),
            in: webView
        )
        guard let json = raw as? String,
              let data = json.data(using: .utf8) else {
            throw ChatConversationExportError.invalidPayload
        }

        let payload = try JSONDecoder().decode(ChatConversationExportPayload.self, from: data)
        let markdown = payload.markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard payload.messageCount > 0, !markdown.isEmpty else {
            throw ChatConversationExportError.noMessagesFound
        }

        let pdfData = try makePDFData(
            title: payload.title,
            markdown: markdown,
            sourceURL: payload.sourceURL,
            exportedAt: payload.exportedAt,
            messageCount: payload.messageCount
        )
        return ChatConversationExportResult(
            title: payload.title,
            markdown: markdown,
            messageCount: payload.messageCount,
            sourceURL: payload.sourceURL,
            exportedAt: payload.exportedAt,
            pdfData: pdfData
        )
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
        let providerNames = javascriptArray([provider.displayName])
        let providerURLs = javascriptArray([provider.startURL.absoluteString])

        return #"""
        (() => {
          const providerName = \#(providerNames)[0];
          const providerStartURL = \#(providerURLs)[0];
          const normalize = v => String(v || '').replace(/\u00a0/g,' ').replace(/\r\n?/g,'\n').replace(/[ \t]+\n/g,'\n').replace(/\n[ \t]+/g,'\n').replace(/\n{3,}/g,'\n\n').trim();
          const all = (root, selector) => { try { return Array.from(root.querySelectorAll(selector)); } catch { return []; } };
          const text = el => normalize(el ? (el.innerText || el.textContent || '') : '');
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
          const topLevel = items => items.filter((item, index) => !items.some((other, otherIndex) => otherIndex !== index && other.contains(item)));
          const valid = el => el && !el.matches?.('nav,aside,header,footer,form,menu') && (text(el).length >= 5 || all(el,'pre,code-block,table,img,canvas,video,audio').length > 0) && text(el).length < 300000;
          const findMessages = () => {
            for (const selector of ['[data-message-author-role]','article[data-testid*=conversation-turn]','div[data-testid*=conversation-turn]','.group\\/conversation-turn','[data-message-id]','main article','main [data-testid*=message]','main [class*=message]','main [role=listitem]']) {
              const found = topLevel(all(document, selector)).filter(valid);
              if (found.length > 0) return found;
            }
            const main = document.querySelector('main,[role=main],[class*=conversation],[class*=chat]') || document.body;
            return topLevel(Array.from(main.children || [])).filter(valid);
          };
          const roleFor = (node, index) => {
            const roleNode = node.matches?.('[data-message-author-role]') ? node : node.querySelector?.('[data-message-author-role]');
            const role = String(roleNode?.getAttribute('data-message-author-role') || '').toLowerCase();
            if (role === 'user') return 'You';
            if (role === 'assistant') return providerName;
            const labels = normalize([
              node.getAttribute?.('aria-label'),
              node.getAttribute?.('data-testid'),
              node.getAttribute?.('class')
            ].filter(Boolean).join(' ')).toLowerCase();
            if (/user|human|prompt/.test(labels)) return 'You';
            if (/assistant|response|answer|model/.test(labels)) return providerName;
            return index % 2 === 0 ? 'You' : providerName;
          };
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
            all(clone, 'button,svg,style,script,textarea,input,[contenteditable=true],[aria-label*=Copy],[aria-label*=More],[data-testid*=copy]').forEach(node => node.remove());
            topLevel(all(clone, 'pre,code-block,[data-testid*=code-block]')).forEach(block => { const code = (block.querySelector?.('code')?.innerText || block.innerText || block.textContent || '').replace(/\u00a0/g,' ').trimEnd(); const fence = fenceFor(code); block.replaceWith(document.createTextNode(`\n\n${fence}\n${code}\n${fence}\n\n`)); });
            topLevel(all(clone, 'table')).forEach(table => table.replaceWith(document.createTextNode(`\n\n${tableMD(table)}\n\n`)));
            all(clone, 'a[href]').forEach(link => { const href = String(link.href || link.getAttribute('href') || '').trim(); if (!href || /^(javascript|data|vbscript):/i.test(href)) return; const label = normalize(link.innerText || link.textContent || href).replace(/[\[\]]/g,''); link.replaceWith(document.createTextNode(`[${label}](${href.replace(/\)/g,'%29')})`)); });
            all(clone, 'img,canvas,video,audio').forEach(media => media.replaceWith(document.createTextNode(`[${media.tagName.toLowerCase()}]`)));
            return text(clone);
          };
          const seen = new Set();
          const messages = [];
          findMessages().forEach((node, index) => {
            const contentRoot = node.matches?.('[data-message-author-role]') ? node : (node.querySelector?.('[data-message-author-role]') || node);
            const content = serialize(contentRoot);
            if (!content || content.length < 5) return;
            const sender = roleFor(node, index);
            const key = `${sender}:${content.slice(0,220)}`;
            if (seen.has(key)) return;
            seen.add(key); messages.push({ sender, content });
          });
          const exportedAt = new Date().toISOString();
          const body = messages.flatMap(m => [`### **${m.sender}**`,'',m.content,'','---','']);
          const source = window.location.href || providerStartURL;
          const header = [`# ${title}`,'',`**Exported:** ${exportedAt}`,`**Source:** ${source}`,`**Messages:** ${messages.length}`,'','---',''];
          return JSON.stringify({ title, markdown: header.concat(body).join('\n').trim() + '\n', messageCount: messages.length, sourceURL: source, exportedAt });
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
