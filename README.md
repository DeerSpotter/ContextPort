# ChatGPT WebView for iOS 16

A lightweight iOS WebView wrapper for ChatGPT’s web app. Built with Swift and WKWebView, optimized for fast performance and speech-to-text microphone support on iOS 16.

## Current trust position

This fork is being converted into a trusted, source controlled build path.

The upstream release IPA should not be treated as trusted unless that exact IPA is separately inspected. The trusted direction in this repo is to generate and build an auditable iOS 16 app from repository source through GitHub Actions.

## Features

- Persistent login
- Safari 16+ User-Agent spoofing
- Mic input (speech-to-text)
- Dark mode support
- ChatGPT tab stop button for quickly stopping current WebView activity
- ChatGPT tab refresh button for reloading a stale or frozen WebView session
- Local device memory vault for offline context capture
- Local memory search and rendered context copy workflow
- Bring your own Supabase project setup
- Supabase setup diagnostics
- Supabase setup deep link import
- Supabase Auth test flow
- Supabase memory dashboard
- Supabase memory save/search management UI
- Virtual MCP memory prototype with approval based save_context_after_approval flow
- Temporary repo context pack generator while MCP memory is built
- Optional local context pack UI for targeted file selection
- Copy context for ChatGPT workflow
- TrollStore compatibility
- Manual or Xcode install

## Memory direction

The app is moving toward a local first memory model.

The most important path is now:

```text
ChatGPT session context
  -> copy or share into the app
  -> save to Local Device Memory Vault
  -> search locally
  -> render a copy-ready project context block
  -> optionally sync or push to Supabase later
```

This makes the app useful even when a ChatGPT connector write is unavailable, blocked, or not deployed. Supabase remains valuable for sync, backup, and future MCP connector work, but the local vault is the first place context should land.

Manual context writing is not the product goal. Memory capture should reduce work through local import, an OpenAI API chat tab, a ChatGPT App/MCP connector, or another tool driven flow where ChatGPT can create structured memory with user approval.

The public app does not hardcode a developer-owned Supabase project. Each user supplies their own Supabase project URL and publishable key, then deploys the memory schema and Edge Function into that project.

A later phase documents a multi cloud file context layer. That idea keeps large files and archives outside the GPT sandbox, routes uploads into user connected cloud storage, and exposes files to GPT through scoped context links and backend tools.

Phase 5 introduces a virtual MCP memory layer inside the app. It uses the same tool name and contract planned for the real connector, while routing the approved write through the existing Supabase memory backend.

Start here:

- [Project goals](docs/PROJECT_GOALS.md)
- [Phase 1 Supabase memory plan](docs/PHASE_1_SUPABASE_MEMORY.md)
- [Phase 1 deployment status](docs/PHASE_1_DEPLOYMENT_STATUS.md)
- [Phase 2A memory UI](docs/PHASE_2A_MEMORY_UI.md)
- [Saved memory direction context](docs/SAVED_CONTEXT_MEMORY_DIRECTION.md)
- [Context pack guide](docs/CONTEXT_PACK_GUIDE.md)
- [Context pack UI guide](docs/CONTEXT_PACK_UI_GUIDE.md)
- [Copy context for ChatGPT](docs/COPY_CONTEXT_FOR_CHATGPT.md)
- [Phase 4B multi cloud file context](docs/PHASE_4B_MULTI_CLOUD_FILE_CONTEXT.md)
- [Phase 5 virtual MCP memory](docs/PHASE_5_VIRTUAL_MCP_MEMORY.md)
- [Onboarding options](docs/ONBOARDING_OPTIONS.md)
- [Auth login and redirect setup](docs/AUTH_LOGIN_REDIRECT_SETUP.md)
- [Connector assisted setup](docs/CONNECTOR_ASSISTED_SETUP.md)
- [Memory schema migration](supabase/migrations/20260628160000_create_memory_schema.sql)
- [Memory Edge Function](supabase/functions/memory/index.ts)
- [BYO setup script](scripts/setup-byo-supabase-memory.sh)
- [Build context pack script](scripts/build-context-pack.sh)
- [Build context pack PowerShell script](scripts/build-context-pack.ps1)
- [Interactive context pack UI](scripts/context-pack-ui.py)
- [Swift memory client](AppMemory/SupabaseMemoryClient.swift)

## Source controlled app

The Phase 2 app source lives under:

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
