import SwiftUI

struct SpotifyIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX
        let cy = rect.midY
        let r = min(rect.width, rect.height) / 2

        // Three curved arcs radiating from center, like the Spotify logo
        let arcData: [(radiusFraction: CGFloat, lineWidth: CGFloat)] = [
            (0.85, 0.14),
            (0.58, 0.13),
            (0.32, 0.12),
        ]

        for arc in arcData {
            let arcRadius = r * arc.radiusFraction
            let halfWidth = r * arc.lineWidth / 2

            // Each arc spans about 60 degrees, centered at -60° (upper-right area)
            let startAngle = Angle.degrees(-140)
            let endAngle = Angle.degrees(-40)
            let steps = 20

            // Outer edge
            var outerPoints: [CGPoint] = []
            var innerPoints: [CGPoint] = []

            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let angle = startAngle.radians + t * (endAngle.radians - startAngle.radians)

                let outerR = arcRadius + halfWidth
                let innerR = arcRadius - halfWidth

                outerPoints.append(CGPoint(
                    x: cx + outerR * CoreGraphics.cos(angle),
                    y: cy + outerR * CoreGraphics.sin(angle)
                ))
                innerPoints.append(CGPoint(
                    x: cx + innerR * CoreGraphics.cos(angle),
                    y: cy + innerR * CoreGraphics.sin(angle)
                ))
            }

            // Draw as a filled band
            path.move(to: outerPoints[0])
            for point in outerPoints.dropFirst() {
                path.addLine(to: point)
            }

            // Cap at end
            let endOuter = outerPoints.last!
            let endInner = innerPoints.last!
            let endCapCenter = CGPoint(
                x: (endOuter.x + endInner.x) / 2,
                y: (endOuter.y + endInner.y) / 2
            )
            path.addArc(
                center: endCapCenter,
                radius: halfWidth,
                startAngle: Angle(radians: atan2(endOuter.y - endCapCenter.y, endOuter.x - endCapCenter.x)),
                endAngle: Angle(radians: atan2(endInner.y - endCapCenter.y, endInner.x - endCapCenter.x)),
                clockwise: false
            )

            for point in innerPoints.reversed().dropFirst() {
                path.addLine(to: point)
            }

            // Cap at start
            let startOuter = outerPoints[0]
            let startInner = innerPoints[0]
            let startCapCenter = CGPoint(
                x: (startOuter.x + startInner.x) / 2,
                y: (startOuter.y + startInner.y) / 2
            )
            path.addArc(
                center: startCapCenter,
                radius: halfWidth,
                startAngle: Angle(radians: atan2(startInner.y - startCapCenter.y, startInner.x - startCapCenter.x)),
                endAngle: Angle(radians: atan2(startOuter.y - startCapCenter.y, startOuter.x - startCapCenter.x)),
                clockwise: false
            )

            path.closeSubpath()
        }

        return path
    }
}

struct WaveformIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let barHeights: [CGFloat] = [0.4, 0.7, 1.0, 0.6, 0.3]
        let barCount = CGFloat(barHeights.count)
        let gap = rect.width * 0.08
        let totalGaps = gap * (barCount - 1)
        let barWidth = (rect.width - totalGaps) / barCount
        let cornerRadius = barWidth / 2

        for (index, heightFraction) in barHeights.enumerated() {
            let barHeight = rect.height * heightFraction
            let x = CGFloat(index) * (barWidth + gap)
            let y = (rect.height - barHeight) / 2

            let barRect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
            path.addRoundedRect(in: barRect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
        }

        return path
    }
}

struct SourceIconView: View {
    let category: TranscriptCategory
    var size: CGFloat = 10

    init(transcript: Transcript, size: CGFloat = 10) {
        self.category = TranscriptCategory.category(for: transcript)
        self.size = size
    }

    init(category: TranscriptCategory, size: CGFloat = 10) {
        self.category = category
        self.size = size
    }

    var body: some View {
        switch category {
        case .youtube:
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: size))
                .foregroundStyle(ColorTokens.textMuted)
        case .spotify:
            SpotifyIconShape()
                .fill(ColorTokens.textMuted)
                .frame(width: size + 2, height: size + 2)
        case .localAudio:
            WaveformIconShape()
                .fill(ColorTokens.textMuted)
                .frame(width: size + 2, height: size + 2)
        case .all:
            EmptyView()
        }
    }
}
