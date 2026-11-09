import SwiftUI
import UIKit

/// App-wide navigation state shared through the environment.
@MainActor @Observable
final class AppRouter {
    var showSettings = false
}

enum SettingsKey {
    /// The AI tutor switch. Off until you turn it on and download the model.
    static let aiTutorEnabled = "aiTutorEnabled"
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
