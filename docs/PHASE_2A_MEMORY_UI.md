# Phase 2A: Supabase Memory UI

## Goal

Make the iOS app talk to a user supplied Supabase memory backend.

Phase 2A adds a source controlled SwiftUI app with:

- trusted ChatGPT WebView tab
- always available Setup tab for assisted BYO configuration
- bring your own Supabase setup screen
- Supabase Auth screen
- Keychain backed session storage
- Memory dashboard first screen
- automatic default memory project creation after login
- project create/list flow
- memory save/search flow
- unsigned IPA build from repository source

## Architecture decision

This app must not make one developer's Supabase database the shared backend for every installed copy of the IPA.

The public app architecture is now:

```text
User installs app
  -> user enters their own Supabase project URL and publishable key
  -> user deploys the memory schema and Edge Function to that Supabase project
  -> app logs into that user's Supabase Auth instance
  -> app stores memory only in that user's Supabase project
```

## What this proves

This phase proves that the app can authenticate to Supabase, call the JWT protected `memory` Edge Function, and write/search durable project memory.

## What this does not do yet

- It does not replace ChatGPT with an OpenAI API based chat shell.
- It does not let ChatGPT web automatically read Supabase memory.
- It does not inject JavaScript into `chatgpt.com`.
- It does not include any Supabase secret or service role key.
- It does not reuse ChatGPT connector authentication tokens. Those belong to the ChatGPT platform session and are not exposed to the external IPA.
- It does not hardcode the developer's Supabase project as the backend for all users.

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
User opens Setup tab
  -> enters their Supabase project URL and publishable key
  -> runs diagnostics
  -> opens Supabase/GitHub setup pages inside the app if needed
  -> copies callback URLs from the app
  -> saves setup
  -> opens Memory tab
  -> signs in with Supabase Auth for that project
  -> token is stored in iOS Keychain
  -> app loads memory projects
  -> if no projects exist, app creates and selects ChatGPT-WebView
  -> app calls /functions/v1/memory with Authorization: Bearer <user JWT>
  -> Supabase RLS scopes rows to owner_id inside that user's project
```

## Memory tab layout

The Memory tab keeps the `externaldrive.connected.to.line.below` tab icon because that visual identity is clear and memorable.

The screen itself is dashboard first:

```text
Memory tab
  -> dashboard card with account, selected project, backend, project count, result count, status
  -> quick actions for Refresh and Copy Context
  -> Search Memory card
  -> Save Memory card
  -> Project management card
  -> Account and Setup card
```

This keeps the most common workflow near the top:

1. confirm the selected memory project
2. search for saved context
3. copy context for ChatGPT
4. save a new memory when needed

Setup and account actions stay lower on the screen because the dedicated Setup tab already handles assisted configuration.

## Supabase social OAuth login

The Memory login screen supports Supabase OAuth buttons for:

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
https://<your-project-ref>.supabase.co/auth/v1/callback
```

For the full login and redirect checklist, see:

```text
docs/AUTH_LOGIN_REDIRECT_SETUP.md
```

## ChatGPT WebView OAuth handling

The trusted WebView keeps a host allowlist. Sign in providers can open OAuth pages in a popup or a new target frame, which can appear as a black screen if not handled by `WKUIDelegate`.

The WebView now:

- keeps the normal ChatGPT/OpenAI allowlist
- allows common OAuth identity provider domains used by Apple, Google, and Microsoft sign in
- handles `targetFrame == nil` popup navigation by loading the trusted OAuth URL into the same WebView
- still rejects non HTTPS pages and arbitrary unrelated hosts

## External link handling

The WebView keeps trusted ChatGPT, OpenAI, and OAuth domains inside the app. Normal outbound links from ChatGPT answers are no longer silently blocked.

External links now open outside the app through iOS using `UIApplication.shared.open`. This keeps the ChatGPT WebView constrained while still allowing normal links, email links, phone links, and text message links to work.

## Assisted setup handling

The Setup tab is always reachable. It includes:

- in app browser buttons for Supabase Dashboard, GitHub OAuth Apps, and repo docs
- setup diagnostics
- setup deep link preview
- app callback URL copy button
- provider callback URL copy button

## Default memory project handling

After login or session restore, the app loads the user's memory projects. If none exist, it automatically creates and selects a default project named `ChatGPT-WebView`.

This prevents a new user from landing on `Selected: None` with Save/Search disabled.

## WebView lifecycle handling

The ChatGPT tab now uses a persistent `ChatGPTWebViewStore` with a single `WKWebView` instance. This prevents the OAuth or MFA page from reloading when SwiftUI redraws the tab or when the app backgrounds and resumes.

This can preserve the login page while the app is still alive in memory. If iOS fully terminates the app in the background, the page cannot be kept alive, but cookies and website data still use the default persistent WebKit data store.

The ChatGPT tab also includes a small refresh control. If the WebView feels frozen after returning to the app, the user can reload the current ChatGPT session without restarting the app.

## Build artifact

The Phase 2A build workflow uploads:

`ChatGPT-WebView-phase2-ios16-unsigned-ipa`

## Security notes

The app stores only the user's Supabase project URL and publishable key. Supabase publishable keys are public client keys. They do not replace user authentication and do not bypass Row Level Security.

Never paste a Supabase secret key or service role key into the app. Secret/service keys belong only in trusted server side code.

The user access token is stored in the iOS Keychain.
