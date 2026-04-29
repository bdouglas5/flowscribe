# Scribosaur v2: Gemma 4 Local AI + Real-Time Transcription

**Source:** [[Scribosaur]]
**Created:** 2026-04-08
**Last Updated:** 2026-04-08
**Status:** Active
**Codename:** Fieldnotes

---

## Executive Summary

Scribosaur v2 transforms a personal open-source transcription tool into a closed-source, privacy-first commercial product. Two additions define the upgrade: **Google Gemma 4 E4B** replaces the cloud-dependent Codex CLI for AI analysis, and a new **real-time audio recording mode** lets users transcribe live conversations, meetings, lectures, and sessions as they happen — all running locally on Apple Silicon with zero cloud dependencies.

**Price:** $29 lifetime (no subscription, no API keys, no cloud uploads)
**Target:** Anyone who needs transcription + AI summaries without sending their audio to a server — professionals in therapy, coaching, law, medicine, education, journalism, podcasting, and knowledge work.
**Model:** Google Gemma 4 E4B (4.5B active params, 128K context, native audio input, Apache 2.0 license)
**Distribution:** Signed DMG, closed source, Mac App Store optional

---

## Why Now

1. **Gemma 4 dropped April 2, 2026** — the E4B edge model is the first open model with native audio + vision + text on a laptop-sized footprint. No other open model does this.
2. **MLX Swift 0.31.3 shipped April 1, 2026** — Apple's ML framework for Swift is mature, supports streaming token generation, and Gemma 4 MLX conversions already exist on Hugging Face.
3. **51% of IT leaders have delayed AI adoption due to privacy concerns** — there is massive unmet demand for local-first AI tools.
4. **Cloud AI transcription tools charge $16-30/month** (Otter.ai, Fireflies, etc.) and upload your audio to third-party servers. A $29 one-time-purchase local alternative has no real competitor.
5. **Scribosaur already has ~10,500 lines of working Swift code** — transcription pipeline, speaker diarization, queue system, search, markdown export, prompt templates, and Codex AI integration all exist. The foundation is built.

---

## What Exists Today (v1 — Open Source)

| Feature | Status | Tech |
|---------|--------|------|
| Drag-and-drop transcription | Working | FluidAudio (CoreML/Neural Engine) |
| Speaker diarization with pre-labeling | Working | FluidAudio (PyAnnote CoreML port) |
| YouTube + 1000 site URL download | Working | yt-dlp bundled binary |
| Spotify podcast ingestion | Broken | SpotifyAuthService + SpotifyPodcastService |
| Batch processing queue | Working | QueueManager (FIFO) |
| Searchable transcript history | Working | GRDB + SQLite FTS5 |
| Markdown export + auto-export | Working | ExportService |
| AI analysis (Clean Up, Summary, Action Items) | Working | CodexService → shells out to OpenAI Codex CLI |
| Custom prompt templates | Working | AIPromptTemplate system |
| AI auto-export after transcription | Working | Codex pipeline in AppState |
| Theme system (light/dark) | Working | ColorTokens, Typography, Spacing |
| Podcast RSS feed support | Working | PodcastRSSService |
| First-launch binary downloads | Working | BinaryDownloadService (ffmpeg, yt-dlp) |

**Total codebase:** 60 Swift files, ~10,500 lines
**Architecture:** SwiftUI macOS app, NavigationSplitView layout, GRDB database, subprocess-based external tools

---

## What Changes in v2

### Change 1: Gemma 4 E4B Replaces Codex CLI

The current `CodexService` (751 lines) shells out to the OpenAI Codex CLI binary for all AI operations. This requires users to install Codex CLI separately, sign in with a ChatGPT account, and send transcript text to OpenAI's servers.

**v2 replaces this entirely** with a local `GemmaService` that runs Gemma 4 E4B via MLX Swift. The AI prompt template system, chunking strategies, and auto-export pipeline remain unchanged — only the execution engine swaps.

#### Model Selection

