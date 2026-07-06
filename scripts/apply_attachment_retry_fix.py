from pathlib import Path

pending_path = Path("ChatGPTWebView/Web/ChatGPTWebViewPendingUploads.swift")
pending = pending_path.read_text()
old_visibility = "return bridge.files.some((record) => attachmentHints.includes(record.name.toLowerCase()));"
new_visibility = "return bridge.files.every((record) => attachmentHints.includes(record.name.toLowerCase()));"
if old_visibility not in pending:
    raise SystemExit("attachment visibility expression not found")
pending_path.write_text(pending.replace(old_visibility, new_visibility, 1))

tab_path = Path("ChatGPTWebView/Web/ChatGPTTabView.swift")
tab = tab_path.read_text()
old_block = '''            let memoryAttachWorked = await webViewStore.injectFilesIntoChatGPTUpload(urls)

            pendingAttachFileURLs = []
            webViewStore.preparePendingUploadURLs([])

            if memoryAttachWorked {
                appModel.statusMessage = "Context bundle handoff completed for \\(provider.displayName). Review the attached context before sending."
            } else {
                appModel.statusMessage = "Context bundle attach was attempted in \\(provider.displayName). Save Context is available again. Return to Memory to retry the bundle if needed."
            }
'''
new_block = '''            let memoryAttachWorked = await webViewStore.injectFilesIntoChatGPTUpload(urls)

            if memoryAttachWorked {
                pendingAttachFileURLs = []
                webViewStore.preparePendingUploadURLs([])
                appModel.statusMessage = "Context bundle handoff completed for \\(provider.displayName). Review the attached context before sending."
            } else {
                pendingAttachFileURLs = urls
                webViewStore.preparePendingUploadURLs(urls)
                appModel.statusMessage = "Context bundle could not be attached in \\(provider.displayName). The files are still ready; tap Attach Files to retry."
            }
'''
if old_block not in tab:
    raise SystemExit("attach retry block not found")
tab_path.write_text(tab.replace(old_block, new_block, 1))
