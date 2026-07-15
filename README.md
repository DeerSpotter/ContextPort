# ContextPort

**Take your context with you.**

ContextPort is a lightweight iOS app for carrying conversation context between ChatGPT, Claude, Gemini, and Grok. It keeps provider and account sessions isolated while preserving one shared, device local Memory that can move with you between AI providers.

```text
ChatGPT
  -> Save Context
  -> Memory
  -> Switch provider
  -> Claude / Gemini / Grok
  -> Continue with the same context
```

The AI can change. Your context does not have to.

## Latest release: ContextPort 2.10.4 (Build 83)

ContextPort 2.10.4 improves ChatGPT Work sessions, especially long conversations that previously became difficult or impossible to navigate.

### ChatGPT scrolling and performance

- Restores reliable vertical scrolling in long ChatGPT conversations.
- Prevents the entire conversation from dragging like a single image.
- Locks horizontal movement to stop sideways drifting and flickering during diagonal swipes.
- Adds recovery handling for ChatGPT Work sessions that remain stuck while loading.
- Preserves the existing ChatGPT login, cookies, and saved ContextPort Memory during recovery.
- Removes the broken ChatGPT message windowing behavior that interfered with the current ChatGPT layout.

Long ChatGPT conversations now feel noticeably snappier and more responsive. Scrolling begins faster, touch movement feels more natural, and the conversation no longer stalls while older messages are being managed in the background.

## Release IPA build provenance

The IPA files attached to this repository's GitHub Releases come from successful GitHub Actions workflow builds.

**GitHub Actions is the build origin. GitHub Releases is the distribution location.**

The Release page does not compile the app. The release process takes the unsigned IPA produced by the repository workflow in Actions and attaches that workflow output to the corresponding GitHub Release.

The primary source controlled IPA workflow is:

- `.github/workflows/build-source-ios16-ipa.yml`
- Workflow name: `Build ContextPort Source iOS 16 IPA`

That workflow:

1. Checks out the repository source.
2. Shows the Xcode version used by the GitHub hosted macOS runner.
3. Installs XcodeGen when required.
4. Generates `ChatGPTWebView.xcodeproj` from `project.yml`.
5. Archives ContextPort in Release configuration for a generic iOS device.
6. Builds with code signing disabled.
7. Packages the archived `.app` inside a `Payload` folder as `ContextPort-source-ios16-unsigned.ipa`.
8. Uploads the IPA as the `ContextPort-source-ios16-unsigned-ipa` Actions artifact.

The repository also contains the `Build ContextPort Unsigned IPA` workflow. It independently detects an available Xcode project or workspace and shared scheme, archives the app without signing, and packages `ContextPort-ios16-unsigned.ipa`.

The expected release path is:

```text
Source merged into main
  -> GitHub Actions workflow runs
  -> ContextPort IPA build completes successfully
  -> unsigned IPA is uploaded as a workflow artifact
  -> workflow produced IPA is attached to the GitHub Release
  -> users download ContextPort from Releases
```

Release IPA assets are expected to be traceable to a successful build in the repository's Actions history rather than a separate local developer build.

The workflows intentionally disable code signing. Release IPA files require a compatible install, signing, or sideloading method.

GitHub Actions artifacts are configured with a 14 day retention period. Publishing the workflow produced IPA as a GitHub Release asset provides the longer lived download location for a released version.

## What ContextPort does

ContextPort keeps a lightweight two tab experience:

- the currently selected AI provider
- `Memory`

The compact person button opens one combined AI and profile popup. The top strip selects ChatGPT, Claude, Gemini, or Grok. The rows below select Current User, Guest, or a saved login for that provider.

The `Save Context` button extracts the current rendered conversation, creates both Markdown and PDF, and stores both inside the local Memory vault under the conversation title.

The Memory tab shows saved chat names. Tap a saved chat to view its PDF, view its Markdown, or start a new chat using that saved context with the currently active AI provider.

## Features

- ChatGPT, Claude, Gemini, and Grok provider catalog
- Provider scoped Current User, Guest, and saved login profiles
- Independent provider and profile WebView sessions
- Persistent Current User and saved login recovery
- Session only Guest behavior per provider
- Shared device local Memory across all AI providers
- Save Context conversation capture
- Rendered conversation extraction into Markdown
- PDF rendering from exported Markdown
- Saved chat detail view with PDF and Markdown
- Direct in Memory Paste Context and file attachment bridge
- Grok auth chain handling for Google, xAI, and Grok login redirects
- Claude dedicated OAuth child WebView handling
- Safari 16+ User-Agent compatibility
- Mic input support
- Dark mode support
- Stop and refresh controls
- Swipe left deletion for saved chats
- TrollStore compatibility
- Manual or Xcode installation

## Multi AI session model

```text
Shared device local Memory
  -> Provider
      -> Profile
          -> WebView Session
```

Provider identity and account identity are separate.

Session and browser recovery storage is namespaced as:

```text
<provider>::<profile>
```

Examples:

```text
chatgpt::primary
claude::primary
gemini::guest
grok::<saved-profile>
```

This prevents provider sessions from colliding on common profile IDs such as `primary` and `guest`.

Existing ChatGPT 2.2.2 profile metadata, Keychain cookies, and browser state are migrated into the ChatGPT provider namespace on first use.

See `docs/MULTI_AI_ARCHITECTURE.md` for architecture and migration details.

## Memory behavior

```text
Active AI provider
  -> Save Context
  -> extract visible conversation DOM
  -> write PDF and Markdown into shared local Memory
  -> open Memory
  -> select a saved conversation
  -> Start New Chat
  -> continue with the currently active AI provider
```

Memory remains device local and app wide. It is not partitioned by provider, profile, or Guest state.

The core Memory flow does not require Supabase or another cloud memory service.

## Update checks

ContextPort can check the public GitHub `releases/latest` endpoint for this repository and compare the published version against the version embedded in the installed IPA.

The update checker targets:

```text
DeerSpotter/ContextPort
```

Update checks are best effort and never block app startup. `Check for updates on start` can be disabled from Settings.

## Source controlled app

The current source layout still uses the established internal project paths:

- `ChatGPTWebView/`
- `AppMemory/`
- `project.yml`

Those internal names are retained for upgrade and build compatibility. The installed product name is ContextPort.

The source controlled build workflow generates the Xcode project from `project.yml`, archives ContextPort without code signing, packages the app as an unsigned IPA, and uploads the result as a GitHub Actions artifact.

For published versions, the IPA attached to the GitHub Release should come from the successful Actions workflow output for that release source revision.

## Support development

ContextPort is actively developed and maintained as an open source project. Developers and users who want to contribute toward continued development can support the project here:

[https://buymeacoffee.com/spotterdeer](https://buymeacoffee.com/spotterdeer)

Support helps fund the time spent testing provider login flows, maintaining iOS compatibility, and continuing ContextPort development.

## Build requirements

- Xcode 14+
- iOS 16+
- Swift 5.0+

## Installation

1. Open the project in Xcode.
2. Choose your device or simulator.
3. Run the app.

Unsigned release IPA files require a compatible signing or sideloading method.

## License

MIT