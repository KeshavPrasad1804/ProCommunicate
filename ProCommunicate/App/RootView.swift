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

    var body: some View {
        @Bindable var router = router
        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.max.fill", value: AppTab.today) {
                TodayView()
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
        #if DEBUG
        .task {
            // Screenshot / testing hooks: -openSettings YES, -autoStartModelDownload YES
            if UserDefaults.standard.bool(forKey: "openSettings") { router.showSettings = true }
            if UserDefaults.standard.bool(forKey: "autoStartModelDownload") { aiModel.startDownload() }
        }
        #endif
    }
}

#Preview {
    RootView(course: .preview)
        .environment(AppRouter())
        .environment(AIModelManager.shared)
}
