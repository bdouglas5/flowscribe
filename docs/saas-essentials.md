# Floscrybe — SaaS Essentials

**Source:** [[Floscrybe]]
**Created:** 2026-03-07
**Last Updated:** 2026-03-07
**Status:** Draft

## Vision Summary

Floscrybe is a native macOS transcription app for personal use. Drag in any audio/video file or paste a YouTube URL, and it transcribes locally using FluidAudio's CoreML models on Apple's Neural Engine. No cloud, no subscriptions, no Python. Features speaker diarization with pre-labeling, a universal processing queue, searchable transcript history, and optional AI analysis via API keys. Built entirely in Swift/SwiftUI as a zero-cost, single-user tool.

---

## Tech Stack

### App Framework & UI

| Technology | Purpose | Why This Choice |
|-----------|---------|-----------------|
| **Swift 6.2** | Primary language | Latest Swift with native `Subprocess` support for running ffmpeg/yt-dlp — no Process hacks needed |
| **SwiftUI** | UI framework | Native macOS look, drag-and-drop via `.onDrop`, minimal code for sidebar/detail layout |
| **NavigationSplitView** | App layout | Two-column sidebar + detail view — exactly the transcript browser pattern needed. Column visibility persists via `@SceneStorage` |
| **UTType (.audio, .video, .fileURL)** | File drop targets | SwiftUI's `onDrop` modifier with UTType lets you accept any audio/video file natively |

### ML & Transcription

| Technology | Purpose | Why This Choice |
|-----------|---------|-----------------|
| **FluidAudio** (v0.12.2+) | ASR, speaker diarization, VAD | Single Swift package — transcription (Parakeet TDT v3), diarization (PyAnnote CoreML), and VAD (Silero) all running on Neural Engine. No Python, no sidecar. ~110x real-time factor on M4 Pro |
| **Parakeet TDT v3 (0.6B)** | ASR model | NVIDIA's open-source model compiled to CoreML by FluidAudio. Supports 25 European languages. Higher accuracy than Whisper large-v3 in benchmarks |
| **PyAnnote (CoreML port)** | Speaker diarization | Same underlying tech as WhisperX's diarization, but compiled to CoreML. Segmentation → embedding → clustering pipeline |
| **Silero VAD (CoreML port)** | Voice activity detection | Detects speech segments before transcription — reduces processing time on files with long silences |

### External Binaries

| Technology | Purpose | Why This Choice |
|-----------|---------|-----------------|
| **ffmpeg** | Audio/video format conversion | Universal format support — converts anything to WAV for FluidAudio. Not bundled in app — **downloaded on first launch** to `~/Library/Application Support/Floscrybe/bin/` to respect LGPL licensing |
| **yt-dlp** | YouTube/URL audio extraction | Gold standard for video platform audio extraction. Supports 1000+ sites beyond YouTube. Also **downloaded on first launch** alongside ffmpeg. Updated via in-app update check |
| **swift-subprocess** | Subprocess management | Swift 6.2's official async subprocess API. Clean `await run(.at(ffmpegPath), arguments: [...])` syntax for calling ffmpeg and yt-dlp |

**Important — LGPL Compliance:**
ffmpeg is LGPL-licensed. Bundling it inside the app would require open-sourcing the app. Instead, follow the MacYTDL pattern: download ffmpeg and yt-dlp binaries on first launch to Application Support. This keeps the app's code proprietary (if ever distributed) and respects licensing.

### Database & Storage

| Technology | Purpose | Why This Choice |
|-----------|---------|-----------------|
| **GRDB.swift** (v7.10+) | Transcript database | SQLite wrapper with full-text search (FTS5), migration support, and excellent performance. Better than SwiftData for this use case — SwiftData has performance issues with large datasets, poor background task support, and doesn't work well outside SwiftUI views. GRDB gives SQL control for full-text search across transcripts |
| **SQLite FTS5** | Full-text search | Built into SQLite via GRDB — enables instant search across all transcript text. No external search service needed |
| **FileManager** | Temp file management | Standard macOS API for temp directory management, file cleanup after transcription |

**Storage Layout:**
```
~/Library/Application Support/Floscrybe/
├── bin/
│   ├── ffmpeg              (downloaded on first launch)
│   └── yt-dlp              (downloaded on first launch)
├── models/                 (FluidAudio CoreML models, cached after first download)
├── db/
│   └── floscrybe.sqlite    (GRDB database — transcripts, metadata, FTS index)
├── exports/                (markdown exports, if user wants a default location)
└── temp/                   (audio files during processing — cleared on app launch)
```

### Development Tools

