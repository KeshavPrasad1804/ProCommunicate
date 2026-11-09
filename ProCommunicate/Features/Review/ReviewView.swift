import SwiftUI

/// Spaced-repetition review, practised by speaking (arrives in Phase 2).
struct ReviewView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Nothing to review yet", systemImage: "arrow.trianglehead.2.clockwise")
            } description: {
                Text("Phrases from your lessons and fixes from your calls will come back here, just before you would forget them.")
            } actions: {
                PhaseBadge(phase: "2")
            }
            .navigationTitle("Review")
        }
    }
}

#Preview { ReviewView() }