| Model | Active Params | Total Params | Context | Quantization | Download Size | RAM Usage | Use Case |
|-------|--------------|-------------|---------|-------------|---------------|-----------|----------|
| **Gemma 4 E4B (4-bit)** | 4.5B | 8B | 128K | Q4 | ~3-4 GB | ~5-6 GB | Default — runs on any Apple Silicon Mac |
| Gemma 4 E2B (4-bit) | 2.3B | 5.1B | 128K | Q4 | ~2 GB | ~3-4 GB | Lightweight fallback for 8GB Macs |
| Gemma 4 26B MoE (4-bit) | 3.8B | 25.2B | 256K | Q4 | ~14-16 GB | ~16-18 GB | Power users with 32GB+ RAM |

**Default:** Gemma 4 E4B at 4-bit quantization. Best balance of quality, speed, and memory. Users with more RAM can select larger models in Settings.

#### Hugging Face Model Sources (Already Available)

- `unsloth/gemma-4-E4B-it-UD-MLX-4bit` — 4-bit, MLX format
- `unsloth/gemma-4-E4B-it-MLX-8bit` — 8-bit, MLX format
- `unsloth/gemma-4-E2B-it-UD-MLX-4bit` — 2-bit edge, MLX format
- `mlx-community/gemma-4-26b-a4b-it-4bit` — 26B MoE, MLX format

#### Architecture: CodexService → GemmaService

**Current flow (v1):**
```
AIPromptTemplate + Transcript Text
  → CodexService.execute()
  → shells out to `codex exec` binary
  → sends transcript to OpenAI servers
  → returns markdown response
```

**New flow (v2):**
```
AIPromptTemplate + Transcript Text
  → GemmaService.execute()
  → MLX Swift loads Gemma 4 E4B model
  → runs inference locally on Metal GPU
  → streams tokens via AsyncStream
  → returns markdown response
```

**What stays identical:**
- `AIPromptTemplate` model (Clean Up, Summary, Action Items, custom prompts)
- `buildPrompt()` method — same system prompt structure
- `executionStrategy()` — singleShot / chunkMap / chunkReduce based on transcript length
- `transcriptChunks()` — same paragraph-aware chunking at 18K characters
- Auto-export pipeline in `AppState.handleAIAutoExport()`
- `TranscriptAIResult` storage model
- UI for running prompts and displaying results

#### GemmaService API Design

```swift
@Observable
@MainActor
final class GemmaService {
    enum ModelState: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case loading
        case ready
        case error(String)
    }

    private(set) var modelState: ModelState = .notDownloaded
    private(set) var isRunningTask = false
    private(set) var activeTaskPromptTitle: String?
    private(set) var activeTaskStatus: String?
    private(set) var activeTaskTranscriptId: Int64?
    private(set) var generationProgress: String = ""

    // Model lifecycle
    func downloadModel() async throws
    func loadModel() async throws
    func unloadModel()

    // Generation — same interface as CodexService.runTranscriptTask
    func runTranscriptTask(
        _ promptTemplate: AIPromptTemplate,
        transcript: Transcript,
        segments: [TranscriptSegment]
    ) async throws -> String

    // Streaming generation for real-time UI updates
    func streamTranscriptTask(
        _ promptTemplate: AIPromptTemplate,
        transcript: Transcript,
        segments: [TranscriptSegment]
    ) -> AsyncStream<String>
}
```

#### MLX Swift Integration

**SPM dependency:**
```swift
.package(url: "https://github.com/ml-explore/mlx-swift", .upToNextMinor(from: "0.31.3"))
```

**Required products:**
- `MLX` — core tensor operations
- `MLXLLM` — LLM loading and generation (from mlx-swift-examples)
- `MLXRandom` — sampling
- `Transformers` — tokenizer (from `huggingface/swift-transformers`)

**Model storage:**
```
~/Library/Application Support/Scribosaur/
├── models/
│   └── gemma-4-E4B-it-4bit/    (downloaded on first AI use)
│       ├── config.json
│       ├── tokenizer.json
│       ├── model-00001-of-00002.safetensors
│       └── model-00002-of-00002.safetensors
├── db/
│   └── scribosaur.sqlite
├── exports/
└── temp/
```

