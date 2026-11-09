import SwiftData
import SwiftUI

/// The Review tab: what's due now, and what's coming.
struct ReviewView: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \ReviewCard.due) private var cards: [ReviewCard]

    var body: some View {
        let now = Date()
        let due = cards.filter { $0.due <= now }
        NavigationStack {
            Group {
                if cards.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing to review yet", systemImage: "arrow.trianglehead.2.clockwise")
                    } description: {
                        Text("Finish a lesson and its phrases and fixes will come back here, just before you would forget them.")
                    }
                } else {
                    List {
                        Section {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(due.isEmpty ? "All caught up" : "\(due.count) to review")
                                    .font(.title2.bold())
                                Text(due.isEmpty
                                     ? nextText(cards.first?.due)
                                     : "See the Tamil meaning, say the English out loud, then check.")
                                    .foregroundStyle(.secondary)
                                if !due.isEmpty {
                                    Button {
                                        router.showReviewSession = true
                                    } label: {
                                        Label("Start review", systemImage: "play.fill")
                                            .font(.headline)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 4)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.large)
                                    .padding(.top, 4)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        Section("Your cards") {
                            LabeledContent("Phrases", value: "\(cards.filter { $0.kind == .phrase }.count)")
                            LabeledContent("Mistakes to fix", value: "\(cards.filter { $0.kind == .mistake }.count)")
                            LabeledContent("Remembered well", value: "\(cards.filter { $0.stability >= 21 }.count)")
                        }
                        Section("Coming up") {
                            ForEach(cards.filter { $0.due > now }.prefix(8)) { card in
                                HStack {
                                    Text(card.back).font(.subheadline).lineLimit(1)
                                    Spacer()
                                    Text(card.due, format: .relative(presentation: .named))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Review")
        }
    }

    private func nextText(_ date: Date?) -> String {
        guard let date else { return "" }
        return "Next review \(date.formatted(.relative(presentation: .named)))."
    }
}

#Preview {
    ReviewView()
        .environment(AppRouter())
        .modelContainer(for: AppSchema.models, inMemory: true)
}
