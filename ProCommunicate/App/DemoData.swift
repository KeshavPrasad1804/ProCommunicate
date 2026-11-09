#if DEBUG
import Foundation
import SwiftData

/// Debug-only sample data for screenshots: launch with `-seedDemoData YES`.
@MainActor
enum DemoData {
    static func seed(in context: ModelContext) {
        guard (try? context.fetchCount(FetchDescriptor<PracticeDay>())) == 0,
              let lesson = try? ContentLoader.loadLesson(unitId: "meetings-03-status") else { return }
        let calendar = Calendar.current
        for offset in 0..<4 {
            let date = calendar.date(byAdding: .day, value: -offset, to: .now) ?? .now
            LearningStore.log(.lesson, seconds: Double(8 + offset * 3) * 60, now: date, in: context)
        }
        ProgressStore.recordCompletion(of: lesson, score: 0.75, in: context)
        // Cards created three days ago so they are due now.
        LearningStore.addCards(from: lesson, now: calendar.date(byAdding: .day, value: -3, to: .now) ?? .now, in: context)
    }
}
#endif
