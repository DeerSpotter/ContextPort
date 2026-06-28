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
- TrollStore compatibility
- Manual or Xcode install

## Supabase memory direction

The next app direction is a Supabase backed memory layer for project/session continuity.

Goal: avoid losing progress when a chat gets too large by storing compact project memory, summaries, decisions, tasks, artifacts, and file notes outside the chat session.

Start here:

- [Project goals](docs/PROJECT_GOALS.md)
- [Phase 1 Supabase memory plan](docs/PHASE_1_SUPABASE_MEMORY.md)
- [Memory schema migration](supabase/migrations/20260628160000_create_memory_schema.sql)
- [Memory Edge Function](supabase/functions/memory/index.ts)
- [Swift memory client stub](AppMemory/SupabaseMemoryClient.swift)

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
