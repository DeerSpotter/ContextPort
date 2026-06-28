# Phase 2A: Supabase Memory UI

## Goal

Make the iOS app talk to the deployed Supabase memory backend.

Phase 2A adds a source controlled SwiftUI app with:

- trusted ChatGPT WebView tab
- Supabase Auth screen
- Keychain backed session storage
- Memory Test screen
- project create/list flow
- memory save/search flow
- unsigned IPA build from repository source

## What this proves

This phase proves that the app can authenticate to Supabase, call the JWT protected `memory` Edge Function, and write/search durable project memory.

## What this does not do yet

- It does not replace ChatGPT with an OpenAI API based chat shell.
- It does not let ChatGPT web automatically read Supabase memory.
- It does not inject JavaScript into `chatgpt.com`.
- It does not include any Supabase secret or service role key.
- It does not reuse ChatGPT connector authentication tokens. Those belong to the ChatGPT platform session and are not exposed to the external IPA.

## App structure

```text
ChatGPTWebView/
  App/
  Auth/
  Memory/
  Web/
  Resources/

AppMemory/
  MemoryModels.swift
  SupabaseMemoryClient.swift
```

## Runtime flow

```text
User opens Memory tab
  -> signs in with Supabase Auth
  -> token is stored in iOS Keychain
  -> app calls /functions/v1/memory with Authorization: Bearer <user JWT>
  -> Supabase RLS scopes rows to owner_id
```

## Supabase social OAuth login

The Memory login screen now supports Supabase OAuth buttons for:

- GitHub
- Google
- Apple
- Microsoft/Azure

The app opens the provider through `ASWebAuthenticationSession` and returns through this custom callback URL:

```text
chatgptwebview://auth-callback
```

Required Supabase project setup:

1. Enable the provider under Supabase Auth providers.
2. Add each provider client ID and secret in Supabase.
3. Add this redirect URL under Supabase Auth URL Configuration:

```text
chatgptwebview://auth-callback
```

Provider developer console callback URL:

```text
https://skejcbgrzlzgyjdjglrk.supabase.co/auth/v1/callback
```

## ChatGPT WebView OAuth handling

The trusted WebView keeps a host allowlist. Sign in providers can open OAuth pages in a popup or a new target frame, which can appear as a black screen if not handled by `WKUIDelegate`.

The WebView now:

- keeps the normal ChatGPT/OpenAI allowlist
- allows common OAuth identity provider domains used by Apple, Google, and Microsoft sign in
- handles `targetFrame == nil` popup navigation by loading the trusted OAuth URL into the same WebView
- still rejects non HTTPS pages and arbitrary unrelated hosts

## WebView lifecycle handling

The ChatGPT tab now uses a persistent `ChatGPTWebViewStore` with a single `WKWebView` instance. This prevents the OAuth or MFA page from reloading when SwiftUI redraws the tab or when the app backgrounds and resumes.

This can preserve the login page while the app is still alive in memory. If iOS fully terminates the app in the background, the page cannot be kept alive, but cookies and website data still use the default persistent WebKit data store.

## Build artifact

The Phase 2A build workflow uploads:

`ChatGPT-WebView-phase2-ios16-unsigned-ipa`

## Security notes

The app includes only the Supabase project URL and publishable key. Supabase publishable keys are public client keys. They do not replace user authentication and do not bypass Row Level Security.

The user access token is stored in the iOS Keychain.
