import SwiftUI

@main
struct ProCommunicateApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var courseState: CourseLoadState = CourseLoadState.load()
    @State private var router = AppRouter()
    /// The animated intro plays once per launch, over the app (which loads underneath).
    @State private var showSplash = !UserDefaults.standard.bool(forKey: "skipSplash")

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    switch courseState {
                    case .loaded(let course):
                        RootView(course: course)
                    case .failed(let message):
                        ContentUnavailableView(
                            "Course content couldn't be loaded",
                            systemImage: "exclamationmark.triangle",
                            description: Text(message)
                        )
                    }
                }
                if showSplash {
                    SplashView { showSplash = false }
                        .zIndex(1)
                }
            }
            .environment(router)
            .environment(AIModelManager.shared)
        }
        .modelContainer(for: LessonProgressRecord.self)
    }
}

/// Result of loading the bundled course once at launch.
enum CourseLoadState {
    case loaded(Course)
    case failed(String)

    static func load() -> CourseLoadState {
        do {
            return .loaded(try ContentLoader.loadCourse())
        } catch {
            return .failed(String(describing: error))
        }
    }
}
