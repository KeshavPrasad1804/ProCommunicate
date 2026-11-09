import SwiftUI

/// Animated intro shown right after the launch screen.
///
/// Its first frame is identical to the launch screen (same 120 pt logo, centred, same
/// background), so the hand-over is seamless. Then the logo "speaks" (the waveform bars move),
/// the name and tagline appear, and it fades into the app. About 1.6 s in total; with
/// Reduce Motion on, there's no movement and it's shorter.
struct SplashView: View {
    static let logoSize: CGFloat = 120

    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var speaking = false
    @State private var showTitle = false
    @State private var leaving = false

    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()

            LogoMark(barLevels: speaking ? LogoMark.speakingLevels : LogoMark.restLevels)
                .frame(width: Self.logoSize, height: Self.logoSize)
                .scaleEffect(leaving ? 1.12 : 1)

            VStack(spacing: 6) {
                Text("ProCommunicate")
                    .font(.title.bold())
                Text("Speak with confidence at work")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .offset(y: Self.logoSize / 2 + 56)
            .opacity(showTitle ? 1 : 0)
            .offset(y: showTitle ? 0 : 10)
        }
        .opacity(leaving ? 0 : 1)
        .accessibilityElement(children: .combine)
        .task { await play() }
    }

    private func play() async {
        if reduceMotion {
            withAnimation(.easeIn(duration: 0.2)) { showTitle = true }
            try? await Task.sleep(for: .milliseconds(700))
        } else {
            // The bars bounce a few times, like someone speaking.
            withAnimation(.easeInOut(duration: 0.2).repeatCount(5, autoreverses: true)) { speaking = true }
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.spring(duration: 0.5, bounce: 0.25)) { showTitle = true }
            try? await Task.sleep(for: .milliseconds(1100))
            withAnimation(.easeInOut(duration: 0.2)) { speaking = false }
        }
        withAnimation(.easeIn(duration: 0.3)) { leaving = true }
        try? await Task.sleep(for: .milliseconds(300))
        onFinished()
    }
}

#Preview {
    SplashView {}
}
