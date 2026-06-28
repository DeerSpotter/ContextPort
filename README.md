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
- Bring your own Supabase project setup
- Supabase setup diagnostics
- Supabase setup deep link import
- Supabase Auth test flow
- Supabase memory save/search test flow
- Copy context for ChatGPT workflow
- TrollStore compatibility
- Manual or Xcode install

## Supabase memory direction

The next app direction is a Supabase backed memory layer for project/session continuity.

Goal: avoid losing progress when a chat gets too large by storing compact project memory, summaries, decisions, tasks, artifacts, and file notes outside the chat session.

The public app does not hardcode a developer-owned Supabase project. Each user supplies their own Supabase project URL and publishable key, then deploys the memory schema and Edge Function into that project.

Start here:

- [Project goals](docs/PROJECT_GOALS.md)
- [Phase 1 Supabase memory plan](docs/PHASE_1_SUPABASE_MEMORY.md)
- [Phase 1 deployment status](docs/PHASE_1_DEPLOYMENT_STATUS.md)
- [Phase 2A memory UI](docs/PHASE_2A_MEMORY_UI.md)
- [Copy context for ChatGPT](docs/COPY_CONTEXT_FOR_CHATGPT.md)
- [Onboarding options](docs/ONBOARDING_OPTIONS.md)
- [Auth login and redirect setup](docs/AUTH_LOGIN_REDIRECT_SETUP.md)
- [Connector assisted setup](docs/CONNECTOR_ASSISTED_SETUP.md)
- [Memory schema migration](supabase/migrations/20260628160000_create_memory_schema.sql)
- [Memory Edge Function](supabase/functions/memory/index.ts)
- [BYO setup script](scripts/setup-byo-supabase-memory.sh)
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
