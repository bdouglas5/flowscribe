# Scribeosaur

A native macOS app for local audio and video transcription powered by Apple's Neural Engine.

Drag in any audio or video file — or paste a YouTube URL — and Scribeosaur transcribes it locally using [FluidAudio](https://github.com/FluidInference/FluidAudio) CoreML models. No cloud services, no subscriptions, no API keys required.

## Features

- **Drag-and-drop transcription** — drop any audio/video file onto the window
- **YouTube and URL support** — paste a YouTube link (or 1000+ other sites via yt-dlp) to download and transcribe
- **Speaker diarization** — detect and pre-label speakers before transcription
- **Batch processing queue** — queue multiple files and process them sequentially
- **Searchable history** — full-text search across all past transcripts
- **Markdown export** — export transcripts as `.md` files, with optional auto-export
- **Optional AI tools** — clean up, summarize, or extract action items with a local Gemma checkpoint through a managed `mlx-lm` runtime
- **AI auto-export** — automatically run an AI prompt after transcription and save the result

## System Requirements

- **macOS 14.0+** (Sonoma)
- **Apple Silicon** (M1 or later) — required for Neural Engine acceleration

## Build from Source

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen):
   ```bash
   brew install xcodegen
   ```

2. Generate the Xcode project:
   ```bash
   xcodegen generate
   ```

3. Open in Xcode 16+ and build:
   ```bash
   open Scribeosaur.xcodeproj
   ```

4. Build and run (Cmd+R).

On first launch:
- transcription dependencies are provisioned automatically if they are not already bundled
- the managed local AI runtime is installed automatically if it is not already bundled
- the default local AI model downloads, verifies, and loads automatically so AI tools are ready immediately

## AI Integration

Scribeosaur does not embed any API keys. AI features run locally through a managed Python + `mlx-lm` runtime using an Apple Silicon Gemma-compatible checkpoint stored in Application Support.

AI setup behavior:
1. First launch provisions `ffmpeg`, `yt-dlp`, `deno`, and `uv` if they are not already bundled
2. Scribeosaur installs or repairs the local AI runtime under `~/Library/Application Support/Scribeosaur/ai-runtime`
3. Scribeosaur downloads or installs the default Gemma model under `~/Library/Application Support/Scribeosaur/models`
4. Startup remains blocked until the runtime is healthy and the model is loaded into memory

For offline-ready releases, the installer can ship a pre-seeded model and an optional pre-seeded AI runtime.

## Release Packaging

The release installer flow is driven by [`scripts/build-release-installer.sh`](/Users/bdoug/Documents/Coding/flowscribe/scripts/build-release-installer.sh). It:

- archives the app
- bundles `ffmpeg`, `yt-dlp`, `deno`, and `uv` into the app resources
- optionally bundles a pre-seeded local model for offline installs
- optionally bundles a pre-seeded local AI runtime for offline installs
- signs the app and installer package
- produces a `.pkg` and `.dmg`

Example:

```bash
DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID)" \
DEVELOPER_ID_INSTALLER="Developer ID Installer: Your Name (TEAMID)" \
NOTARY_PROFILE="scribeosaur-notary" \
MODEL_SEED_PATH="/absolute/path/to/model/folder" \
AI_RUNTIME_SEED_PATH="/absolute/path/to/ai-runtime/folder" \
./scripts/build-release-installer.sh
```

## Dependencies

| Package | Purpose |
|---------|---------|
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | CoreML-based transcription, speaker diarization, and VAD |
| [GRDB](https://github.com/groue/GRDB.swift) | SQLite database for transcript storage and search |
| [mlx-lm](https://github.com/ml-explore/mlx-lm) | Local Gemma runtime used by the managed AI helper |
| [uv](https://docs.astral.sh/uv/) | Managed Python runtime bootstrap and package installation |
| deno | URL resolution and helper tooling |
| ffmpeg | Audio/video format conversion |
| yt-dlp | YouTube and URL audio extraction |

## License

[MIT](LICENSE)
