from pathlib import Path

upload_path = Path("ChatGPTWebView/Web/ChatGPTWebViewPendingUploads.swift")
project_path = Path("project.yml")

old = """          const attachmentVisible = () => {
            const attachmentHints = Array.from(document.querySelectorAll('[data-testid], [aria-label], a, button, div, span'))
              .map((el) => [el.innerText, el.textContent, el.getAttribute('aria-label'), el.getAttribute('data-testid')].filter(Boolean).join(' '))
              .join(' ')
              .toLowerCase();
            return bridge.files.every((record) => attachmentHints.includes(record.name.toLowerCase()));
          };

          const composer = findComposer();
          if (composer) tapLikeUser(composer);
          await wait(200);

          const input = Array.from(document.querySelectorAll('input[type=\"file\"]')).reverse()[0];
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
"""

new = """          const attachmentVisible = () => {
            const attachmentHints = Array.from(document.querySelectorAll('[data-testid], [aria-label], [data-filename], [title], [alt], a, button, div, span'))
              .map((el) => [
                el.innerText,
                el.textContent,
                el.getAttribute('aria-label'),
                el.getAttribute('data-testid'),
                el.getAttribute('data-filename'),
                el.getAttribute('title'),
                el.getAttribute('alt'),
                el.getAttribute('name'),
                el.getAttribute('value')
              ].filter(Boolean).join(' '))
              .join(' ')
              .toLowerCase();
            const attachmentHTML = String(document.documentElement?.innerHTML || '').toLowerCase();
            return bridge.files.every((record) => {
              const name = record.name.toLowerCase();
              return attachmentHints.includes(name) || attachmentHTML.includes(name);
            });
          };

          const fileListMatches = (fileList) => {
            const actualFiles = Array.from(fileList || []);
            if (actualFiles.length !== files.length) return false;
            return files.every((file, index) => {
              const actual = actualFiles[index];
              return actual
                && actual.name === file.name
                && actual.size === file.size
                && String(actual.type || '') === String(file.type || '');
            });
          };

          const composer = findComposer();
          if (composer) tapLikeUser(composer);
          await wait(200);

          const input = Array.from(document.querySelectorAll('input[type=\"file\"]')).reverse()[0];
          if (input) {
            try {
              input.files = transfer.files;
              const browserAcceptedExactFiles = fileListMatches(input.files)
                && (files.length === 1 || input.multiple);
              input.dispatchEvent(new Event('input', { bubbles: true }));
              input.dispatchEvent(new Event('change', { bubbles: true }));

              if (browserAcceptedExactFiles) {
                closeTransientMenus();
                await wait(250);
                return true;
              }

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
"""

text = upload_path.read_text(encoding="utf-8")
if text.count(old) != 1:
    raise SystemExit(f"Expected one upload verifier block, found {text.count(old)}")
text = text.replace(old, new, 1)

required = [
    "browserAcceptedExactFiles",
    "fileListMatches(input.files)",
    "el.getAttribute('data-filename')",
    "el.getAttribute('title')",
    "attachmentHTML.includes(name)",
]
for marker in required:
    if marker not in text:
        raise SystemExit(f"Missing required patch marker: {marker}")

upload_path.write_text(text, encoding="utf-8")

project = project_path.read_text(encoding="utf-8")
old_build = 'CURRENT_PROJECT_VERSION: "65"'
new_build = 'CURRENT_PROJECT_VERSION: "66"'
if project.count(old_build) != 1:
    raise SystemExit(f"Expected one build 65 marker, found {project.count(old_build)}")
project_path.write_text(project.replace(old_build, new_build, 1), encoding="utf-8")

print("Patched exact browser FileList handoff verification and bumped build 66.")