| Technology | Purpose | Why This Choice |
|-----------|---------|-----------------|
| **Xcode 16+** | IDE | Required for SwiftUI macOS development |
| **Swift Package Manager** | Dependency management | FluidAudio and GRDB both distributed via SPM — no CocoaPods needed |
| **Git** | Version control | Standard |
| **macOS 14.0+ (Sonoma)** | Minimum deployment target | FluidAudio requires macOS 14+, Apple Silicon |

### AI / LLM Layer (V2)

| Technology | Purpose | Why This Choice |
|-----------|---------|-----------------|
| **Claude API** (direct HTTP) | Transcript analysis | `URLSession` POST to `api.anthropic.com` — no SDK needed for simple prompt/response. User provides own API key |
| **OpenAI API** (direct HTTP) | Transcript analysis (alt) | Same pattern — `URLSession` POST. User chooses which key to configure |

No SDK dependencies needed for V2 AI features — both APIs are simple enough to call with native `URLSession` and `Codable` response parsing.

### Alternatives Considered

| Category | Considered | Why Not |
|----------|-----------|---------|
| ASR Engine | **WhisperX (Python)** | Requires PyInstaller sidecar, Python runtime, two-language stack. FluidAudio gives the same quality in pure Swift |
| ASR Engine | **WhisperKit** | No built-in speaker diarization. Would need a second package for diarization |
| ASR Engine | **whisper.cpp** | C++ integration complexity. No diarization. FluidAudio wraps better models with a cleaner API |
| ASR Engine | **Apple SFSpeechRecognizer** | Lower accuracy than Parakeet, limited language support, no diarization |
| Database | **SwiftData** | Poor performance with large datasets, no FTS support, requires SwiftUI view context, can't do background writes cleanly |
| Database | **SQLite.swift** | Viable but GRDB has better ergonomics, built-in FTS5 support, and migration tooling |
| Database | **Core Data** | Heavy for this use case. GRDB is lighter and gives direct SQL access |
| Database | **JSON files only** | No search capability. Database needed for full-text search across transcript history |
| Subprocess | **Foundation Process** | Legacy API, no async/await, uses ObjC exceptions. swift-subprocess is the modern replacement |
| UI | **AppKit** | More power but more code. SwiftUI is sufficient and faster to build |
| UI | **Electron/Tauri** | Massive overhead for a simple native app. Swift/SwiftUI is the right tool |
| Binary bundling | **Embed ffmpeg in .app** | LGPL requires open-sourcing the app. Download-on-first-launch avoids this |

---

## Cost Estimate (Monthly)

| Component | Cost |
|-----------|------|
| FluidAudio | **$0** (MIT/Apache 2.0) |
| GRDB.swift | **$0** (MIT) |
| ffmpeg | **$0** (LGPL, downloaded) |
| yt-dlp | **$0** (Unlicense) |
| Hosting/servers | **$0** (fully local) |
| Apple Developer Program | **$0** (not distributing — personal use) |
| Claude API (V2, optional) | **~$0-5/mo** (pay-per-use, light personal usage) |
| **Total** | **$0/mo** (MVP), **~$0-5/mo** (with V2 AI) |

---

## Roadmap

### Phase 0: Foundation
**Duration:** 1 week
**Theme:** Project scaffolding, dependencies, and first-launch setup

**Milestones:**
- [ ] Create Xcode project — SwiftUI macOS app, deployment target macOS 14.0
- [ ] Add FluidAudio via SPM, verify model download and basic transcription works
- [ ] Add GRDB via SPM, set up database schema (transcripts table, FTS5 virtual table)
- [ ] Build first-launch flow: download ffmpeg + yt-dlp to Application Support
- [ ] Verify subprocess calls to ffmpeg and yt-dlp work via swift-subprocess

**Technical Focus:** Proving out FluidAudio transcription, subprocess binary management, and database setup
**Success Criteria:** Can transcribe a local WAV file from a Swift test harness and store the result in GRDB

---

### Phase 1: Core MVP — Transcription Engine
**Duration:** 2 weeks
**Theme:** The core loop — drop a file, get a transcript

**Milestones:**
- [ ] Drag-and-drop file input (`.onDrop` with UTType.audio, UTType.video, UTType.fileURL)
- [ ] Format detection: if not WAV → ffmpeg converts to WAV in temp dir
- [ ] FluidAudio transcription with progress callback → progress bar in UI
- [ ] Transcript result stored in GRDB with metadata (filename, date, duration)
- [ ] Basic two-column layout: sidebar (file list) + detail (transcript text)
- [ ] Copy button — copies transcript text to clipboard
- [ ] Temp file cleanup after transcription completes

