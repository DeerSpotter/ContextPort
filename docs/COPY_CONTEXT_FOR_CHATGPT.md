# Copy Context for ChatGPT

## Purpose

This is the first practical bridge between saved Supabase memory and the ChatGPT WebView.

The app does not inject JavaScript into `chatgpt.com`. Instead, the user searches saved memory, copies a formatted context block, and pastes it into the ChatGPT tab.

## Workflow

```text
Open Memory tab
  -> search saved memory
  -> review results
  -> tap Copy Context for ChatGPT
  -> open ChatGPT tab
  -> paste the formatted context into the chat
```

## Output format

The copied text tells ChatGPT:

- this is saved project memory
- it should be treated as previous user supplied context
- it should be used when relevant
- it should not override the user's current instructions

Example shape:

```text
Use the following saved project memory as background context for this conversation. Treat it as user provided context from previous work. Use it when relevant, but do not assume it overrides my current instructions.

Project: ChatGPT-WebView
Memory search query: oauth redirect

Saved memory results:
1. GitHub login redirect fix
Content: Supabase Site URL and Redirect URLs must include chatgptwebview://auth-callback. GitHub OAuth callback stays as Supabase /auth/v1/callback.
Tags: supabase, github, oauth, ios

Please continue from this context and ask if anything is unclear.
```

## Current limitation

This is manual copy/paste. ChatGPT does not automatically call the Supabase memory backend yet.

## Why this comes before API chat or MCP

This option is intentionally simple. It proves the memory format, user experience, and project context structure before adding a more complex automatic bridge.

Future options:

```text
Option B: Build an OpenAI API chat tab
  -> retrieve memory automatically
  -> send memory context with the prompt

Option C: Build a ChatGPT App/Action/MCP style bridge
  -> ChatGPT can call the same Supabase memory backend directly
```
