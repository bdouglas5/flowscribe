import SwiftUI

enum ThumbnailShape {
    case rounded
    case circle
}

struct ThumbnailView: View {
    let thumbnailURL: String?
    let category: TranscriptCategory
    var size: CGFloat = 32
    var shape: ThumbnailShape = .rounded

    var body: some View {
        if let urlString = thumbnailURL, let url = URL(string: urlString) {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .empty, .failure:
                    fallbackIcon
                }
            }
            .frame(width: size, height: size)
            .clipShape(clipShapeView)
        } else {
            fallbackIcon
        }
    }

    private var clipShapeView: AnyShape {
        switch shape {
        case .rounded:
            AnyShape(RoundedRectangle(cornerRadius: size * 0.1))
        case .circle:
            AnyShape(Circle())
        }
    }

    private var fallbackIcon: some View {
        Group {
            switch shape {
            case .rounded:
                RoundedRectangle(cornerRadius: size * 0.1)
                    .fill(ColorTokens.backgroundFloat)
                    .frame(width: size, height: size)
                    .overlay {
                        SourceIconView(category: category, size: size * 0.4)
                    }
            case .circle:
                Circle()
                    .fill(ColorTokens.backgroundFloat)
                    .frame(width: size, height: size)
                    .overlay {
                        SourceIconView(category: category, size: size * 0.4)
                    }
            }
        }
    }
}
