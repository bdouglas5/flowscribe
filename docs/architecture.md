# Scribeosaur

**Source:** None (original concept)
**Created:** 2026-03-07
**Last Updated:** 2026-03-07
**Status:** Active

## Documents

- [[Scribeosaur - SaaS Essentials|SaaS Essentials]]

## Overview

Scribeosaur is a native macOS transcription app — drag in any audio/video file (or paste a YouTube URL), and it transcribes locally using FluidAudio's CoreML models running on Apple's Neural Engine. No cloud services, no subscriptions, no Python. Features include speaker diarization with pre-labeling, a processing queue, transcript history with search, and optional AI analysis via Claude/GPT API keys. Built entirely in Swift/SwiftUI for a minimal, fast, personal-use tool.

---

## Session: 2026-03-07

### Context & Starting Point

Brandon wanted a super simple local Mac app that transcribes any audio/video format. Key drivers: accuracy, speed, ease of use, fully local processing with no paid services. Shares DNA with the [[Scriber-Architecture|Scriber]] project (same problem space — transcription on Mac) but is a completely different product. Scriber is an After Effects plugin for placing word-level markers; Scribeosaur is a standalone general-purpose transcription tool for personal use.

### Key Questions Explored

#### 1. Tech Stack — Pure Swift vs. Python Sidecar

**Question:** Should Scribeosaur use WhisperX with a Python/PyInstaller sidecar (like Scriber) or go fully native?

**Discussion:**
Two viable paths were identified:

- **WhisperX + Python sidecar** — proven approach from Scriber. WhisperX has excellent word-level alignment via CTA, strong speaker diarization via PyAnnote. Downside: ~200MB app + 3GB model download, PyInstaller complexity, two-language stack.
- **FluidAudio (pure Swift/CoreML)** — newer option. Swift package that bundles transcription (Parakeet ASR), speaker diarization (PyAnnote CoreML port), and VAD (Silero) all running on Apple's Neural Engine. No Python, no sidecar, smaller footprint, more power-efficient. macOS 14+, Apple Silicon.

**Conclusion/Decision:**
**FluidAudio** — go fully native. It's more modern, easier to extend later, no cross-language complexity. Single Swift codebase. Models run on the Neural Engine which is power-efficient and keeps CPU/GPU free. If FluidAudio's accuracy proves insufficient, WhisperX remains a fallback, but FluidAudio is the bet.

**Research Findings:**
- FluidAudio API is clean: `AsrModels.downloadAndLoad()` → `AsrManager().transcribe(url)` — few lines of code
- Speaker diarization uses PyAnnote models compiled to CoreML — same underlying tech as WhisperX's diarization
- macOS 14.0+ required, Apple Silicon
- MIT/Apache 2.0 licensed — no restrictions for personal use
- Models download on first run, cached locally

---

#### 2. Audio/Video Format Handling

**Question:** How does "any format" actually work?

**Discussion:**
FluidAudio's `AudioConverter` handles format conversion internally for common formats. For edge cases and video files, ffmpeg is the safety net — converts anything to WAV before passing to FluidAudio.

**Conclusion/Decision:**
- Bundle ffmpeg as a binary inside the app (same approach as Scriber)
- On file drop: check if FluidAudio can handle the format directly → if not, ffmpeg converts to WAV first
- Supported input: mp3, wav, aac, m4a, flac, ogg, opus, mp4, mov, mkv, avi, webm — basically anything ffmpeg can read
- Audio files from video are extracted to a temp directory, transcribed, then deleted

---

#### 3. Core UI & Workflow

**Question:** What does the user experience look like end-to-end?

**Discussion:**
Brandon wants maximum simplicity. Drag and drop onto the window, transcription kicks off automatically. No unnecessary clicks.

**Conclusion/Decision:**

**Main Window Layout:**
```
┌──────────────────────────────────────────────────────┐
│  Scribeosaur                              [+] [⚙]     │
├────────────┬─────────────────────────────────────────┤
│            │                                         │
│  Sidebar   │  Transcript View                        │
│            │                                         │
│  ┌──────┐  │  Speaker 1 (Brandon):                   │
│  │file1 │  │  "Hey, so I was thinking about..."      │
│  │file2 │  │                                         │
│  │file3 │  │  Speaker 2 (Mike):                      │
│  │ ...  │  │  "Yeah, what about it?"                 │
│  └──────┘  │                                         │
│            │                                         │
│            ├─────────────────────────────────────────┤
│            │  [Copy] [Export .md] [Timestamps ☐]     │
└────────────┴─────────────────────────────────────────┘
```

