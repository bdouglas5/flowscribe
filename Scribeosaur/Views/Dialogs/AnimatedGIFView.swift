import AppKit
import ImageIO
import SwiftUI

enum StartupMascotAsset {
    static let resourceName = "ScribasaurDance"
    static let resourceExtension = "gif"
    static let resourceSubdirectory = "Startup"

    enum Content {
        case animated(NSImage)
        case staticFrame(NSImage)
        case unavailable
    }

    static func resourceURL() -> URL? {
        let candidateURLs = [
            StoragePaths.bundledResource(
                named: resourceName,
                withExtension: resourceExtension,
                subdirectory: resourceSubdirectory
            ),
            StoragePaths.bundledResource(
                named: resourceName,
                withExtension: resourceExtension
            ),
        ]

        return candidateURLs.compactMap { $0 }.first {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

    static func startupSubdirectoryResourceURL() -> URL? {
        StoragePaths.bundledResource(
            named: resourceName,
            withExtension: resourceExtension,
            subdirectory: resourceSubdirectory
        )
    }

    static func rootResourceURL() -> URL? {
        StoragePaths.bundledResource(
            named: resourceName,
            withExtension: resourceExtension
        )
    }

    static func loadContent(reduceMotion: Bool) -> Content {
        guard let url = resourceURL(),
              let data = try? Data(contentsOf: url) else {
            return .unavailable
        }

        return loadContent(from: data, reduceMotion: reduceMotion)
    }

    static func loadContent(from data: Data, reduceMotion: Bool) -> Content {
        let posterImage = firstFrameImage(from: data)

        if reduceMotion {
            return posterImage.map(Content.staticFrame) ?? .unavailable
        }

        if let animatedImage = NSImage(data: data) {
            return .animated(animatedImage)
        }

        return posterImage.map(Content.staticFrame) ?? .unavailable
    }

    static func firstFrameImage(from data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }
}

struct AnimatedGIFView: NSViewRepresentable {
    let image: NSImage
    let animates: Bool

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = animates
        imageView.wantsLayer = true
        imageView.layer?.masksToBounds = true
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.image = image
        nsView.animates = animates
    }
}
