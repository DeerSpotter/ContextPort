# ChatGPT WebView for iOS 16

A lightweight iOS WebView AI memory shell built with Swift and WKWebView. The app keeps local conversation Memory while supporting provider scoped web sessions for ChatGPT, Claude, Gemini, and Grok.

## Current trust position

This fork is being converted into a trusted, source controlled build path. The upstream release IPA should not be treated as trusted unless that exact IPA is separately inspected.

## Release IPA build provenance

The IPA files attached to this repository's GitHub Releases come from successful GitHub Actions workflow builds.

**GitHub Actions is the build origin. GitHub Releases is the distribution location.**

The Release page does not compile the app. The project release process takes the unsigned IPA produced by the repository workflow in Actions and attaches that workflow output to the corresponding GitHub Release.

The primary source controlled IPA workflow is:

- `.github/workflows/build-source-ios16-ipa.yml`
- Workflow name: `Build Source iOS 16 IPA`

That workflow:

1. Checks out the repository source.
2. Shows the Xcode version used by the GitHub hosted macOS runner.
3. Installs XcodeGen when required.
4. Generates `ChatGPTWebView.xcodeproj` from `project.yml`.
5. Archives the app in Release configuration for a generic iOS device.
6. Builds with code signing disabled.
7. Packages the archived `.app` inside a `Payload` folder as an unsigned `.ipa`.
8. Uploads the IPA as a GitHub Actions workflow artifact.

The repository also contains the `Build Unsigned IPA` workflow. That workflow independently detects an available Xcode project or workspace and shared scheme, archives the app without signing, packages the result as an unsigned IPA, and uploads its own Actions artifact.

The expected release path is:

```text
Source merged into main
  -> GitHub Actions workflow runs
  -> IPA build completes successfully
  -> unsigned IPA is uploaded as a workflow artifact
  -> that workflow produced IPA is attached to the GitHub Release
  -> users download the IPA from Releases
```

This means release IPA assets are expected to be traceable back to a successful build in the repository's Actions history rather than a separate local developer build.

The workflows intentionally set code signing to disabled. Release IPA files produced by these workflows are unsigned and require a compatible install, signing, or sideloading method.

GitHub Actions artifacts are configured with a 14 day retention period. Publishing the workflow produced IPA as a GitHub Release asset provides the longer lived download location for a released version.

## Current app direction

The app keeps the lightweight two-tab experience:

- the currently selected AI provider
- `Memory`

The compact person button opens one combined AI and profile popup. The top strip selects ChatGPT, Claude, Gemini, or Grok. The rows below select Current User, Guest, or a saved login for that provider.

The `Save Context` button extracts the current rendered conversation, creates both Markdown and PDF, and stores both inside the app Memory vault under the conversation title.

The Memory tab remains intentionally simple. It shows saved chat names only. Tap a name to open the saved chat memory, view the PDF, view the Markdown, or start a new chat from that saved memory. Swipe left on a saved chat name to delete it.

## Features

- ChatGPT, Claude, Gemini, and Grok provider catalog
- Provider scoped Current User, Guest, and saved login profiles
- Independent provider/profile WebView sessions
- Persistent Current User and saved login recovery
- Session only Guest behavior per provider
- Small `x` removal control for saved logins
- Shared app wide local Memory
- Safari 16+ User-Agent spoofing
- Mic input support
- Dark mode support
- Stop and refresh controls
- Save Context button near the active AI controls
- Rendered conversation extraction into Markdown
- PDF rendering from exported Markdown
- App Memory tab with saved chat names
- Saved chat detail screen with PDF and Markdown
- Direct in memory Paste Context and file attachment bridge
- Swipe left deletion for saved chats
- TrollStore compatibility
- Manual or Xcode install

## Multi AI session model

```text
Shared local Memory
  -> Provider
      -> Profile
          -> WebView Session
```

Provider and account identity are intentionally separate.

Session and browser recovery storage is namespaced as:

```text
<provider>::<profile>
```

This prevents provider sessions from colliding on common profile IDs such as `primary` and `guest`.

Existing ChatGPT 2.2.2 profile metadata, Keychain cookies, and browser state are migrated into the new ChatGPT namespace on first use.

See `docs/MULTI_AI_ARCHITECTURE.md` for the architecture and migration details.

## Memory behavior

```text
Active AI tab
  -> Save Context
  -> extract visible conversation DOM
  -> write PDF and Markdown into shared app Memory
  -> Memory tab shows the saved chat title
  -> tap title to open PDF and Markdown
  -> Start New Chat opens the currently active AI provider for continuation
```

Memory remains device local and app wide. It is not partitioned by provider, profile, or Guest state.

The app does not require Supabase for this flow. Supabase and database experiments may remain in the repository for reference, but they are not part of the active two-tab user experience.

## Source controlled app

The app source lives under:

- `ChatGPTWebView/`
- `AppMemory/`
- `project.yml`

The source controlled build workflow generates the Xcode project from `project.yml`, archives the app without code signing, packages the app as an unsigned IPA, and uploads the result as a GitHub Actions artifact.

For published versions, the IPA attached to the GitHub Release is taken from the successful Actions workflow output for that release source revision.

## Build Requirements

- Xcode 14+
- Target iOS 16+
- Swift 5.0+

## Installation

1. Open this project in Xcode.
2. Choose your device or simulator.
3. Run the app.

## License

MIT
