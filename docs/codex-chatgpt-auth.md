# Floscrybe Codex and ChatGPT Integration

Updated: March 13, 2026

## What this implements

Floscrybe now supports native AI account management from Settings by using the local first-party `codex` CLI session already installed on the Mac.

The app can now:

- Detect whether `codex` is installed
- Show current Codex login status
- Start the official ChatGPT sign-in flow through `codex login`
- Sign out through `codex logout`
- Run a real execution health check through `codex exec`
- Let users edit built-in prompts and create or delete custom prompts
- Use the authenticated Codex session for transcript cleanup, summaries, action-item extraction, and custom prompt execution
- Save AI output locally per transcript and view it inside the transcript screen

## Important auth constraint

As of March 13, 2026, OpenAI documents ChatGPT sign-in for first-party Codex clients such as the Codex CLI. OpenAI also documents that ChatGPT billing and API billing are separate products.

Because of that, Floscrybe does **not** try to fake or reverse-engineer a custom third-party “Sign in with ChatGPT” OAuth flow. Instead, it delegates authentication to the supported local Codex client and then executes transcript tasks through that authenticated session.

This is the supported path implemented in the app.

## User flow

1. Install Codex CLI if it is not already available.
2. Open `Floscrybe > Settings > AI`.
3. Click `Sign In with ChatGPT`.
4. Complete the browser-based OpenAI sign-in flow.
5. Click `Run Health Check` or let the app run it automatically after login.
6. Open any transcript and use the `AI` menu in the bottom toolbar.
7. Switch between `Transcript` and `AI` in the detail view to review saved output.

## Transcript tools

- `Clean Up`: rewrites transcript text into cleaner notes while preserving meaning
- `Summary`: produces a concise markdown summary
- `Action Items`: extracts explicit tasks, owners, and due dates when present
- `Custom prompts`: user-defined transcript actions created in Settings

## Prompt library

Prompt templates live in `Settings > AI`.

Users can:

- edit the built-in prompt bodies
- create custom prompts
- rename custom prompts
- delete custom prompts

The toolbar AI menu uses the same prompt library, so any saved template becomes available immediately in transcript detail.

## Saved AI output

AI generations are stored locally in the app database per transcript and prompt.

The transcript detail view now has a built-in toggle between the original transcript and saved AI output, so the user no longer has to use a modal popup to inspect generated content.

All transcript tools run through `codex exec` with:

- `--skip-git-repo-check`
- `--ephemeral`
- `--sandbox read-only`
- stdin-fed prompts to avoid command-line length limits on large transcripts

## Health check

The health check performs a minimal read-only Codex execution and expects a deterministic response. This confirms:

- the local `codex` binary is present
- the user has a valid Codex session
- Floscrybe can successfully execute an authenticated request

## Privacy and behavior

When a user runs an AI transcript tool, transcript content is sent to OpenAI through the user’s local Codex session.

Floscrybe does not store an OpenAI API key and does not bundle a hidden project credential.

## Troubleshooting

- If `Codex CLI not installed` appears, install the CLI first and reopen Settings.
- If `Sign In with ChatGPT` fails, run `codex login` manually in Terminal to inspect the local environment and complete first-time setup.
- If the health check fails, verify `codex login status` works in Terminal on the same Mac account.
- If transcript tools fail on a signed-in session, confirm `codex exec` works locally outside the app.

## Official references

- Codex CLI: https://developers.openai.com/codex/cli
- Using Codex with your ChatGPT plan: https://help.openai.com/en/articles/11369540
- Codex CLI getting started: https://help.openai.com/en/articles/11750541
- ChatGPT billing vs API billing: https://help.openai.com/en/articles/8156019
