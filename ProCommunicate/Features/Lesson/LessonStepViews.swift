import SwiftData
import SwiftUI

// MARK: - Shared pieces

/// Plays a phrase aloud; shows a waveform while it's speaking.
struct SpeakButton: View {
    let text: String
    var slow = false
    var prominent = false

    private var speaker: Speaker { Speaker.shared }

    var body: some View {
        let isPlaying = speaker.speakingText == text && speaker.speakingSlow == slow
        Button {
            if isPlaying { speaker.stop() } else { speaker.speak(text, slow: slow) }
        } label: {
            Label(slow ? "Slow" : "Listen",
                  systemImage: isPlaying ? "waveform" : (slow ? "tortoise.fill" : "speaker.wave.2.fill"))
                .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(prominent ? .large : .regular)
        .accessibilityLabel(slow ? "Play slowly" : "Play")
    }
}

/// A small heading over a question, with an optional Tamil line.
struct StepTitle: View {
    let kicker: String
    let text: String
    var tamil: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kicker.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.tint)
            Text(text)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if let tamil {
                Text(tamil)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Answer options as large tappable cards; colours show right/wrong after checking.
struct OptionsList: View {
    let options: [String]
    @Binding var selection: String?
    let result: StepResult?
    let locked: Bool

    @State private var order: [String] = []

    var body: some View {
        VStack(spacing: 12) {
            ForEach(order.isEmpty ? options : order, id: \.self) { option in
                Button {
                    if !locked { selection = option }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: icon(for: option))
                            .font(.title3)
                            .foregroundStyle(tint(for: option))
                        Text(option)
                            .font(.body)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(tint(for: option), lineWidth: borderWidth(for: option)))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .onAppear { if order.isEmpty { order = options.shuffled() } }
    }

    private func isAnswer(_ option: String) -> Bool {
        guard let result else { return false }
        return AnswerChecker.isCorrect(option, expected: result.expected)
    }

    private func icon(for option: String) -> String {
        if result != nil {
            if isAnswer(option) { return "checkmark.circle.fill" }
            if option == selection { return "xmark.circle.fill" }
        }
        return option == selection ? "largecircle.fill.circle" : "circle"
    }

    private func tint(for option: String) -> Color {
        if result != nil {
            if isAnswer(option) { return .green }
            if option == selection { return .orange }
            return .secondary.opacity(0.3)
        }
        return option == selection ? .accentColor : .secondary.opacity(0.3)
    }

    private func borderWidth(for option: String) -> CGFloat {
        (option == selection || (result != nil && isAnswer(option))) ? 2 : 1
    }
}

/// Shown under a checked answer.
struct FeedbackPanel: View {
    let result: StepResult
    let step: LessonStep

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(result.correct ? "Correct!" : "Not quite",
                  systemImage: result.correct ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill")
                .font(.headline)
                .foregroundStyle(result.correct ? .green : .orange)
            if !result.correct {
                HStack(alignment: .top) {
                    Text("\(Text("Correct answer:").fontWeight(.semibold)) \(result.expected)").font(.subheadline)
                    Spacer(minLength: 8)
                    SpeakButton(text: result.expected)
                }
            }
            if let explanation = step.explanation {
                Text(explanation).font(.subheadline)
            }
            if let tamil = step.explanationTamil {
                Text(tamil).font(.subheadline).foregroundStyle(.secondary)
            }
            if !result.correct {
                Text("You'll see this one again at the end.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background((result.correct ? Color.green : Color.orange).opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Step views

struct LessonIntroView: View {
    let lesson: Lesson

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            LogoMark(barLevels: LogoMark.speakingLevels)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 8) {
                Text("LESSON").font(.caption.weight(.bold)).foregroundStyle(.tint)
                Text(lesson.title).font(.largeTitle.bold())
            }
            Text(lesson.intro).font(.title3)
            Text(lesson.introTamil).font(.body).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Label("\(lesson.phrases.count) phrases", systemImage: "text.quote")
                Label("about 6 min", systemImage: "clock")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(lesson.phrases) { phrase in
                    Label(phrase.text, systemImage: "quote.opening")
                        .font(.subheadline)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

struct LearnStepView: View {
    let phrase: Phrase

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("NEW PHRASE").font(.caption.weight(.bold)).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 16) {
                Text(phrase.text)
                    .font(.title.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    SpeakButton(text: phrase.text, prominent: true)
                    SpeakButton(text: phrase.text, slow: true, prominent: true)
                }
                Divider()
                Text(phrase.tamil)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = phrase.note {
                    Label(note, systemImage: "lightbulb")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))

            Label("Say it out loud twice, like you're on the call.", systemImage: "mouth")
                .font(.subheadline.weight(.medium))
        }
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            Speaker.shared.speak(phrase.text)
        }
    }
}

struct ListenHeader: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepTitle(kicker: "Listen", text: "What did you hear?", tamil: "நீங்கள் கேட்டது எது?")
            HStack(spacing: 12) {
                SpeakButton(text: text, prominent: true)
                SpeakButton(text: text, slow: true, prominent: true)
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            Speaker.shared.speak(text)
        }
    }
}

struct FixHeader: View {
    let wrong: String
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepTitle(kicker: "Fix the mistake", text: prompt, tamil: "சரியான வாக்கியத்தைத் தேர்ந்தெடுங்கள்.")
            Label {
                Text(wrong).font(.body.italic())
            } icon: {
                Image(systemName: "exclamationmark.bubble.fill").foregroundStyle(.orange)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

struct BuildStepView: View {
    let step: LessonStep
    @Binding var answer: String?
    let result: StepResult?

    private struct Tile: Identifiable, Hashable {
        let id: Int
        let word: String
    }

    @State private var tiles: [Tile] = []
    @State private var chosen: [Tile] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepTitle(kicker: "Build the sentence", text: "Say this in English:", tamil: nil)
            Text(step.promptTamil ?? "")
                .font(.title3.weight(.medium))
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

            // Your sentence: tap a word to take it back.
            FlowLayout(spacing: 8) {
                ForEach(chosen) { tile in
                    tileButton(tile, filled: true) {
                        guard result == nil else { return }
                        chosen.removeAll { $0 == tile }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(12)
            .overlay(alignment: .bottom) {
                Rectangle().fill(.secondary.opacity(0.3)).frame(height: 1)
            }
            .overlay {
                if chosen.isEmpty {
                    Text("Tap the words in order")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }

            // Word bank.
            FlowLayout(spacing: 8) {
                ForEach(tiles) { tile in
                    let used = chosen.contains(tile)
                    tileButton(tile, filled: false) {
                        guard result == nil, !used else { return }
                        chosen.append(tile)
                    }
                    .opacity(used ? 0.25 : 1)
                    .disabled(used)
                }
            }
        }
        .onAppear {
            if tiles.isEmpty {
                tiles = (step.tiles ?? []).enumerated().map { Tile(id: $0.offset, word: $0.element) }.shuffled()
            }
        }
        .onChange(of: chosen) { _, newValue in
            answer = newValue.isEmpty ? nil : newValue.map(\.word).joined(separator: " ")
        }
    }

    private func tileButton(_ tile: Tile, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(tile.word)
                .font(.body.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(filled ? Color.accentColor.opacity(0.15) : Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.secondary.opacity(0.25)))
        }
        .buttonStyle(.plain)
    }
}

struct SpeakStepView: View {
    let step: LessonStep
    let lesson: Lesson

    @Environment(\.modelContext) private var modelContext
    @State private var listener = SingleAnswerListener()
    @State private var answer: CallTurn?
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepTitle(kicker: "Your turn", text: step.prompt ?? "", tamil: step.promptTamil)
            VStack(alignment: .leading, spacing: 12) {
                Text("Phrases to use").font(.subheadline.weight(.semibold))
                ForEach((step.suggestedPhraseIds ?? []).compactMap { lesson.phrase($0) }) { phrase in
                    HStack {
                        Text(phrase.text).font(.subheadline)
                        Spacer(minLength: 8)
                        SpeakButton(text: phrase.text)
                    }
                }
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

            if listener.available {
                recorder
            } else if listener.readiness == .needsDownload {
                Label("Say it out loud now. Download the speech model in Settings → AI tutor, and the app will listen and show you a fix.",
                      systemImage: "mic")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                SpeechReadinessNote(readiness: listener.readiness) { Task { await listener.prepare() } }
                    .font(.footnote)
            }

            if checking {
                HStack { ProgressView(); Text("Listening to your answer…") }
            }
            if let answer {
                feedback(for: answer)
            }
        }
        .task { await listener.prepare() }
        .onDisappear { listener.stop() }
        .onChange(of: listener.result) { _, result in
            guard let result else { return }
            Task { await evaluate(result) }
        }
    }

    private var recorder: some View {
        VStack(spacing: 10) {
            LevelBars(level: listener.level, active: listener.isRecording).frame(height: 20)
            Button {
                listener.isRecording ? listener.finish() : listener.start()
            } label: {
                Label(listener.isRecording ? "I'm done" : (answer == nil ? "Record my answer" : "Try again"),
                      systemImage: listener.isRecording ? "checkmark" : "mic.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .tint(listener.isRecording ? .green : .accentColor)
            .disabled(checking)
        }
    }

    private func feedback(for answer: CallTurn) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("You said").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            Text(answer.text).font(.callout)
            if let fix = ReportFix.top(from: [answer], limit: 1).first {
                FixCard(fix: fix)
            } else {
                Label(answer.check == nil && !TutorService.isAvailable
                      ? "No common mistakes found. Turn on the AI tutor for a full check."
                      : "No mistakes found. Well said!", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            }
            if let better = answer.check?.better, AnswerChecker.normalize(better) != AnswerChecker.normalize(answer.text) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Say it better").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Text(better).font(.callout)
                    SpeakButton(text: better)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func evaluate(_ result: SingleAnswerListener.Result) async {
        guard !result.text.isEmpty else { return }
        checking = true
        defer { checking = false }
        var turn = CallTurn(speaker: .learner, text: result.text, clipFile: result.clipFile,
                            seconds: result.seconds, longPauses: result.longPauses)
        turn.ruleHits = MistakeRules.check(result.text).map { CallTurn.StoredHit(ruleId: $0.ruleId, wrong: $0.wrong) }
        if TutorService.isAvailable { turn.check = try? await TutorService.checkAnswer(result.text) }
        answer = turn
        MistakeBook.record(turns: [turn], in: modelContext)
    }
}

struct LessonCompleteView: View {
    let lesson: Lesson
    let session: LessonSession

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: session.isFinished)
            VStack(alignment: .leading, spacing: 8) {
                Text("Lesson complete!").font(.largeTitle.bold())
                Text("\(session.firstTryCorrect.count) of \(session.gradedCount) right first time")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Phrases you learned").font(.headline)
                ForEach(lesson.phrases) { phrase in
                    HStack {
                        Text(phrase.text).font(.subheadline)
                        Spacer(minLength: 8)
                        SpeakButton(text: phrase.text)
                    }
                }
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            Label("Use one of these on your next real call. They'll come back in Review so you don't forget them.",
                  systemImage: "sparkles")
                .font(.subheadline)
        }
    }
}

// MARK: - Layout

/// Lays out views left to right, wrapping onto new lines (for word tiles).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, width: width)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let maxRow = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? maxRow, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width && !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
