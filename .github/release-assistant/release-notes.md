# ContextPort 2.10.12

ContextPort 2.10.12 restores responsive long Work conversations and gives users direct control over whether the app reopens their last chat at startup.

## Highlights

- Restored fast ChatGPT Work scrolling by removing the indefinite whole-document mutation observer that reacted to every streamed text update.
- Preserved Follow Latest behavior with a lightweight cached scroll target and lower-frequency checks.
- Added **Settings → Startup → Restore Last Chat**.
- Turning **Restore Last Chat** off clears saved conversation URLs while preserving account sign-ins, provider cookies, local storage, saved profiles, and Memory.
- Added the developer support link in Settings.

## Startup behavior

**Restore Last Chat** remains enabled by default. Users who prefer a clean provider home page at launch can turn it off without signing out.

## Build

- Version: 2.10.12
- Build: 91
- Minimum iOS version: iOS 16

## Validation

Both ContextPort unsigned IPA workflows completed successfully for build 91 before merge.

## Installation

Download the attached IPA after it is added to this release. Existing signing and sideloading requirements remain unchanged.
