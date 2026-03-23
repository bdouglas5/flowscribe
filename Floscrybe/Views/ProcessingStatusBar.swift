import SwiftUI

struct ProcessingStatusBar: View {
    let item: QueueItem

    @State private var flavorIndex = 0
    @State private var showFlavor = true

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)

            Text(item.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ColorTokens.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(-1)

            Text(item.statusLabel)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(ColorTokens.textMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(ColorTokens.backgroundFloat, in: Capsule())
                .fixedSize()
                .layoutPriority(1)

            if item.status == .downloading, let speed = item.downloadSpeed {
                Text(speed)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(ColorTokens.textMuted)
                    .fixedSize()
                    .layoutPriority(1)
                    .transition(.opacity)
            }

            Text(currentFlavorWord)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(ColorTokens.textMuted)
                .opacity(showFlavor ? 0.8 : 0)
                .frame(width: 130, alignment: .trailing)
                .animation(.easeInOut(duration: 0.25), value: showFlavor)
                .fixedSize()
                .layoutPriority(1)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 4)
        .onAppear {
            flavorIndex = randomIndexForStatus(item.status)
            startFlavorRotation()
        }
        .onChange(of: item.status) { _, newStatus in
            flavorIndex = randomIndexForStatus(newStatus)
        }
    }

    private var currentFlavorWord: String {
        let words = Self.flavorWordsByStatus[item.status] ?? Self.flavorWordsByStatus[.transcribing]!
        guard !words.isEmpty else { return "" }
        return words[flavorIndex % words.count]
    }

    private func startFlavorRotation() {
        Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
            withAnimation(.easeOut(duration: 0.15)) {
                showFlavor = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let words = Self.flavorWordsByStatus[item.status] ?? Self.flavorWordsByStatus[.transcribing]!
                guard !words.isEmpty else { return }
                flavorIndex = (flavorIndex + Int.random(in: 1...3)) % words.count
                withAnimation(.easeIn(duration: 0.15)) {
                    showFlavor = true
                }
            }
        }
    }

    private func randomIndexForStatus(_ status: QueueItem.Status) -> Int {
        let words = Self.flavorWordsByStatus[status] ?? Self.flavorWordsByStatus[.transcribing]!
        guard !words.isEmpty else { return 0 }
        return Int.random(in: 0..<words.count)
    }

    // MARK: - Flavor Words by Status

    private static let flavorWordsByStatus: [QueueItem.Status: [String]] = [
        .resolving: [
            "Locating signal...",
            "Finding the source...",
            "Tracing the wire...",
            "Following the trail...",
            "Hunting down audio...",
            "Sniffing packets...",
            "Pinging the void...",
            "Resolving mysteries...",
            "Untangling URLs...",
            "Connecting dots...",
            "Opening channels...",
            "Tuning in...",
            "Acquiring target...",
            "Zeroing in...",
            "Establishing link...",
        ],

        .downloading: [
            "Pulling bytes...",
            "Fetching audio...",
            "Catching waves...",
            "Reeling it in...",
            "Downloading goodness...",
            "Sipping the stream...",
            "Buffering dreams...",
            "Absorbing data...",
            "Inhaling content...",
            "Vacuuming bits...",
            "Downloading vibes...",
            "Grabbing the goods...",
            "Streaming in...",
            "Loading cargo...",
            "Receiving signal...",
            "Hauling packets...",
            "Wrangling bandwidth...",
            "Guzzling data...",
            "Piping it down...",
            "Tunneling through...",
            "Riding the tubes...",
            "Surfing the wire...",
            "Packet by packet...",
            "Byte by byte...",
            "Draining the source...",
            "Tapping the feed...",
            "Opening floodgates...",
            "Caching the moment...",
            "Hoarding audio...",
            "Stockpiling sound...",
            "Collecting samples...",
            "Harvesting audio...",
            "Gathering fragments...",
            "Assembling pieces...",
            "Stitching packets...",
            "Weaving the stream...",
            "Spinning up pipes...",
            "Channeling audio...",
            "Routing signals...",
            "Bridging the gap...",
            "Leeching politely...",
            "Summoning bytes...",
            "Conjuring audio...",
            "Materializing sound...",
            "Importing goodness...",
            "Teleporting data...",
            "Beaming it down...",
            "Downloading magic...",
            "Ingesting media...",
            "Consuming the feed...",
            "Devouring content...",
            "Nibbling packets...",
            "Snacking on bits...",
            "Feasting on data...",
            "Digesting stream...",
            "Siphoning audio...",
            "Funneling bytes...",
            "Cascading data...",
            "Flowing downstream...",
            "Trickling in...",
            "Pouring it down...",
            "Filling the bucket...",
            "Loading the cargo...",
            "Packing it in...",
            "Stacking frames...",
            "Queuing segments...",
            "Buffering ahead...",
            "Preloading audio...",
            "Warming the cache...",
            "Priming the pipe...",
            "Charging buffers...",
            "Energizing download...",
            "Accelerating bits...",
            "Turbo downloading...",
            "Warp speed bytes...",
            "Ludicrous speed...",
            "Almost streaming...",
            "Transfer in flight...",
            "Bits are flying...",
            "Downloading furiously...",
            "Maximum bandwidth...",
        ],

        .converting: [
            "Crunching audio...",
            "Reshaping waves...",
            "Alchemizing sound...",
            "Transmuting formats...",
            "Massaging samples...",
            "Wrangling codecs...",
            "Squeezing frequencies...",
            "Blending channels...",
            "Smoothing edges...",
            "Normalizing chaos...",
            "Flattening curves...",
            "Cooking audio...",
            "Baking waveforms...",
            "Simmering samples...",
            "Distilling sound...",
            "Refining audio...",
            "Polishing signal...",
            "Filtering noise...",
            "Sculpting waves...",
            "Prepping the mix...",
        ],

        .transcribing: [
            "Listening closely...",
            "Decoding speech...",
            "Parsing phonemes...",
            "Catching every word...",
            "Reading the airwaves...",
            "Translating vibrations...",
            "Interpreting sound...",
            "Unscrambling voices...",
            "Capturing syllables...",
            "Mining sentences...",
            "Extracting meaning...",
            "Weaving words...",
            "Stitching phrases...",
            "Spelling it out...",
            "Typing furiously...",
            "Transcribing magic...",
            "Scribbling notes...",
            "Dictation mode...",
            "Word by word...",
            "Sentence surfing...",
            "Riding the waveform...",
            "Neural crunching...",
            "Pattern matching...",
            "Model thinking...",
            "Attention spanning...",
            "Token by token...",
            "Softmaxing hard...",
            "Beam searching...",
            "Decoding layers...",
            "Inference engine go...",
            "Whisper working...",
            "Acoustic modeling...",
            "Spectral analysis...",
            "Fourier transforming...",
            "Frequency hopping...",
            "Signal processing...",
            "Amplitude decoding...",
            "Waveform walking...",
            "Mel spectrogram go...",
            "Feature extracting...",
            "Embedding vectors...",
            "Attention is all...",
            "Weights activating...",
            "Neurons firing...",
            "Layers propagating...",
            "Gradients flowing...",
            "Tensors crunching...",
            "Matrix multiplying...",
            "Probabilities rising...",
            "Logits computing...",
            "Vocabulary scanning...",
            "Context absorbing...",
            "Grammar resolving...",
            "Punctuation placing...",
            "Sentences forming...",
            "Paragraphs emerging...",
            "Meaning crystallizing...",
            "Words materializing...",
            "Language decoding...",
            "Speech to text...",
            "Audio to words...",
            "Sound to meaning...",
            "Vibrations to text...",
            "Noise to knowledge...",
            "Chaos to clarity...",
            "Babble to prose...",
            "Murmurs to words...",
            "Echoes to text...",
            "Whispers to print...",
            "Voices to pages...",
            "Talk to type...",
            "Hear and write...",
            "Listen and learn...",
            "Perceive and pen...",
            "Comprehending audio...",
            "Absorbing dialogue...",
            "Digesting speech...",
            "Processing language...",
            "Analyzing utterances...",
            "Deciphering accents...",
            "Recognizing words...",
            "Identifying phrases...",
            "Cataloging speech...",
            "Indexing dialogue...",
            "Mapping the talk...",
            "Charting the words...",
            "Documenting speech...",
            "Recording insights...",
            "Preserving words...",
            "Archiving dialogue...",
            "Capturing thoughts...",
            "Bottling conversation...",
            "Distilling speech...",
            "Refining transcript...",
            "Polishing prose...",
            "Perfecting output...",
            "Finalizing text...",
            "Nearly there...",
            "Still crunching...",
            "Keep going...",
            "Patience rewarded...",
        ],

        .diarizing: [
            "Who said what?...",
            "Sorting voices...",
            "Identifying speakers...",
            "Matching voiceprints...",
            "Clustering speech...",
            "Untangling speakers...",
            "Voice fingerprinting...",
            "Labeling voices...",
            "Distinguishing tones...",
            "Mapping conversations...",
            "Assigning speakers...",
            "Separating voices...",
            "Profiling acoustics...",
            "Recognizing patterns...",
            "Attributing quotes...",
            "Tagging speakers...",
            "Analyzing cadence...",
            "Detecting turns...",
            "Segmenting dialogue...",
            "Almost there...",
        ],
    ]
}
