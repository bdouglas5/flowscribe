# Flowscribe

A native macOS app for local audio and video transcription powered by Apple's Neural Engine.

Drag in any audio or video file — or paste a YouTube URL — and Flowscribe transcribes it locally using [FluidAudio](https://github.com/FluidInference/FluidAudio) CoreML models. No cloud services, no subscriptions, no API keys required.

## Features

- **Drag-and-drop transcription** — drop any audio/video file onto the window
- **YouTube and URL support** — paste a YouTube link (or 1000+ other sites via yt-dlp) to download and transcribe
- **Speaker diarization** — detect and pre-label speakers before transcription
- **Batch processing queue** — queue multiple files and process them sequentially
- **Searchable history** — full-text search across all past transcripts
- **Markdown export** — export transcripts as `.md` files, with optional auto-export
- **Optional AI tools** — clean up, summarize, or extract action items via [Codex CLI](https://developers.openai.com/codex/cli) (no embedded API keys)
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
   open Floscrybe.xcodeproj
   ```

4. Build and run (Cmd+R). Models download automatically on first launch.

### Bundled binaries

Flowscribe expects `ffmpeg` and `yt-dlp` binaries in `Floscrybe/Resources/Binaries/`. These are not checked into the repository — download them and place them there before building:

- [ffmpeg](https://evermeet.cx/ffmpeg/) (static macOS arm64 build)
- [yt-dlp](https://github.com/yt-dlp/yt-dlp/releases) (macOS binary)

## AI Integration

Flowscribe does not embed any API keys. AI features use the first-party [Codex CLI](https://developers.openai.com/codex/cli) already signed in on your Mac. Transcript content is sent to OpenAI through your local Codex session when you run an AI tool.

To enable AI features:
1. Install Codex CLI (`npm install -g @openai/codex`)
2. Open Flowscribe Settings > AI and sign in with ChatGPT
3. Use the built-in tools (Clean Up, Summary, Action Items) or create custom prompts

## Dependencies

| Package | Purpose |
|---------|---------|
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | CoreML-based transcription, speaker diarization, and VAD |
| [GRDB](https://github.com/groue/GRDB.swift) | SQLite database for transcript storage and search |
| ffmpeg | Audio/video format conversion |
| yt-dlp | YouTube and URL audio extraction |

## License

[MIT](LICENSE)