#### First-Launch Model Download Flow

1. User opens app → transcription works immediately (FluidAudio models download as before)
2. User clicks an AI tool (Summary, Clean Up, etc.) for the first time
3. If Gemma model not downloaded → download dialog appears:
   ```
   ┌────────────────────────────────────────┐
   │  Download AI Model                      │
   │                                         │
   │  Scribosaur needs to download the       │
   │  Gemma 4 AI model to enable local       │
   │  analysis. This is a one-time download. │
   │                                         │
   │  Model: Gemma 4 E4B (4-bit)            │
   │  Size: ~3.5 GB                          │
   │  Storage: ~/Library/Application Support │
   │                                         │
   │  ████████████░░░░░░░░  62%              │
   │  1.8 GB / 3.5 GB — 2 min remaining     │
   │                                         │
   │  [Cancel]                               │
   └────────────────────────────────────────┘
   ```
4. After download, model loads into memory (~5-6 GB unified memory)
5. AI tool executes — all subsequent uses are instant (model stays loaded while app is open)

#### Settings: AI Model Selection

```
┌────────────────────────────────────────────────┐
│  AI Model                                       │
│                                                 │
│  Current: Gemma 4 E4B (4-bit) — 3.5 GB  [✓]   │
│                                                 │
│  Available models:                              │
│  ○ Gemma 4 E2B (4-bit) — 2 GB (lighter, fast) │
│  ● Gemma 4 E4B (4-bit) — 3.5 GB (recommended) │
│  ○ Gemma 4 E4B (8-bit) — 7 GB (higher quality) │
│  ○ Gemma 4 26B MoE (4-bit) — 16 GB (best, 32GB+) │
│                                                 │
│  [Delete Downloaded Models]  Used: 3.5 GB       │
└────────────────────────────────────────────────┘
```

---

### Change 2: Real-Time Audio Recording + Live Transcription

A new "Record" mode lets users capture audio from the Mac's microphone (or any audio input device) and see the transcript build in real-time as people speak.

#### Use Cases

- **Therapy sessions** — therapist records, gets SOAP notes after
- **Meetings** — live captions during, summary after
- **Lectures** — student records, AI extracts key points
- **Interviews** — journalist records, gets structured notes
- **Voice memos** — brain dump into mic, AI cleans it up
- **Coaching calls** — record, extract action items and commitments

#### Recording Architecture

```
Microphone (AVAudioEngine)
  │
  ├──→ Audio Buffer (circular, 30-second chunks)
  │     │
  │     └──→ FluidAudio ASR (transcribe chunk)
  │           │
  │           └──→ Append to live transcript view
  │
  └──→ Full Recording (WAV file to temp)
        │
        └──→ On "Stop": final FluidAudio pass on complete audio
              │
              ├──→ Replace live transcript with final (higher accuracy)
              ├──→ Speaker diarization (if enabled)
              └──→ Save to database + trigger AI auto-export
```

**Two-pass approach:**
1. **Live pass:** Streaming chunks (~30 seconds each) through FluidAudio for real-time display. Lower accuracy but immediate feedback.
2. **Final pass:** After recording stops, the complete audio file is transcribed in one shot for maximum accuracy. The final transcript replaces the live one.

#### Recording UI

**New toolbar button in main window:**
```
┌──────────────────────────────────────────────────────┐
│  Scribosaur                    [🎙 Record] [+] [⚙]  │
├────────────┬─────────────────────────────────────────┤
```

