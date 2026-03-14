# Contributing to Flowscribe

Thanks for your interest in contributing! Flowscribe is a native macOS transcription app built with Swift and SwiftUI.

## Development Environment

- **macOS 14.0+** (Sonoma)
- **Xcode 16+**
- **Apple Silicon** Mac (required for Neural Engine)
- **XcodeGen** — install with `brew install xcodegen`

## Building from Source

```bash
# Generate the Xcode project
xcodegen generate

# Open in Xcode
open Floscrybe.xcodeproj

# Build and run (Cmd+R)
```

Place `ffmpeg` and `yt-dlp` binaries in `Floscrybe/Resources/Binaries/` before building. See the README for download links.

## Pull Request Process

1. Branch from `main`
2. Make your changes — follow existing Swift/SwiftUI patterns in the codebase
3. Test locally on Apple Silicon
4. Open a PR with a clear description of what changed and why
5. Keep PRs focused — one feature or fix per PR

## Code Style

- Follow the existing Swift and SwiftUI conventions in the project
- Use the design tokens (`Typography`, `ColorTokens`, `Spacing`) for UI consistency
- Keep services in `Services/`, models in `Models/`, views in `Views/`

## Reporting Issues

- Use [GitHub Issues](../../issues) for bug reports and feature requests
- Include your macOS version and Mac model
- For transcription issues, note the file format and approximate duration
- Check existing issues before opening a new one
