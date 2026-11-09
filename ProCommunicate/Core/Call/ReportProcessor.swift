import Foundation
import Observation
import SwiftData
import UIKit
import UserNotifications

/// Checks a finished call's answers in the background (while you use the rest of the app), saves the
/// report as it fills in, and notifies you when it's ready.
///
/// iPhones don't allow GPU work (the AI) while the app is in the background, so processing pauses
/// when you leave the app and continues when you come back. It also waits while a call is running.
@MainActor @Observable
final class ReportProcessor {
    static let shared = ReportProcessor()

    struct Progress: Equatable {
        var done: Int
        var total: Int
    }

    /// A short message shown at the top of the app.
    struct Banner: Equatable, Identifiable {
        let id = UUID()
        let text: String
        let reportId: UUID?
    }

    private(set) var progress: [UUID: Progress] = [:]
    var banner: Banner?
    /// Set when you tap the "report ready" notification; the root view opens the report.
    var openRequest: UUID?
    /// True while a practice call is on screen (the call needs the AI engine).
    var callInProgress = false

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var queue: [UUID] = []
    @ObservationIgnored private var running = false

    private var context: ModelContext? { container?.mainContext }

    /// True while answers are being checked (other AI work waits).
    var isWorking: Bool { running }

    /// Called once at launch. Resumes reports that were still pending when the app last closed.
    func configure(container: ModelContainer) {
        self.container = container
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            // GPU work isn't allowed in the background: stop now; the answer is retried when you're back.
            Task { @MainActor in
                if ReportProcessor.shared.running && !ReportProcessor.shared.callInProgress { LlamaEngine.shared.cancelCurrent() }
            }
        }
        let pending = (try? container.mainContext.fetch(FetchDescriptor<CallRecord>(predicate: #Predicate { $0.reportPending }))) ?? []
        for record in pending { enqueue(record.id, announce: false) }
    }

    func enqueue(_ recordId: UUID, announce: Bool = true) {
        guard !queue.contains(recordId) else { return }
        queue.append(recordId)
        if announce {
            banner = Banner(text: "Call saved. Your report is being prepared. We'll let you know when it's ready.", reportId: nil)
            Task { _ = await ReminderScheduler.requestPermission() }
        }
        if !running { Task { await run() } }
    }

    // MARK: - Work

    private func run() async {
        running = true
        defer { running = false }
        while let id = queue.first {
            await process(id)
            queue.removeFirst()
        }
        // Free the AI's memory unless a call needs it.
        if !callInProgress {
            await LlamaEngine.shared.unload()   // speech recognition stays loaded (small, and slow to load)
        }
    }

    private func process(_ id: UUID) async {
        guard let context, let record = fetch(id, in: context) else { return }
        var turns = record.turns
        let toCheck = turns.indices.filter { turns[$0].speaker == .learner && turns[$0].check == nil && !turns[$0].checkFailed }
        progress[id] = Progress(done: 0, total: toCheck.count)
        var newlyChecked: [CallTurn] = []

        for (n, index) in toCheck.enumerated() {
            var attempts = 0
            while attempts < 2 {
                await waitUntilFree()
                do {
                    try await TutorService.ensureLoaded()
                    let check = try await checkWithTimeout(turns[index].text)
                    if let check { turns[index].check = check; newlyChecked.append(turns[index]) } else { turns[index].checkFailed = true }
                    break
                } catch LlamaError.cancelled {
                    // Left the app or a call started: try this answer again when free (doesn't count).
                    continue
                } catch {
                    // GPU work fails in the background; only count real failures.
                    if UIApplication.shared.applicationState == .active { attempts += 1 }
                    if attempts >= 2 { turns[index].checkFailed = true }
                }
            }
            // Save after every answer so an open report fills in as it goes.
            record.update(turns: turns)
            try? context.save()
            progress[id] = Progress(done: n + 1, total: toCheck.count)
        }

        record.reportPending = false
        MistakeBook.record(turns: newlyChecked, includeRules: false, in: context)
        try? context.save()
        progress[id] = nil
        await notifyReady(record)
    }

    private func waitUntilFree() async {
        while UIApplication.shared.applicationState != .active || callInProgress {
            try? await Task.sleep(for: .milliseconds(600))
        }
    }

    /// One answer check with a time limit, so a stuck check can't hold up the report.
    private func checkWithTimeout(_ text: String) async throws -> AnswerCheck? {
        let timeout = Task {
            try? await Task.sleep(for: .seconds(90))
            if !Task.isCancelled { LlamaEngine.shared.cancelCurrent() }
        }
        defer { timeout.cancel() }
        do {
            return try await TutorService.checkAnswer(text)
        } catch LlamaError.cancelled where !timeout.isCancelled && UIApplication.shared.applicationState == .active && !callInProgress {
            // Cancelled by the timeout, not by leaving the app: give up on this answer.
            return nil
        }
    }

    private func fetch(_ id: UUID, in context: ModelContext) -> CallRecord? {
        try? context.fetch(FetchDescriptor<CallRecord>(predicate: #Predicate { $0.id == id })).first
    }

    // MARK: - Notify

    private func notifyReady(_ record: CallRecord) async {
        let fixes = ReportFix.top(from: record.turns).count
        let body = fixes == 0 ? "No mistakes found. Tap to see your numbers." : "Your top \(fixes) \(fixes == 1 ? "fix is" : "fixes are") ready. Tap to see them."
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
            let content = UNMutableNotificationContent()
            content.title = "Report ready: \(record.title)"
            content.body = body
            content.sound = .default
            content.userInfo = ["callId": record.id.uuidString]
            try? await center.add(UNNotificationRequest(identifier: "report-\(record.id.uuidString)", content: content, trigger: nil))
        } else {
            banner = Banner(text: "Report ready: \(record.title). \(body)", reportId: record.id)
        }
    }
}

/// Shows notifications while the app is open and opens the report when you tap one.
final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationHandler()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let idString = response.notification.request.content.userInfo["callId"] as? String,
              let id = UUID(uuidString: idString) else { return }
        await MainActor.run { ReportProcessor.shared.openRequest = id }
    }
}