**Technical Focus:** End-to-end file → transcript pipeline
**Success Criteria:** Can drag an MP4 onto the window and get an accurate transcript displayed in the detail view

---

### Phase 2: Queue, Speakers & History
**Duration:** 2 weeks
**Theme:** Multi-file workflow, speaker diarization, and persistent history

**Milestones:**
- [ ] Processing queue — FIFO, visible in UI, handles multiple files
- [ ] Queue states: waiting → transcribing (progress %) → done / error (retry)
- [ ] Speaker diarization toggle in settings (global default)
- [ ] Speaker pre-labeling dialog: number of speakers + name fields → appears before transcription when toggle is ON
- [ ] Diarization output mapped to user-provided speaker names
- [ ] Transcript history in sidebar — all past transcripts, newest first
- [ ] Full-text search bar (FTS5 via GRDB) across all transcripts
- [ ] Click any history item → view full transcript in detail pane

**Technical Focus:** Queue architecture, FluidAudio diarization API, search indexing
**Success Criteria:** Can queue 5 files, have 2 speakers detected and labeled correctly, search across all past transcripts

---

### Phase 3: YouTube, Export & Polish
**Duration:** 2 weeks
**Theme:** URL support, export options, and UX refinement

**Milestones:**
- [ ] YouTube URL input — paste field or ⌘V detection
- [ ] yt-dlp downloads audio to temp dir → enters normal transcription queue
- [ ] Video title pulled from yt-dlp metadata as transcript label
- [ ] Timestamp toggle in transcript view (timestamps ON/OFF)
- [ ] Transcript display adapts: with/without timestamps, with/without speaker labels
- [ ] Export as `.md` file (markdown with frontmatter: title, date, duration, speakers)
- [ ] Settings panel: speaker detection default, timestamp default, storage info, clear data
- [ ] App icon and window chrome polish
- [ ] Error handling: no audio in file, network errors for yt-dlp, unsupported formats

**Technical Focus:** yt-dlp integration, export formatting, settings persistence
**Success Criteria:** Can paste a YouTube URL, get a timestamped speaker-labeled transcript, export it as markdown, and find it later via search

---

### Phase 4: AI Analysis & Extended Sources (V2)
**Duration:** 2-3 weeks
**Theme:** Optional AI-powered transcript analysis and additional input sources

**Milestones:**
- [ ] API key configuration in settings (Claude key, OpenAI key — stored in Keychain)
- [ ] "Analyze" button on transcripts (visible only when an API key is configured)
- [ ] Preset analysis prompts: Summarize, Extract action items, Extract decisions, Custom prompt
- [ ] AI response displayed below transcript in "Analysis" section
- [ ] Analysis saved alongside transcript in database
- [ ] Podcast RSS feed support: paste RSS URL → list episodes → select → download + transcribe
- [ ] SRT/VTT subtitle export format
- [ ] Keyboard shortcuts: ⌘V paste URL, ⌘C copy transcript, ⌘E export
- [ ] Bulk URL paste (multiple YouTube links queued at once)

**Technical Focus:** URLSession API calls to Claude/OpenAI, RSS feed parsing, subtitle format generation
**Success Criteria:** Can transcribe a podcast episode from RSS, run a Claude summarization on it, and export the transcript as SRT

---

## Architecture Diagram

```
┌────────────────────────────────────────────────────────────┐
│                     Floscrybe.app                          │
│                                                            │
│  ┌──────────────┐    ┌──────────────────────────────────┐  │
│  │   SwiftUI    │    │        FluidAudio (CoreML)       │  │
│  │              │    │  ┌────────┐ ┌───────┐ ┌───────┐  │  │
│  │ Sidebar      │    │  │Parakeet│ │PyAnnote│ │Silero │  │  │
│  │  • Queue     │    │  │  ASR   │ │Diariz. │ │  VAD  │  │  │
│  │  • History   │    │  └───┬────┘ └───┬────┘ └───┬───┘  │  │
│  │  • Search    │    │      └──────────┼──────────┘      │  │
│  │              │    │           Neural Engine            │  │
│  │ Detail       │    └──────────────────────────────────┘  │
│  │  • Transcript│                                          │
│  │  • Copy/Export│   ┌──────────────────────────────────┐  │
│  │  • Analyze   │   │     External Binaries             │  │
│  └──────┬───────┘   │  ┌────────┐    ┌──────────┐      │  │
│         │           │  │ ffmpeg │    │  yt-dlp  │      │  │
│         │           │  └───┬────┘    └────┬─────┘      │  │
│         │           │      │              │             │  │
│         │           │  Format conversion  URL download  │  │
│         │           └──────────────────────────────────┘  │
│         │                                                  │
│  ┌──────▼───────────────────────────────────────────────┐  │
│  │              GRDB (SQLite + FTS5)                    │  │
│  │  transcripts | metadata | full-text search index     │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              V2: AI Analysis Layer                   │  │
│  │  Claude API / OpenAI API via URLSession              │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────┘

File System:
~/Library/Application Support/Floscrybe/
├── bin/         ← ffmpeg, yt-dlp (downloaded first launch)
├── models/      ← FluidAudio CoreML models (cached)
├── db/          ← floscrybe.sqlite (GRDB)
└── temp/        ← processing audio (auto-cleaned)
```

