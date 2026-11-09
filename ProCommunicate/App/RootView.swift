import SwiftData
import SwiftUI

/// The five main areas of the app, matching FEATURES.md.
enum AppTab: String, CaseIterable, Hashable {
    case today, learn, practice, review, progress

    /// Lets tests and screenshots open a specific tab: launch with `-initialTab learn`.
    static var launchTab: AppTab {
        UserDefaults.standard.string(forKey: "initialTab").flatMap(AppTab.init(rawValue:)) ?? .today
    }
}

struct RootView: View {
    let course: Course
    @State private var selection: AppTab = AppTab.launchTab
    @Environment(AppRouter.self) private var router
    @Environment(AIModelManager.self) private var aiModel
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        @Bindable var router = router
        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.max.fill", value: AppTab.today) {
                TodayView(course: course)
            }
            Tab("Learn", systemImage: "book.fill", value: AppTab.learn) {
                LearnView(course: course)
            }
            Tab("Practice", systemImage: "phone.fill", value: AppTab.practice) {
                PracticeView()
            }
            Tab("Review", systemImage: "arrow.trianglehead.2.clockwise", value: AppTab.review) {
                ReviewView()
            }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.progress) {
                MyProgressView()
            }
        }
        .sheet(isPresented: $router.showSettings) {
            SettingsView()
        }
        .fullScreenCover(item: $router.activeLesson) { lesson in
            LessonPlayerView(lesson: lesson, startAt: router.debugLessonStartStep) { score, seconds in
                ProgressStore.recordCompletion(of: lesson, score: score, in: modelContext)
                LearningStore.addCards(from: lesson, in: modelContext)
                LearningStore.log(.lesson, seconds: seconds, in: modelContext)
            }
        }
        .fullScreenCover(isPresented: $router.showReviewSession) {
            ReviewSessionView()
        }
        .fullScreenCover(isPresented: $router.showStandUpDrill) {
            StandUpDrillView()
        }
        #if DEBUG
        .task {
            // Screenshot / testing hooks: -openSettings YES, -autoStartModelDownload YES,
            // -openLesson <unitId> [-lessonStep N]
            let defaults = UserDefaults.standard
            if defaults.bool(forKey: "openSettings") { router.showSettings = true }
            if defaults.bool(forKey: "autoStartModelDownload") { aiModel.startDownload() }
            if let unitId = defaults.string(forKey: "openLesson"),
               let lesson = try? ContentLoader.loadLesson(unitId: unitId) {
                if defaults.object(forKey: "lessonStep") != nil { router.debugLessonStartStep = defaults.integer(forKey: "lessonStep") }
                router.open(lesson)
            }
            if defaults.bool(forKey: "openStandUp") { router.showStandUpDrill = true }
            if defaults.bool(forKey: "openReview") { router.showReviewSession = true }
            if defaults.bool(forKey: "seedDemoData") { DemoData.seed(in: modelContext) }
        }
        #endif
    }
}

#Preview {
    RootView(course: .preview)
        .environment(AppRouter())
        .environment(AIModelManager.shared)
        .modelContainer(for: AppSchema.models, inMemory: true)
}
