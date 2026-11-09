import SwiftData
import SwiftUI

/// Review due cards: see the Tamil meaning (or a mistake), say the English aloud, check, and rate.
struct ReviewSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var queue: [ReviewCard] = []
    @State private var position = 0
    @State private var revealed = false
    @State private var reviewed = 0
    @State private var startedAt = Date()
    @State private var loaded = false
    @State private var logged = false

    private var current: ReviewCard? { position < queue.count ? queue[position] : nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button {
                    finish()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: 36, height: 36)
                        .background(.thinMaterial, in: Circle())
                }
                .tint(.primary)
                .accessibilityLabel("Close review")
                ProgressView(value: queue.isEmpty ? 1 : Double(position) / Double(queue.count))
                Text("\(min(position + 1, queue.count))/\(queue.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            ScrollView {
                Group {
                    if let card = current {
                        cardView(card).id(card.id + "\(position)")
                    } else if loaded {
                        doneView
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            bottomBar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            guard !loaded else { return }
            queue = LearningStore.dueCards(in: context)
            startedAt = .now
            loaded = true
        }
        .onDisappear { Speaker.shared.stop() }
    }

    private func cardView(_ card: ReviewCard) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(card.kind == .phrase ? "SAY IT IN ENGLISH" : "SAY THE CORRECT VERSION")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tint)
            Text(card.front)
                .font(card.kind == .phrase ? .title2.weight(.medium) : .title3.italic())
                .fixedSize(horizontal: false, vertical: true)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(card.kind == .phrase ? Color(.secondarySystemGroupedBackground) : Color.orange.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 18))
            if !revealed {
                Label("Say it out loud first, then check.", systemImage: "mouth")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Text(card.back)
                        .font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        SpeakButton(text: card.back, prominent: true)
                        SpeakButton(text: card.back, slow: true, prominent: true)
                    }
                    if let hint = card.hint {
                        Label(hint, systemImage: "lightbulb")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var doneView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 56)).foregroundStyle(.green)
            Text(reviewed == 0 ? "Nothing due right now" : "Review done!").font(.largeTitle.bold())
            Text(reviewed == 0
                 ? "Finish a lesson and its phrases will come back here."
                 : "You reviewed \(reviewed) \(reviewed == 1 ? "card" : "cards"). They'll come back just before you'd forget them.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        if let card = current {
            if !revealed {
                Button {
                    withAnimation(.spring(duration: 0.35)) { revealed = true }
                    Speaker.shared.speak(card.back)
                } label: {
                    Text("Show answer").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                let labels = LearningStore.preview(card)
                VStack(spacing: 8) {
                    Text("How well did you remember it?").font(.footnote).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(ReviewGrade.allCases, id: \.self) { grade in
                            Button {
                                rate(card, grade)
                            } label: {
                                VStack(spacing: 2) {
                                    Text(grade.title).font(.subheadline.weight(.semibold))
                                    Text(labels[grade] ?? "").font(.caption2).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.bordered)
                            .tint(color(for: grade))
                        }
                    }
                }
            }
        } else {
            Button {
                finish()
            } label: {
                Text("Done").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func color(for grade: ReviewGrade) -> Color {
        switch grade {
        case .again: .red
        case .hard: .orange
        case .good: .green
        case .easy: .blue
        }
    }

    private func rate(_ card: ReviewCard, _ grade: ReviewGrade) {
        LearningStore.grade(card, grade)
        try? context.save()
        reviewed += 1
        if grade == .again { queue.append(card) }   // see it again before the session ends
        Speaker.shared.stop()
        withAnimation(.easeInOut(duration: 0.25)) {
            revealed = false
            position += 1
        }
    }

    private func finish() {
        if reviewed > 0 && !logged {
            logged = true
            LearningStore.log(.review, seconds: Date().timeIntervalSince(startedAt), in: context)
        }
        dismiss()
    }
}
