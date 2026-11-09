import SwiftData
import SwiftUI

@main
struct ProCommunicateApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var courseState: CourseLoadState = CourseLoadState.load()
    @State private var router = AppRouter()
    /// The animated intro plays once per launch, over the app (which loads underneath).
    @State private var showSplash = !UserDefaults.standard.bool(forKey: "skipSplash")
    /// The on-phone database. If it ever can't be opened (for example a failed upgrade), the app still
    /// starts with a temporary in-memory store instead of crashing.
    private let container: ModelContainer = {
        let schema = Schema(AppSchema.models)
        if let container = try? ModelContainer(for: schema) { return container }
        return try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }()

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
            .task {
                ReportProcessor.shared.configure(container: container)
                SpeechReadiness.preloadInBackground()
                RecordingCleanup.run(in: container.mainContext)
            }
        }
        .modelContainer(container)
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
