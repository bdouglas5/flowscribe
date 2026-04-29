import Foundation

enum FFmpegService {
    static let supportedAudioExtensions: Set<String> = [
        "mp3", "wav", "aac", "m4a", "flac", "ogg", "opus", "wma", "aiff"
    ]

    static let supportedVideoExtensions: Set<String> = [
        "mp4", "mov", "mkv", "avi", "webm", "wmv", "flv", "m4v"
    ]

    static var allSupportedExtensions: Set<String> {
        supportedAudioExtensions.union(supportedVideoExtensions)
    }

    static func isSupported(_ url: URL) -> Bool {
        allSupportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func needsConversion(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        // WAV files can go directly to FluidAudio
        return ext != "wav"
    }

    static func convertToWAV(input: URL) async throws -> URL {
        let outputName = input.deletingPathExtension().lastPathComponent + "_converted.wav"
        let outputURL = StoragePaths.temp.appendingPathComponent(outputName)

        let fm = FileManager.default
        if fm.fileExists(atPath: outputURL.path) {
            try fm.removeItem(at: outputURL)
        }

        _ = try await SubprocessRunner.runChecked(
            executable: StoragePaths.ffmpegBinary,
            arguments: [
                "-i", input.path,
                "-vn",                   // no video
                "-acodec", "pcm_s16le",  // PCM 16-bit
                "-ar", "16000",          // 16kHz sample rate
                "-ac", "1",              // mono
                "-y",                    // overwrite
                outputURL.path
            ]
        )

        return outputURL
    }

    static func audioDuration(of url: URL) async throws -> Double {
        let output = try await SubprocessRunner.run(
            executable: StoragePaths.ffmpegBinary,
            arguments: [
                "-i", url.path,
                "-hide_banner",
                "-f", "null", "-"
            ]
        )
        guard output.exitCode == 0 else {
            let message = output.stderr.isEmpty ? output.stdout : output.stderr
            throw SubprocessError.executionFailed(message, output.exitCode)
        }

        let combinedOutput = [output.stdout, output.stderr].joined(separator: "\n")

        // ffmpeg reports duration to stderr, not stdout.
        if let range = combinedOutput.range(
            of: #"Duration: (\d+):(\d+):(\d+(?:\.\d+)?)"#,
            options: .regularExpression
        ) {
            let match = String(combinedOutput[range])
            let components = match
                .replacingOccurrences(of: "Duration: ", with: "")
                .split(separator: ":")
            if components.count == 3,
               let hours = Double(components[0]),
               let minutes = Double(components[1]),
               let seconds = Double(components[2]) {
                return (hours * 3600) + (minutes * 60) + seconds
            }
        }
        return 0
    }
}