### Data Flow

```
Input                    Processing              Storage
─────                    ──────────              ───────

Drag file ──┐
            ├──→ Queue ──→ ffmpeg ──→ FluidAudio ──→ GRDB
Paste URL ──┘     │        (if needed)   (Neural     (transcript
                  │                       Engine)     + metadata
                  │                         │         + FTS index)
                  │                         │
                  │    Speaker Dialog ───────┘
                  │    (if diarization ON)
                  │
                  └──→ Progress bar ──→ Sidebar history
```

---

## Risk Register

| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| FluidAudio diarization accuracy is poor | High | Medium | Fall back to WhisperX Python sidecar for diarization only; keep FluidAudio for ASR |
| FluidAudio doesn't handle very long files (2+ hrs) | Medium | Medium | Implement manual chunking — split audio into 30-min segments, transcribe sequentially, merge results |
| yt-dlp breaks on YouTube changes | Medium | High (happens regularly) | Auto-update mechanism checks for new yt-dlp binary on app launch; manual update button in settings |
| ffmpeg/yt-dlp download fails on first launch | Medium | Low | Retry logic with clear error message; manual download instructions as fallback |
| Apple Silicon only excludes Intel Macs | Low | Low | Personal tool — you're on Apple Silicon. If needed later, WhisperKit supports Intel via CPU fallback |
| FluidAudio models are large downloads | Low | Medium | Show download progress on first launch; cache models permanently; only re-download if corrupted |
| macOS sandboxing blocks subprocess execution | Medium | Medium | If distributing: use App Sandbox exception for subprocess execution. For personal use: disable sandbox entirely |
| GRDB database grows large over time | Low | Low | Periodic vacuum; storage info in settings showing DB size; manual cleanup option |

---

## Key Dependencies & Versions

| Dependency | Version | Install Method | License |
|-----------|---------|---------------|---------|
| FluidAudio | 0.12.2+ | SPM | MIT / Apache 2.0 |
| GRDB.swift | 7.10+ | SPM | MIT |
| swift-subprocess | Swift 6.2 stdlib | Built-in | Apache 2.0 |
| ffmpeg | Latest static build | Downloaded to App Support | LGPL 2.1+ |
| yt-dlp | Latest release | Downloaded to App Support | Unlicense |
| macOS | 14.0+ (Sonoma) | Deployment target | — |
| Xcode | 16+ | Development | — |

---

## Research Sources

- [FluidAudio GitHub](https://github.com/FluidInference/FluidAudio)
- [FluidAudio Swift Package Index](https://swiftpackageindex.com/FluidInference/FluidAudio)
- [FluidAudio ASR Getting Started](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/GettingStarted.md)
- [Parakeet TDT v3 CoreML Model](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml)
- [GRDB.swift GitHub](https://github.com/groue/GRDB.swift)
- [SwiftData Considerations (why not SwiftData)](https://fatbobman.com/en/posts/key-considerations-before-using-swiftdata/)
- [swift-subprocess GitHub](https://github.com/swiftlang/swift-subprocess)
- [Swift Process Documentation](https://developer.apple.com/documentation/foundation/process)
- [yt-dlp GitHub](https://github.com/yt-dlp/yt-dlp/)
- [MacYTDL — yt-dlp Mac wrapper reference](https://github.com/section83/MacYTDL)
- [yt-dlp wrapper learnings (binary bundling)](https://arkadiuszchmura.com/posts/things-i-learned-while-building-a-yt-dlp-wrapper/)
- [SwiftUI Drag and Drop](https://www.hackingwithswift.com/quick-start/swiftui/how-to-support-drag-and-drop-in-swiftui)
- [SwiftUI File Drop Example](https://github.com/tp/demo-SwiftUI-File-Drop-Example)
- [NavigationSplitView Documentation](https://developer.apple.com/documentation/swiftui/navigationsplitview)
- [WhisperKit GitHub (alternative considered)](https://github.com/argmaxinc/WhisperKit)
- [speech-swift — MLX diarization (alternative considered)](https://github.com/soniqo/speech-swift)
