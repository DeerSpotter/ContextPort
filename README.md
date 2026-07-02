# ChatGPT WebView for iOS 16

A lightweight iOS WebView wrapper for ChatGPT’s web app. Built with Swift and WKWebView, optimized for fast performance and speech-to-text microphone support on iOS 16.

## Current trust position

This fork is being converted into a trusted, source controlled build path. The upstream release IPA should not be treated as trusted unless that exact IPA is separately inspected.

## Current app direction

The app is now focused on two tabs:

- `ChatGPT`
- `Memory`

The `Save Context` button in the ChatGPT tab extracts the current ChatGPT conversation from the rendered page, creates both Markdown and PDF, and stores both inside the app Memory vault under the chat title.

The Memory tab is intentionally simple. It shows saved chat names only. Tap a name to open the saved chat memory, view the PDF, view the Markdown, or start a new chat from that saved memory. Swipe left on a saved chat name to delete it.

## Features

- Persistent ChatGPT WebView login
- Safari 16+ User-Agent spoofing
- Mic input support
- Dark mode support
- ChatGPT stop and refresh controls
- Save Context button near the ChatGPT controls
- Full rendered-chat extraction into Markdown
- PDF rendering from the exported Markdown
- App Memory tab with saved chat names
- Saved chat detail screen with PDF and Markdown
- Swipe left deletion for saved chats
- TrollStore compatibility
- Manual or Xcode install

## Memory behavior

```text
ChatGPT tab
  -> Save Context
  -> extract visible conversation DOM
  -> write PDF and Markdown into app Memory
  -> Memory tab shows the saved chat title
  -> tap title to open PDF and Markdown
  -> Start New Chat opens ChatGPT for continuation
```

The app does not require Supabase for this flow. Supabase and database experiments may remain in the repository for reference, but they are not part of the active two-tab user experience.

## Source controlled app

The app source lives under:

- `ChatGPTWebView/`
- `AppMemory/`
- `project.yml`

The build workflow generates the Xcode project from `project.yml` and uploads an unsigned IPA artifact.

## Build Requirements

- Xcode 14+
- Target iOS 15-16
- Swift 5.0+

## Installation

1. Open this project in Xcode
2. Choose your device or simulator
3. Hit “Run” to build

## License

MIT
