import SwiftUI

/// The ProCommunicate logo: a speech bubble with a voice waveform on a blue tile.
/// Pure SwiftUI (no UIKit) so the same drawing renders the app icon, the launch image
/// (via tools/RenderBrand.swift on the Mac) and the animated intro inside the app.
struct LogoMark: View {
    enum Style {
        /// Rounded tile, for use inside the app and on the launch screen.
        case tile
        /// Square, edge to edge, for the app icon (iOS applies its own rounded mask).
        case fullBleed
    }

    var style: Style = .tile
    /// Height of each waveform bar, 0…1. Animating these makes the logo "speak".
    var barLevels: [CGFloat] = LogoMark.restLevels

    static let restLevels: [CGFloat] = [0.38, 0.68, 1.0, 0.68, 0.38]
    static let speakingLevels: [CGFloat] = [0.80, 0.42, 0.62, 1.0, 0.55]

    static let gradientTop = Color(red: 0.24, green: 0.55, blue: 1.00)     // #3D8CFF
    static let gradientBottom = Color(red: 0.15, green: 0.30, blue: 0.80)  // #264DCC
    static let barColor = Color(red: 0.16, green: 0.38, blue: 0.86)

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                background(size: size)
                bubble(size: size)
            }
            .frame(width: size, height: size)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("ProCommunicate")
    }

    @ViewBuilder
    private func background(size: CGFloat) -> some View {
        let gradient = LinearGradient(colors: [Self.gradientTop, Self.gradientBottom],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
        switch style {
        case .tile:
            RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous).fill(gradient)
        case .fullBleed:
            Rectangle().fill(gradient)
        }
    }

    private func bubble(size: CGFloat) -> some View {
        let bubbleWidth = size * 0.64
        let bubbleHeight = size * 0.50
        let barWidth = size * 0.062
        let maxBar = bubbleHeight * 0.58
        return ZStack {
            SpeechBubble(tailSize: size * 0.11)
                .fill(.white)
                .shadow(color: .black.opacity(0.18), radius: size * 0.03, y: size * 0.012)
            HStack(spacing: barWidth * 0.75) {
                ForEach(barLevels.indices, id: \.self) { index in
                    Capsule()
                        .fill(Self.barColor)
                        .frame(width: barWidth, height: max(barWidth, maxBar * barLevels[index]))
                }
            }
            .frame(height: maxBar)
        }
        .frame(width: bubbleWidth, height: bubbleHeight)
        .offset(y: -size * 0.03)
    }
}

/// A rounded speech bubble with a small tail at the bottom left.
struct SpeechBubble: Shape {
    var tailSize: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = rect.height * 0.32
        let body = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        // Start the tail where the bottom edge is already flat, overlap it into the bubble,
        // and merge the two outlines so there is no seam or notch.
        let tailX = rect.minX + radius + tailSize * 0.15
        let overlap = tailSize * 0.6
        var tail = Path()
        tail.move(to: CGPoint(x: tailX, y: rect.maxY - overlap))
        tail.addLine(to: CGPoint(x: tailX, y: rect.maxY))
        tail.addLine(to: CGPoint(x: tailX - tailSize * 0.45, y: rect.maxY + tailSize))
        tail.addLine(to: CGPoint(x: tailX + tailSize * 1.05, y: rect.maxY))
        tail.addLine(to: CGPoint(x: tailX + tailSize * 1.05, y: rect.maxY - overlap))
        tail.closeSubpath()
        return body.union(tail)
    }
}

#Preview {
    HStack(spacing: 24) {
        LogoMark().frame(width: 120)
        LogoMark(barLevels: LogoMark.speakingLevels).frame(width: 120)
    }
    .padding()
}
