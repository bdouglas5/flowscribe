import SwiftUI

enum CachedImagePhase {
    case empty
    case success(Image)
    case failure
}

struct CachedAsyncImage<Content: View>: View {
    let url: URL?
    @ViewBuilder let content: (CachedImagePhase) -> Content

    @State private var phase: CachedImagePhase = .empty

    var body: some View {
        content(phase)
            .task(id: url) {
                guard let url else {
                    phase = .failure
                    return
                }

                if let cached = ThumbnailCache.shared.image(for: url) {
                    phase = .success(Image(nsImage: cached))
                    return
                }

                do {
                    let (data, _) = try await ThumbnailCache.shared.session.data(from: url)
                    if let nsImage = NSImage(data: data) {
                        ThumbnailCache.shared.setImage(nsImage, for: url)
                        phase = .success(Image(nsImage: nsImage))
                    } else {
                        phase = .failure
                    }
                } catch {
                    phase = .failure
                }
            }
    }
}

final class ThumbnailCache: @unchecked Sendable {
    private static var current = ThumbnailCache()

    static var shared: ThumbnailCache {
        current
    }

    let session: URLSession
    private let memoryCache = NSCache<NSURL, NSImage>()

    private init() {
        let config: URLSessionConfiguration

        if StoragePaths.hasAppSupportOverride {
            config = .ephemeral
            config.urlCache = URLCache(
                memoryCapacity: 10 * 1024 * 1024,
                diskCapacity: 0,
                directory: nil
            )
        } else {
            let cacheDir = StoragePaths.appSupport.appendingPathComponent("thumbnailCache")
            let diskCache = URLCache(
                memoryCapacity: 10 * 1024 * 1024,
                diskCapacity: 50 * 1024 * 1024,
                directory: cacheDir
            )
            config = .default
            config.urlCache = diskCache
        }

        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
        memoryCache.countLimit = 200
    }

    static func resetSharedForTesting() {
        current.shutdown()
        current = ThumbnailCache()
    }

    func image(for url: URL) -> NSImage? {
        memoryCache.object(forKey: url as NSURL)
    }

    func setImage(_ image: NSImage, for url: URL) {
        memoryCache.setObject(image, forKey: url as NSURL)
    }

    func shutdown() {
        session.configuration.urlCache?.removeAllCachedResponses()
        session.invalidateAndCancel()
        memoryCache.removeAllObjects()
    }
}
