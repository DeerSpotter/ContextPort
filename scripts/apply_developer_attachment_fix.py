from pathlib import Path

path = Path("ChatGPTWebView/Web/ChatGPTWebViewPendingUploads.swift")
text = path.read_text()
start_marker = "    func injectFilesIntoChatGPTUpload(_ urls: [URL]) async -> Bool {\n"
end_marker = "    private func waitForStableComposerReady() async -> Bool {\n"
start = text.index(start_marker)
end = text.index(end_marker, start)

replacement = r'''    func injectFilesIntoChatGPTUpload(_ urls: [URL]) async -> Bool {
        struct FileDescriptor {
            let id: String
            let name: String
            let mime: String
        }

        let uploadChunkSize = 384 * 1024
        let existingURLs = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existingURLs.isEmpty else { return false }

        func evaluateBool(_ script: String) async -> Bool {
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

        func jsonObject(_ object: [String: String]) -> String? {
            guard JSONSerialization.isValidJSONObject(object),
                  let data = try? JSONSerialization.data(withJSONObject: object, options: []),
                  let json = String(data: data, encoding: .utf8) else {
                return nil
            }
            return json
        }

        func cleanupUploadBridge() async {
            _ = await evaluateBool(
                "(() => { try { delete window.__contextPortUploadBridge; } catch (_) {} return true; })();"
            )
        }

        let initialized = await evaluateBool(#"""
        (() => {
          try { delete window.__contextPortUploadBridge; } catch (_) {}
          window.__contextPortUploadBridge = { files: [] };
          return true;
        })();
        """#)
        guard initialized else { return false }

        for url in existingURLs {
            let descriptor = FileDescriptor(
                id: UUID().uuidString,
                name: url.lastPathComponent,
                mime: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            )

            guard let descriptorJSON = jsonObject([
                "id": descriptor.id,
                "name": descriptor.name,
                "mime": descriptor.mime
            ]) else {
                await cleanupUploadBridge()
                return false
            }

            let registered = await evaluateBool("""
            (() => {
              const bridge = window.__contextPortUploadBridge;
              if (!bridge || !Array.isArray(bridge.files)) return false;
              const descriptor = \(descriptorJSON);
              bridge.files.push({ ...descriptor, parts: [] });
              return true;
            })();
            """)
            guard registered else {
                await cleanupUploadBridge()
                return false
            }

            guard let handle = try? FileHandle(forReadingFrom: url) else {
                await cleanupUploadBridge()
                return false
            }

            var fileReadSucceeded = true
            do {
                while let chunk = try handle.read(upToCount: uploadChunkSize), !chunk.isEmpty {
                    let base64 = chunk.base64EncodedString()
                    let staged = await evaluateBool("""
                    (() => {
                      const bridge = window.__contextPortUploadBridge;
                      const file = bridge?.files?.find((candidate) => candidate.id === '\(descriptor.id)');
                      if (!file) return false;
                      const binary = atob('\(base64)');
                      const bytes = new Uint8Array(binary.length);
                      for (let index = 0; index < binary.length; index++) {
                        bytes[index] = binary.charCodeAt(index);
                      }
                      file.parts.push(bytes);
                      return true;
                    })();
                    """)
                    if !staged {
                        fileReadSucceeded = false
                        break
                    }
                }
            } catch {
                fileReadSucceeded = false
            }
            try? handle.close()

            guard fileReadSucceeded else {
                await cleanupUploadBridge()
                return false
            }
        }

        let attachScript = #"""
        (async () => {
          const bridge = window.__contextPortUploadBridge;
          if (!bridge || !Array.isArray(bridge.files) || bridge.files.length === 0) return false;

          const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

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

          const findComposer = () => {
            const selectors = [
              'textarea',
              '[contenteditable="true"]',
              '.ProseMirror',
              '[data-testid="composer"] [contenteditable="true"]',
              '[data-testid="composer"] textarea',
              'form textarea',
              'form [contenteditable="true"]'
            ];
            for (const selector of selectors) {
              const candidates = Array.from(document.querySelectorAll(selector)).filter(visible);
              if (candidates.length) return candidates[candidates.length - 1];
            }
            return null;
          };

          const closeTransientMenus = () => {
            const escDown = new KeyboardEvent('keydown', { key: 'Escape', code: 'Escape', keyCode: 27, which: 27, bubbles: true, cancelable: true });
            const escUp = new KeyboardEvent('keyup', { key: 'Escape', code: 'Escape', keyCode: 27, which: 27, bubbles: true, cancelable: true });
            document.dispatchEvent(escDown);
            window.dispatchEvent(escDown);
            document.body?.dispatchEvent(escDown);
            document.dispatchEvent(escUp);
            window.dispatchEvent(escUp);
            document.body?.dispatchEvent(escUp);

            const composer = findComposer();
            if (composer) {
              tapLikeUser(composer);
            } else {
              document.body?.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window, clientX: 8, clientY: 8 }));
            }
          };

          const files = bridge.files.map((record) => new File(
            record.parts,
            record.name,
            { type: record.mime || 'application/octet-stream' }
          ));

          let transfer = null;
          try { transfer = new DataTransfer(); } catch (_) {}
          if (!transfer) {
            try { transfer = new ClipboardEvent('paste').clipboardData; } catch (_) {}
          }
          if (!transfer) return false;
          for (const file of files) transfer.items.add(file);
          if (!transfer.files || transfer.files.length === 0) return false;

          const attachmentVisible = () => {
            const attachmentHints = Array.from(document.querySelectorAll('[data-testid], [aria-label], a, button, div, span'))
              .map((el) => [el.innerText, el.textContent, el.getAttribute('aria-label'), el.getAttribute('data-testid')].filter(Boolean).join(' '))
              .join(' ')
              .toLowerCase();
            return bridge.files.some((record) => attachmentHints.includes(record.name.toLowerCase()));
          };

          const composer = findComposer();
          if (composer) tapLikeUser(composer);
          await wait(200);

          const input = Array.from(document.querySelectorAll('input[type="file"]')).reverse()[0];
          if (input) {
            try {
              input.files = transfer.files;
              input.dispatchEvent(new Event('input', { bubbles: true }));
              input.dispatchEvent(new Event('change', { bubbles: true }));
              for (let attempt = 0; attempt < 12; attempt++) {
                await wait(250);
                if (attachmentVisible()) {
                  closeTransientMenus();
                  await wait(250);
                  return true;
                }
              }
            } catch (_) {}
          }

          const dropTargets = [
            composer,
            document.querySelector('form'),
            document.querySelector('[data-testid="composer"]'),
            document.querySelector('main'),
            document.body
          ].filter(Boolean);

          for (const target of dropTargets) {
            try {
              target.dispatchEvent(new ClipboardEvent('paste', { bubbles: true, cancelable: true, clipboardData: transfer }));
            } catch (_) {}
            try {
              target.dispatchEvent(new DragEvent('dragenter', { bubbles: true, cancelable: true, dataTransfer: transfer }));
              target.dispatchEvent(new DragEvent('dragover', { bubbles: true, cancelable: true, dataTransfer: transfer }));
              target.dispatchEvent(new DragEvent('drop', { bubbles: true, cancelable: true, dataTransfer: transfer }));
            } catch (_) {}

            for (let attempt = 0; attempt < 8; attempt++) {
              await wait(250);
              if (attachmentVisible()) {
                closeTransientMenus();
                await wait(250);
                return true;
              }
            }
          }

          return false;
        })();
        """#

        let attached = await evaluateBool(attachScript)
        await cleanupUploadBridge()
        return attached
    }

'''

path.write_text(text[:start] + replacement + text[end:])