**Workflow:**
1. Drag file(s) onto window (or paste YouTube URL)
2. If "Speaker Detection" is enabled in settings → dialog pops: "How many speakers? Name them."
3. File enters the **queue** with a progress indicator
4. Transcription runs in background on Neural Engine
5. When done, transcript appears in the detail view
6. Sidebar shows file history — click any past transcript to view it
7. Copy button copies transcript to clipboard (plain text or with timestamps, based on toggle)

---

#### 4. Speaker Pre-Labeling UX

**Question:** How does speaker detection work from the user's perspective?

**Discussion:**
Brandon wants to pre-label speakers before transcription starts, not rename them after. A checkbox controls whether speaker detection is active.

**Conclusion/Decision:**

**Flow when "Speaker Detection" checkbox is ON:**
1. File is dragged/added to queue
2. Before transcription starts, a dialog appears:
   ```
   ┌─────────────────────────────────┐
   │  Speaker Setup                  │
   │                                 │
   │  Number of speakers: [2 ▼]     │
   │                                 │
   │  Speaker 1: [Brandon________]  │
   │  Speaker 2: [Mike___________]  │
   │           [+ Add Speaker]      │
   │                                 │
   │  [Cancel]          [Transcribe] │
   └─────────────────────────────────┘
   ```
3. User enters speaker count and names
4. FluidAudio's diarization assigns segments to Speaker 1, Speaker 2, etc.
5. Labels are mapped to the user-provided names in the output

**Flow when "Speaker Detection" checkbox is OFF:**
- File drops straight into the queue, transcription starts immediately
- Output is a single continuous transcript with no speaker labels

---

#### 5. Queue System

**Question:** How does the processing queue work?

**Discussion:**
Brandon wants a general-purpose queue — whether files are dragged in, YouTube URLs are pasted, or multiple items are added at once, everything flows through the same queue.

**Conclusion/Decision:**

**Queue behavior:**
- All transcription jobs go through a single FIFO queue
- Queue is visible in the UI (could be a section above the history in the sidebar, or a small queue panel)
- Each item shows: filename/URL, status (waiting / transcribing / done / error), progress bar
- Multiple files can be queued at once (drag 5 files → 5 queue items)
- Queue processes one at a time (Neural Engine is the bottleneck)
- Completed items move to the transcript history automatically
- Failed items show error state with retry option

**Queue item states:**
- ⏳ Waiting — in queue, not yet started
- 🔄 Transcribing — actively processing (with progress %)
- ✅ Done — transcript available in history
- ❌ Error — failed with message, retry available

---

#### 6. YouTube URL Support

**Question:** How do YouTube links get handled?

**Discussion:**
yt-dlp is the gold standard for YouTube audio extraction. It's a standalone binary that can be bundled inside the app. Swift calls it via `Process` (subprocess).

**Conclusion/Decision:**

**Flow:**
1. User pastes a YouTube URL (via paste button or ⌘V in a URL field)
2. App calls bundled yt-dlp: `yt-dlp -x --audio-format wav -o /tmp/scribeosaur/[title].wav "URL"`
3. yt-dlp downloads and extracts audio to temp directory
4. Audio file enters the normal transcription queue
5. Temp audio is cleaned up after transcription completes
6. Transcript is stored with the video title as the label (pulled from yt-dlp metadata)

**Bundling:**
- yt-dlp binary bundled in `Scribeosaur.app/Contents/Resources/`
- ffmpeg also bundled there (yt-dlp needs it for format conversion)
- Auto-update mechanism for yt-dlp would be nice but is post-MVP

**Note:** yt-dlp supports 1000+ sites beyond YouTube (Vimeo, etc.), so this naturally extends to other platforms for free.

---

#### 7. Transcript Storage & History

**Question:** How are transcripts stored and accessed?

**Discussion:**
Audio/video files are temp-only — deleted after transcription. Transcripts persist locally as the permanent record.

**Conclusion/Decision:**

**Storage:**
- Transcripts stored in `~/Library/Application Support/Scribeosaur/transcripts/`
- Each transcript is a JSON file containing:
  - Original filename or URL
  - Transcription date
  - Speaker labels (if used)
  - Full transcript with timestamps
  - Settings used (model, speaker detection on/off)