**Recording state:**
```
┌──────────────────────────────────────────────────────┐
│  Scribosaur              ● Recording 00:12:34  [■]   │
├────────────┬─────────────────────────────────────────┤
│            │                                         │
│  Sidebar   │  Live Transcript                        │
│            │                                         │
│            │  "So I was thinking about the project   │
│            │  timeline and whether we need to push    │
│            │  the deadline back. The client mentioned │
│            │  that they want to see a prototype by    │
│            │  next Friday, which feels tight given    │
│            │  where we are with the backend."         │
│            │                                         │
│            │  █ (cursor — new text appears here)      │
│            │                                         │
│            │  ┌─────────────────────────────┐        │
│            │  │  ◉ ━━━━━━━━━━━━━━━━━━━ 🔇  │        │
│            │  │  Audio level meter           │        │
│            │  └─────────────────────────────┘        │
│            │                                         │
│            │  Input: MacBook Pro Microphone ▼         │
└────────────┴─────────────────────────────────────────┘
```

**When recording stops:**
```
┌──────────────────────────────────────────────────────┐
│  Scribosaur                              [🎙] [+] [⚙]│
├────────────┬─────────────────────────────────────────┤
│            │  Finalizing transcript...                │
│            │  ████████████░░░░░░░░  65%              │
│            │                                         │
│            │  (Running final high-accuracy pass)      │
└────────────┴─────────────────────────────────────────┘
```

Then: final transcript replaces live version, speaker diarization runs (if enabled), transcript saved to database, AI auto-export triggers (if configured).

#### Audio Input Configuration

**Settings > Recording:**
```
┌────────────────────────────────────────────────┐
│  Recording                                      │
│                                                 │
│  Input Device: [MacBook Pro Microphone ▼]       │
│                                                 │
│  ☑ Show live transcript while recording         │
│  ☑ Run final accuracy pass after recording      │
│  ☐ Auto-run AI prompt after recording           │
│     Prompt: [Summary ▼]                         │
│                                                 │
│  Audio Quality: [High (48kHz) ▼]                │
│  ☐ Keep original audio file after transcription │
│     Save to: [~/Documents ▼]                    │
└────────────────────────────────────────────────┘
```

#### Technical Implementation

**Audio capture:** `AVAudioEngine` with an input node tap. Configurable sample rate (16kHz for transcription, 48kHz if user wants to keep the audio).

**Streaming transcription chunks:**
```swift
class LiveTranscriptionService {
    private let audioEngine = AVAudioEngine()
    private let transcriptionService: TranscriptionService
    private var chunkBuffer: AVAudioPCMBuffer?
    private var chunkDuration: TimeInterval = 30.0
    private var tempRecordingURL: URL?

    // Start recording + live transcription
    func startRecording(inputDevice: AVAudioDevice?) async throws
        -> AsyncStream<LiveTranscriptUpdate>

    // Stop recording, trigger final pass
    func stopRecording() async throws -> URL  // returns temp audio file

    struct LiveTranscriptUpdate {
        let text: String
        let isPartial: Bool  // true = still processing this chunk
        let chunkIndex: Int
        let timestamp: TimeInterval
    }
}
```

**Chunk pipeline:**
1. `AVAudioEngine` input tap fills a circular buffer
2. Every 30 seconds (or on silence detection via Silero VAD), flush buffer to a temp WAV file
3. Send temp WAV to `TranscriptionService.transcribe()` (same FluidAudio path as file transcription)
4. Emit `LiveTranscriptUpdate` with new text
5. UI appends text to the live transcript view
6. Simultaneously, the full audio is being written to a single WAV file for the final pass

**Silence detection (smarter chunking):**
FluidAudio includes Silero VAD (Voice Activity Detection). Use it to find natural pause points for chunk boundaries instead of hard 30-second cuts. This prevents splitting mid-sentence.

**Final pass:**
After recording stops, the complete WAV file goes through the standard `AudioPipelineService.process()` path — same as a dropped file. The final transcript replaces the live one in the database.

---

### Change 3: iCloud Sync

Sync transcripts and AI results across Mac devices (and eventually iPad/iPhone) via iCloud.

#### Implementation

**Entitlement:** Add `com.apple.developer.icloud-container-identifiers` with container `iCloud.com.scribosaur.app`

**What syncs:**
- SQLite database (transcripts, segments, AI results, settings)
- Exported markdown files (if auto-export targets iCloud Drive)

