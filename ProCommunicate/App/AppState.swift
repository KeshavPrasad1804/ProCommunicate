import SwiftUI
import UIKit

/// App-wide navigation state shared through the environment.
@MainActor @Observable
final class AppRouter {
    var showSettings = false
    /// The lesson being played full screen, if any.
    var activeLesson: Lesson?
    /// Full-screen review session.
    var showReviewSession = false
    /// Full-screen stand-up drill.
    var showStandUpDrill = false
    /// The practice call on screen, if any.
    var activeCall: CallLaunch?
    /// A finished call's report opened from history.
    var openReport: UUID?

    func startCall(_ scenario: CallScenario, extraContext: String? = nil) {
        activeCall = CallLaunch(scenario: scenario, extraContext: extraContext)
    }
    /// Debug only: start the lesson at this step (skips the intro), for screenshots.
    var debugLessonStartStep: Int?

    func open(_ lesson: Lesson) {
        activeLesson = lesson
    }
}

enum SettingsKey {
    /// The AI tutor switch. Off until you turn it on and download the model.
    static let aiTutorEnabled = "aiTutorEnabled"
    /// Daily practice goal in minutes (10, 20 or 30).
    static let dailyGoalMinutes = "dailyGoalMinutes"
    static let reminderEnabled = "reminderEnabled"
    /// Minutes after midnight for the daily reminder.
    static let reminderMinuteOfDay = "reminderMinuteOfDay"
}

/// Lets iOS wake the app to finish the model's background download.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        // Touching the manager recreates the background session, which then delivers the pending events.
        AIModelManager.shared.backgroundEventsCompletion = completionHandler
    }
}

/// Gear button that opens Settings from any tab.
struct SettingsToolbarButton: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button {
            router.showSettings = true
        } label: {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel("Settings")
    }
}

/// What's needed to start a call.
struct CallLaunch: Identifiable, Hashable {
    let id = UUID()
    let scenario: CallScenario
    let extraContext: String?
}
