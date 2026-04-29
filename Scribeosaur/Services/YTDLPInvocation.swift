import Foundation

struct YTDLPRequest: Equatable {
    let arguments: [String]
    let environment: [String: String]
    let timeout: TimeInterval?
}

enum YTDLPInvocation {
    enum Command: Equatable {
        case metadata(url: String)
        case title(url: String)
        case collection(url: String, dateAfter: String?)
        case downloadAudio(url: String, outputTemplate: String)

        var logLabel: String {
            switch self {
            case .metadata:
                return "metadata lookup"
            case .title:
                return "title lookup"
            case .collection:
                return "collection lookup"
            case .downloadAudio:
                return "audio download"
            }
        }
    }

    static func makeRequest(
        for command: Command,
        environment baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> YTDLPRequest {
        var arguments = baseArguments()
        let timeout: TimeInterval?

        switch command {
        case .metadata(let url):
            arguments += [
                "--dump-single-json",
                "--no-playlist",
                "--no-download",
                "--no-warnings",
                url
            ]
            timeout = 90

        case .title(let url):
            arguments += [
                "--get-title",
                "--no-playlist",
                "--no-warnings",
                url
            ]
            timeout = 90

        case .collection(let url, let dateAfter):
            arguments += ["--flat-playlist"]
            if let dateAfter, !dateAfter.isEmpty {
                arguments += ["--dateafter", dateAfter]
            }
            arguments += ["--dump-single-json", "--no-warnings", url]
            timeout = 90

        case .downloadAudio(let url, let outputTemplate):
            arguments += [
                "-x",
                "--audio-format", "wav",
                "--no-playlist",
                "--newline",
                "-o", outputTemplate,
                url
            ]
            timeout = nil
        }

        return YTDLPRequest(
            arguments: arguments,
            environment: managedEnvironment(base: baseEnvironment),
            timeout: timeout
        )
    }

    private static func baseArguments() -> [String] {
        [
            "--ffmpeg-location", StoragePaths.bin.path,
            "--no-js-runtimes",
            "--js-runtimes", "deno:\(StoragePaths.denoBinary.path)"
        ]
    }

    private static func managedEnvironment(base: [String: String]) -> [String: String] {
        var environment = base
        let currentPath = base["PATH"] ?? ""
        let managedPath = StoragePaths.bin.path
        environment["PATH"] = currentPath.isEmpty ? managedPath : "\(managedPath):\(currentPath)"
        return environment
    }
}