**What does NOT sync:**
- ML models (too large — each device downloads its own)
- Temp files
- Audio recordings (unless user explicitly saves them)

**Sync mechanism:**
- GRDB database stored in the app's iCloud container when sync is enabled
- `NSUbiquitousKeyValueStore` for lightweight settings sync
- `NSMetadataQuery` to monitor iCloud container changes
- Conflict resolution: last-write-wins at the transcript level (transcripts are append-only in practice)

**Settings toggle:**
```
┌────────────────────────────────────────────────┐
│  Sync                                           │
│                                                 │
│  ☑ Sync transcripts via iCloud                  │
│     Syncing to: bdoug@icloud.com               │
│     Last sync: 2 minutes ago                    │
│     Transcripts synced: 147                     │
│                                                 │
│  Note: AI models are stored locally per device  │
│  and are not synced.                            │
└────────────────────────────────────────────────┘
```

---

### Change 4: Closed Source + Commercial Distribution

#### Licensing

- **v1 (current):** MIT license, open source on GitHub
- **v2:** Closed source, proprietary license
- **Gemma 4:** Apache 2.0 — fully permissible for commercial use, no usage caps (unlike Llama's 700M MAU restriction)
- **FluidAudio:** MIT/Apache 2.0 — no commercial restrictions
- **MLX Swift:** MIT license — no commercial restrictions
- **GRDB:** MIT license — no commercial restrictions

No licensing blockers for a closed-source commercial product.

#### Distribution

**Primary:** Direct download from website as a signed, notarized DMG
- Full control over pricing, updates, and customer relationship
- No 30% App Store cut
- No sandboxing restrictions (important for subprocess calls to ffmpeg/yt-dlp)
- Sparkle framework for auto-updates

**Secondary (optional):** Mac App Store
- Broader discovery
- Must resolve sandboxing: ffmpeg and yt-dlp subprocess calls may require App Sandbox exceptions
- 30% revenue share
- Evaluate after direct sales prove demand

**Payment:** Paddle or LemonSqueezy
- One-time $29 purchase
- License key activation in app
- No subscription management overhead

#### Pricing Strategy

| Tier | Price | What You Get |
|------|-------|-------------|
| **Scribosaur** | $29 one-time | Full app — transcription, recording, AI analysis, iCloud sync, all AI prompt templates, YouTube support |

No tiers. No subscriptions. No free version with limitations. One price, everything included. The entire value prop is "pay once, own it forever, nothing leaves your Mac."

**Why $29 works:**
- Zero marginal cost per user (no API calls, no cloud infrastructure)
- Otter.ai charges $16.99/month — Scribosaur pays for itself in 2 months
- Fireflies charges $19/month — pays for itself in 6 weeks
- Rev charges $29.99/month — pays for itself in 1 month
- Cloud competitors also upload your audio to their servers — Scribosaur never does

---

## Complete v2 Architecture

```
Scribosaur.app (signed DMG, ~250 MB without models)
│
├── SwiftUI Frontend
│   ├── ContentView (NavigationSplitView)
│   ├── SidebarView (transcript history + queue + search)
│   ├── TranscriptDetailView (transcript + AI result pane)
│   ├── RecordingView (NEW — live transcript + audio meter)
│   ├── SettingsView (model selection, recording, sync, export)
│   └── FirstLaunchView (model download progress)
│
├── Services
│   ├── TranscriptionService (FluidAudio CoreML — unchanged)
│   ├── DiarizationService (FluidAudio PyAnnote — unchanged)
│   ├── GemmaService (NEW — MLX Swift, replaces CodexService)
│   ├── LiveTranscriptionService (NEW — AVAudioEngine + streaming)
│   ├── AudioPipelineService (unchanged)
│   ├── QueueManager (unchanged)
│   ├── ExportService (unchanged)
│   ├── FFmpegService (unchanged)
│   ├── YTDLPService (unchanged)
│   ├── iCloudSyncService (NEW)
│   ├── LicenseService (NEW — Paddle/LemonSqueezy activation)
│   └── ModelDownloadService (NEW — Hugging Face model fetcher)
│
├── Models (data)
│   ├── Transcript, TranscriptSegment (unchanged)
│   ├── TranscriptAIResult (unchanged)
│   ├── AIPromptTemplate (unchanged)
│   ├── QueueItem (unchanged)
│   ├── AppSettings (extended — model selection, recording, sync)
│   └── Recording (NEW — in-progress recording state)
│
├── Database
│   ├── DatabaseManager (GRDB — unchanged)
│   └── TranscriptRepository (unchanged)
│
├── Bundled Binaries
│   ├── ffmpeg (arm64)
│   └── yt-dlp
│
└── Downloaded on First Use
    ├── FluidAudio ASR models (~1-3 GB)
    └── Gemma 4 E4B 4-bit (~3-4 GB)
```

---

## Implementation Phases

### Phase 1: GemmaService (Replace Codex) — 1-2 weeks

**Goal:** AI analysis works locally via Gemma 4 with zero code changes outside the service layer.

- [ ] Add MLX Swift + swift-transformers as SPM dependencies
- [ ] Create `GemmaService` with same public API as `CodexService`
- [ ] Implement model download from Hugging Face with progress UI
- [ ] Implement model loading and memory management
- [ ] Port `execute()` from Codex subprocess to MLX inference
- [ ] Port streaming token generation for real-time UI feedback
- [ ] Implement `singleShot` / `chunkMap` / `chunkReduce` strategies using local inference
- [ ] Add model selection in Settings (E2B, E4B, 26B MoE)
- [ ] Update `AppState` to use `GemmaService` instead of `CodexService`
- [ ] Remove `CodexService` and all Codex CLI references
- [ ] Test: Summary, Clean Up, Action Items prompts produce quality output
- [ ] Test: Custom prompt templates work
- [ ] Test: AI auto-export triggers correctly
- [ ] Test: Chunk strategies work for long transcripts (2+ hours)

### Phase 2: Real-Time Recording — 2-3 weeks

**Goal:** Users can record from their mic and see live transcription.

- [ ] Create `LiveTranscriptionService` with `AVAudioEngine` input tap
- [ ] Implement circular buffer → chunk → transcribe pipeline
- [ ] Integrate Silero VAD for intelligent chunk boundaries
- [ ] Build `RecordingView` with live transcript display
- [ ] Add audio level meter visualization
- [ ] Add audio input device selector
- [ ] Implement "Stop" → final accuracy pass → replace live transcript
- [ ] Integrate recording results into existing `AudioPipelineService` flow
- [ ] Add recording settings (input device, quality, auto-AI, keep audio)
- [ ] Handle edge cases: long recordings (3+ hours), microphone disconnection, low disk space
- [ ] Add microphone permission request flow (first use)
- [ ] Test: 1-hour recording with 2 speakers, diarization, AI summary

### Phase 3: iCloud Sync — 1 week

**Goal:** Transcripts available on all user's Macs.

- [ ] Add iCloud container entitlement
- [ ] Move GRDB database to iCloud container when sync enabled
- [ ] Implement `iCloudSyncService` with `NSMetadataQuery` monitoring
- [ ] Add sync settings toggle with status display
- [ ] Handle conflict resolution (last-write-wins)
- [ ] Handle offline → online sync queue
- [ ] Test: Create transcript on MacBook, appears on iMac

### Phase 4: Commercial Polish — 1-2 weeks

**Goal:** Ready to sell.

- [ ] Integrate Paddle or LemonSqueezy SDK for license activation
- [ ] Create license activation flow (enter key → validate → unlock)
- [ ] Build landing page / website
- [ ] Remove MIT license, add proprietary license
- [ ] Code-sign the app with Developer ID
- [ ] Notarize with Apple
- [ ] Build DMG with background image and Applications shortcut
- [ ] Set up Sparkle for auto-updates
- [ ] Fix or cleanly remove broken Spotify features
- [ ] Final QA pass on all features
- [ ] Create product screenshots and demo video

### Phase 5: Ship — 1 week

**Goal:** Live and selling.

- [ ] Soft launch to targeted communities (transcription, productivity, privacy)
- [ ] ProductHunt launch
- [ ] Reddit posts (r/macapps, r/productivity, r/LocalLLaMA, r/therapists)
- [ ] Set up customer support email
- [ ] Monitor crash reports and feedback
- [ ] First patch release based on early feedback

---

## Risk Register

| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| Gemma 4 E4B summary quality insufficient | High | Low | E4B benchmarks well on reasoning; fallback to 26B MoE for power users; prompt engineering can compensate |
| MLX Swift API changes break integration | Medium | Low | Pin to 0.31.x; MLX team maintains backward compat |
| Model download too large for some users (~3.5 GB) | Medium | Medium | Offer E2B (2 GB) as lightweight alternative; show clear progress UI |
| 8 GB Mac runs out of memory (FluidAudio + Gemma loaded) | High | Medium | Lazy-load Gemma only when AI tools used; unload after idle timeout; E2B fallback for 8 GB machines |
| Live transcription latency too high | Medium | Medium | 30-second chunks may feel delayed; reduce to 10-15 seconds if FluidAudio handles it; VAD-based natural breaks help |
| App Store rejection due to subprocess calls | Medium | High | Ship direct DMG first; App Store is optional/secondary |
| iCloud sync conflicts corrupt database | High | Low | WAL mode, last-write-wins, backup before sync migration |
| Spotify features remain broken | Low | High | Remove cleanly from v2 if not fixed; YouTube support covers the URL use case |

---

## Competitive Landscape

| Product | Price | Local? | Live Recording? | AI Summary? | Privacy |
|---------|-------|--------|----------------|-------------|---------|
| **Scribosaur v2** | **$29 one-time** | **Yes — fully local** | **Yes** | **Yes (Gemma 4)** | **Nothing leaves your Mac** |
| Otter.ai | $16.99/mo | No — cloud | Yes | Yes (cloud) | Audio uploaded to servers |
| Fireflies.ai | $19/mo | No — cloud | Yes | Yes (cloud) | Audio uploaded to servers |
| Rev | $29.99/mo | No — cloud | No | Yes (cloud) | Audio uploaded to servers |
| MacWhisper | $30 one-time | Yes — local | No | No | Local |
| Whisper Transcription | $5 | Yes — local | No | No | Local |

**Scribosaur's moat:** Only product that combines local transcription + local AI analysis + live recording + iCloud sync at a one-time price. MacWhisper is the closest competitor but has no AI analysis and no live recording.

---

## Success Metrics

| Metric | Target | Timeframe |
|--------|--------|-----------|
| DMG downloads | 1,000 | First month |
| Paid conversions | 200 ($5,800 revenue) | First month |
| Customer rating | 4.5+ stars | First 50 reviews |
| Support tickets | < 5% of customers | Ongoing |
| Crash-free rate | > 99% | Ongoing |
| Monthly revenue (steady state) | $2,000-5,000 | Month 3-6 |

---

## Future Considerations (Post-v2)

- **iOS/iPad app** — Gemma 4 E2B runs on iPhone 15 Pro+ (8 GB RAM). Record on phone, transcripts sync via iCloud, AI analysis on device. SwiftUI shared codebase makes this feasible.
- **Domain-specific prompt packs** — therapy SOAP notes, legal briefs, coaching session templates, medical chart notes. Could be in-app purchases or included.
- **Gemma 4 native audio** — E4B has native audio input. Currently using FluidAudio for transcription + Gemma for analysis (two-model pipeline). Future: test Gemma 4 doing both in one pass for simpler architecture.
- **Real-time AI annotations** — as the live transcript builds, Gemma highlights key points, flags action items, and identifies topics in real-time (not just after recording stops).
- **Export integrations** — direct export to Notion, Obsidian, Apple Notes, Google Docs.
- **Multi-language support** — FluidAudio + Gemma 4 both support multiple languages. Add language selection for non-English transcription.
- **Collaborative features** — share transcripts via link, comment on segments, assign action items.