- SQLite database for indexing and search across transcripts

**History UI:**
- Sidebar shows all past transcripts, newest first
- Each entry shows: title, date, duration, speaker count
- Search bar at top of sidebar — full-text search across all transcripts
- Click any entry to view the full transcript in the detail pane

**Temp file policy:**
- Audio extracted from video → temp dir → transcribe → delete
- Downloaded YouTube audio → temp dir → transcribe → delete
- Original audio files are NOT modified or moved — only read from their location
- Temp directory: `~/Library/Application Support/Scribeosaur/temp/` — cleared on app launch

---

#### 8. Transcript Output & Copy Formats

**Question:** What does the transcript look like and how is it exported?

**Discussion:**
Brandon wants both clean (no timestamps) and timestamped views, toggled in the UI. Plus markdown export.

**Conclusion/Decision:**

**Clean format (timestamps OFF):**
```
Brandon: Hey, so I was thinking about the van build and what we need to finish.

Mike: Yeah, what about it? I was looking at the electrical panel yesterday.

Brandon: Right, so the shore power hookup is the last big piece.
```

**Timestamped format (timestamps ON):**
```
[00:01:12] Brandon: Hey, so I was thinking about the van build and what we need to finish.

[00:01:18] Mike: Yeah, what about it? I was looking at the electrical panel yesterday.

[00:01:24] Brandon: Right, so the shore power hookup is the last big piece.
```

**No speakers (speaker detection OFF):**
```
Hey, so I was thinking about the van build and what we need to finish. Yeah, what about it? I was looking at the electrical panel yesterday. Right, so the shore power hookup is the last big piece.
```

**Copy button:** Copies whatever format is currently displayed (respects timestamp toggle and speaker labels)

**Export .md:** Saves a markdown file with:
```markdown
# [Title]
**Date:** 2026-03-07
**Duration:** 12:34
**Speakers:** Brandon, Mike

---

[Transcript content matching current display format]
```

Export location: user-selected via save dialog (default to Downloads)

---

#### 9. Settings & Configuration

**Question:** What lives in the settings panel?

**Conclusion/Decision:**

**Settings (⚙ gear icon):**
- **Speaker Detection** — global toggle (on/off), default OFF
- **Default Timestamp Display** — on/off, default OFF
- **Model Selection** — which ASR model to use (FluidAudio may offer size options)
- **API Keys** (nice-to-have, V2):
  - Claude API key field
  - OpenAI API key field
- **Storage** — show transcript database size, clear temp files, clear all transcripts
- **About** — version, credits

---

#### 10. AI Integration (V2 / Nice-to-Have)

**Question:** How would the optional Claude/GPT integration work?

**Discussion:**
Not MVP, but the vision is clear: once you have a transcript, you can run AI analysis on it.

**Conclusion/Decision (for future):**

**Concept:**
- After transcription completes, an "Analyze" button appears (only if an API key is configured)
- Click → choose from preset prompts or write custom:
  - "Summarize this conversation"
  - "Extract action items"
  - "Extract key decisions"
  - "Custom prompt..."
- AI response appears below the transcript in an "Analysis" section
- Analysis is saved alongside the transcript in the JSON store

**Implementation:**
- Direct API calls to Claude or OpenAI (whichever key is configured)
- Transcript text sent as context with the chosen prompt
- No streaming needed — just show a spinner and the result

---

#### 11. Spotify Support (V2 / Exploration Needed)

**Question:** Can we pull Spotify audio for transcription?

**Research Findings:**
Spotify doesn't have a clean open-source extraction path. Options are:
- **Podcast RSS feeds** — most Spotify podcasts have public RSS feeds with direct MP3 download links. This is the cleanest approach: paste the podcast RSS URL, download episodes directly.
- **Third-party tools** — sketchy, break often, DRM concerns
- **Spotify API** — only provides 30-second previews, not full tracks

**Conclusion/Decision:**
Park Spotify for V2. The RSS feed approach for podcasts is viable and clean — could add a "Podcast Feed" feature where you paste an RSS URL and it lists episodes for download + transcription. Music transcription from Spotify is not feasible without DRM circumvention.

---

### Tech Stack Summary

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| App framework | Swift / SwiftUI | Native macOS, minimal footprint |
| Window layout | NavigationSplitView | Sidebar + detail, built-in |
| ASR (transcription) | FluidAudio (CoreML) | Local, Neural Engine, no Python |
| Speaker diarization | FluidAudio (PyAnnote CoreML) | Same package, same engine |
| VAD | FluidAudio (Silero CoreML) | Included in FluidAudio |
| Audio conversion | ffmpeg (bundled binary) | Universal format support |
| YouTube extraction | yt-dlp (bundled binary) | Gold standard, 1000+ sites |
| Transcript storage | SQLite + JSON files | Fast search, portable data |
| File dropping | SwiftUI `.onDrop` / `DropDelegate` | Native drag-and-drop |
| AI analysis (V2) | Claude API / OpenAI API | Direct HTTP calls |
| Min macOS | 14.0 (Sonoma) | FluidAudio requirement |
| Architecture | Apple Silicon only | Neural Engine required |

---

### MVP Feature Set

- [ ] SwiftUI app with sidebar + transcript detail layout
- [ ] Drag-and-drop file input (any audio/video format)
- [ ] ffmpeg conversion for unsupported formats
- [ ] FluidAudio transcription on Neural Engine
- [ ] Progress bar during transcription
- [ ] Processing queue (FIFO, one-at-a-time)
- [ ] Speaker diarization with pre-labeling dialog
- [ ] Speaker detection toggle (global setting)
- [ ] Timestamp toggle in transcript view
- [ ] Copy button (respects current display format)
- [ ] Export as .md file
- [ ] YouTube URL paste → yt-dlp download → transcribe
- [ ] Transcript history in sidebar with search
- [ ] SQLite-backed transcript database
- [ ] Temp file cleanup (audio deleted after transcription)
- [ ] Settings panel (speaker detection, timestamps, model, storage)

### Post-MVP / V2

- [ ] Claude/OpenAI API key integration for transcript analysis
- [ ] Preset analysis prompts (summarize, extract action items, etc.)
- [ ] Custom analysis prompts
- [ ] Podcast RSS feed support (paste feed URL → list episodes → download + transcribe)
- [ ] yt-dlp auto-update mechanism
- [ ] Bulk URL paste (multiple YouTube links at once)
- [ ] Transcript export as SRT/VTT (subtitle formats)
- [ ] Keyboard shortcuts (⌘V to paste URL, ⌘C to copy transcript)
- [ ] Dark/light mode theming
- [ ] Transcript editing (fix errors inline)

---

### Insights & Decisions

- **FluidAudio over WhisperX** — going fully native eliminates Python entirely. Same underlying diarization tech (PyAnnote) but compiled to CoreML. Cleaner, smaller, more future-proof.
- **Queue-first architecture** — everything flows through one queue. Files, URLs, future podcast feeds — same pipeline. This makes the app dead simple to extend.
- **Temp-only audio** — transcripts are the permanent artifact, not audio files. Saves disk space and keeps things clean.
- **Speaker pre-labeling over post-labeling** — more intentional. You know who's talking before you transcribe, so label upfront. Diarization assigns segments to numbered speakers, app maps numbers to names.
- **yt-dlp gives multi-platform for free** — bundling yt-dlp means YouTube, Vimeo, and 1000+ other sites work out of the box. No need to build platform-specific integrations.
- **Markdown export targets this vault** — `.md` export means transcripts can drop straight into Obsidian for linking and reference.

---

### Open Questions

- [ ] FluidAudio model sizes — does it offer small/medium/large variants? Affects first-run download time and accuracy tradeoff.
- [ ] How does FluidAudio handle very long files (2+ hours)? Does it chunk internally or need manual segmentation?
- [ ] yt-dlp binary size — how much does bundling it add to the app?
- [ ] Should the app live in the menubar as well, or just be a regular window app?
- [ ] Auto-launch on login — desirable or unnecessary for a personal tool?
- [ ] Transcript sharing — any desire to export/share beyond copy and .md export?

### Next Steps

- [ ] Set up Xcode project: SwiftUI macOS app, add FluidAudio via SPM
- [ ] Prototype the drag-and-drop → transcribe flow with FluidAudio
- [ ] Build the sidebar + transcript detail view with NavigationSplitView
- [ ] Bundle ffmpeg and yt-dlp binaries, test subprocess calls from Swift
- [ ] Implement the queue system with progress tracking
- [ ] Test speaker diarization with FluidAudio on a multi-speaker audio file
