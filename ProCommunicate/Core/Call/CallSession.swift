import AVFoundation
import Foundation
import Observation
import SwiftData

/// Runs one practice call: the AI's spoken turns, listening for yours, transcribing, background
/// answer checks, recording your answers, and saving the call with its mistakes at the end.
///
/// Order of work on the single AI engine: the AI's reply always comes first. Answer checks run
/// in the gaps (while the AI speaks and you answer) and are cancelled and retried later if you
/// finish your next turn before a check is done (PLAN.md "Mock interview mode").
@MainActor @Observable
final class CallSession {
    enum Phase: Equatable {
        case preparing(String)
        case aiSpeaking
        case listening
        case learnerSpeaking
        case thinking
        case finishing(done: Int, total: Int)
        case ended
        case failed(String)
    }

    let scenario: CallScenario
    let profile: LearnerProfile
    let extraContext: String?
    let recordId = UUID()

    private(set) var phase: Phase = .preparing("Getting ready…")
    private(set) var turns: [CallTurn] = []
    private(set) var level: Double = 0
    private(set) var startedAt = Date()
    private(set) var savedRecordId: UUID?
    /// True when there's no speech model or microphone: you type your answers instead.
    private(set) var typingMode = false
    var typedAnswer = ""

    /// Whether the real AI is available (iPhone + downloaded model); otherwise replies are scripted.
    let aiAvailable: Bool

    @ObservationIgnored private var capture: VoiceCapture?
    @ObservationIgnored private var messages: [ChatMessage] = []
    /// True while the AI is writing its reply.
    @ObservationIgnored private var replying = false
    @ObservationIgnored private var checkTask: Task<Void, Never>?
    @ObservationIgnored private var checkingTurn: UUID?
    @ObservationIgnored private var endAfterSpeaking = false
    @ObservationIgnored private var learnerTurnCount = 0

    init(scenario: CallScenario, profile: LearnerProfile = .current, extraContext: String? = nil) {
        self.scenario = scenario
        self.profile = profile
        self.extraContext = extraContext
        self.aiAvailable = LlamaEngine.isAvailable && AIModelManager.shared.isReady
    }

    var isActive: Bool {
        switch phase {
        case .ended, .failed, .finishing: false
        default: true
        }
    }

    var lastAIText: String? { turns.last { $0.speaker == .ai }?.text }
    var lastLearnerText: String? { turns.last { $0.speaker == .learner }?.text }

    // MARK: - Start

    func start() async {
        startedAt = .now
        Speaker.shared.onFinishedAll = { [weak self] in self?.aiFinishedSpeaking() }

        if aiAvailable {
            phase = .preparing("Loading the AI…")
            do {
                try await LlamaEngine.shared.load(modelPath: AIModelManager.shared.modelFileURL.path)
                await LlamaEngine.shared.reset(.conversation)
                await LlamaEngine.shared.reset(.utility)
            } catch {
                phase = .failed(error.localizedDescription)
                return
            }
        }

        // Voice: needs the speech model and microphone permission; otherwise type.
        if let folder = SpeechModelManager.shared.modelFolder, await AudioRecorder.requestPermission() {
            phase = .preparing("Loading speech recognition…")
            do {
                try await SpeechRecognizer.shared.load(folder: folder)
                let capture = VoiceCapture { [weak self] event in
                    Task { @MainActor in self?.handle(event) }
                }
                try capture.start()
                self.capture = capture
            } catch {
                typingMode = true
            }
        } else {
            typingMode = true
        }

        messages = [ChatMessage(role: .system, content: scenario.systemPrompt(profile: profile, extraContext: extraContext))]
        let opening = scenario.openingLine(profile: profile)
        messages.append(ChatMessage(role: .assistant, content: opening))
        turns.append(CallTurn(speaker: .ai, text: opening))
        say([opening])
    }

    // MARK: - Speaking and listening

    private func say(_ sentences: [String]) {
        guard !sentences.isEmpty else { return }
        phase = .aiSpeaking
        capture?.setAISpeaking(true)
        capture?.setListening(false)
        for sentence in sentences {
            Speaker.shared.enqueue(sentence, voice: scenario.speechVoice)
        }
    }

    private func aiFinishedSpeaking() {
        guard isActive, phase == .aiSpeaking else { return }
        capture?.setAISpeaking(false)
        if endAfterSpeaking {
            Task { await end() }
            return
        }
        // Still writing the reply? Keep waiting; the next sentences will be spoken.
        if replying { phase = .thinking; return }
        phase = .listening
        capture?.setListening(true)
        startNextCheckIfIdle()
    }

    /// Stops the AI talking (you started speaking, or tapped to interrupt).
    func interrupt() {
        guard phase == .aiSpeaking else { return }
        Speaker.shared.stop()
        capture?.setAISpeaking(false)
        phase = .listening
        capture?.setListening(true)
    }

    /// "I'm done": ends your turn without waiting for the pause.
    func finishTurnNow() {
        capture?.finishTurnNow()
    }

    private func handle(_ event: VoiceEvent) {
        switch event {
        case .level(let value):
            level = value
        case .speechStarted:
            if phase == .aiSpeaking { interrupt() }
            if phase == .listening || phase == .aiSpeaking { phase = .learnerSpeaking }
            pauseChecksForReply()
        case .turnEnded(let samples, let duration, let longPauses):
            guard isActive else { return }
            Task { await learnerSpoke(samples: samples, seconds: duration, longPauses: longPauses) }
        }
    }

    func submitTypedAnswer() {
        let text = typedAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, isActive else { return }
        typedAnswer = ""
        let estimatedSeconds = Double(FluencyMetrics.wordCount(text)) / 2.2
        Task { await handleLearnerText(text, clipFile: nil, seconds: estimatedSeconds, longPauses: 0) }
    }

    private func learnerSpoke(samples: [Float], seconds: Double, longPauses: Int) async {
        phase = .thinking
        capture?.setListening(false)
        pauseChecksForReply()
        if aiAvailable {
            // A short acknowledgement while the transcript and reply are prepared.
            Speaker.shared.enqueue(["Mm-hmm.", "Okay.", "Right.", "I see."].randomElement()!, voice: scenario.speechVoice)
        }
        let transcript = (try? await SpeechRecognizer.shared.transcribe(samples))?.text ?? ""
        guard !transcript.isEmpty else {
            say(["Sorry, I didn't quite catch that. Could you say it again?"])
            return
        }
        learnerTurnCount += 1
        let clipName = "call-\(recordId.uuidString.prefix(8))-\(learnerTurnCount).m4a"
        let clipURL = RecordingStorage.directory.appending(path: clipName)
        let saved = await Task.detached(priority: .utility) { () -> Bool in
            (try? AudioFileWriter.writeM4A(samples, to: clipURL)) != nil
        }.value
        await handleLearnerText(transcript, clipFile: saved ? clipName : nil, seconds: seconds, longPauses: longPauses)
    }

    private func handleLearnerText(_ text: String, clipFile: String?, seconds: Double, longPauses: Int) async {
        phase = .thinking
        var turn = CallTurn(speaker: .learner, text: text, clipFile: clipFile, seconds: seconds, longPauses: longPauses)
        turn.ruleHits = MistakeRules.check(text).map { CallTurn.StoredHit(ruleId: $0.ruleId, wrong: $0.wrong) }
        turns.append(turn)
        messages.append(ChatMessage(role: .user, content: text))
        trimHistoryIfNeeded()

        let learnerTurns = turns.filter { $0.speaker == .learner }.count
        let wrapUp = learnerTurns >= scenario.maxTurns
        if wrapUp {
            messages.append(ChatMessage(role: .system, content: "The call is at its time limit. Reply with a brief, polite closing and goodbye."))
        }
        await generateReply(closing: wrapUp)
    }

    // MARK: - The AI's reply

    private func generateReply(closing: Bool) async {
        guard aiAvailable else {
            let scripted = closing
                ? "Thanks, that's all for today. Goodbye!"
                : "Thank you. Could you tell me a little more about that?"
            turns.append(CallTurn(speaker: .ai, text: scripted))
            endAfterSpeaking = closing
            say([scripted])
            return
        }
        let prompt = GemmaPrompt.format(messages)
        let voice = scenario.speechVoice
        replying = true
        var splitter = SentenceSplitter()
        let stream = AsyncStream<String> { continuation in
            Task.detached {
                do {
                    let result = try await LlamaEngine.shared.generate(prompt: prompt, slot: .conversation,
                                                                      options: GenerationOptions(maxTokens: 120, temperature: 0.7)) { piece in
                        continuation.yield(piece)
                    }
                    _ = result
                } catch {
                    continuation.yield("\u{0}ERROR")
                }
                continuation.finish()
            }
        }
        var reply = ""
        var failed = false
        for await piece in stream {
            if piece == "\u{0}ERROR" { failed = true; break }
            reply += piece
            for sentence in splitter.add(piece) {
                let clean = GemmaPrompt.clean(sentence)
                if !clean.isEmpty {
                    if phase != .aiSpeaking { phase = .aiSpeaking; capture?.setAISpeaking(true); capture?.setListening(false) }
                    Speaker.shared.enqueue(clean, voice: voice)
                }
            }
        }
        if let rest = splitter.flush().map(GemmaPrompt.clean), !rest.isEmpty {
            if phase != .aiSpeaking { phase = .aiSpeaking; capture?.setAISpeaking(true) }
            Speaker.shared.enqueue(rest, voice: voice)
        }
        replying = false
        let text = GemmaPrompt.clean(reply)
        if failed || text.isEmpty {
            say(["Sorry, could you repeat that?"])
            return
        }
        turns.append(CallTurn(speaker: .ai, text: text))
        messages.append(ChatMessage(role: .assistant, content: text))
        let saysGoodbye = text.lowercased().contains("goodbye") || text.lowercased().contains("bye for now")
        endAfterSpeaking = closing || saysGoodbye
        // If the speech already finished while the reply was still being written, listen now.
        if !Speaker.shared.isSpeaking { phase = .aiSpeaking; aiFinishedSpeaking() }
        startNextCheckIfIdle()
    }

    /// Keeps the conversation within the AI's memory: the system prompt (with your profile pinned)
    /// stays, and the oldest turns are dropped if the call gets very long.
    private func trimHistoryIfNeeded() {
        let budgetCharacters = 16_000   // ≈ 4,500 tokens of an 8,192-token context
        while messages.count > 3, messages.dropFirst().reduce(0, { $0 + $1.content.count }) > budgetCharacters {
            messages.remove(at: 1)
        }
    }

    // MARK: - Background answer checks

    private func startNextCheckIfIdle() {
        guard aiAvailable, checkTask == nil, !replying,
              phase == .aiSpeaking || phase == .listening || phase == .learnerSpeaking,
              let turn = turns.first(where: { $0.speaker == .learner && $0.check == nil && !$0.checkFailed }) else { return }
        checkingTurn = turn.id
        checkTask = Task { [weak self] in
            await self?.check(turnId: turn.id, text: turn.text)
            self?.checkTask = nil
            self?.checkingTurn = nil
            self?.startNextCheckIfIdle()
        }
    }

    /// The reply comes first: stop a running check (it will be retried later).
    private func pauseChecksForReply() {
        if checkTask != nil { LlamaEngine.shared.cancelCurrent() }
    }

    private func check(turnId: UUID, text: String) async {
        let prompt = GemmaPrompt.format([
            ChatMessage(role: .system, content: TutorPrompts.answerCheckSystem),
            ChatMessage(role: .user, content: text),
        ])
        do {
            let result = try await LlamaEngine.shared.generate(
                prompt: prompt, slot: .utility,
                options: GenerationOptions(maxTokens: 450, temperature: 0, grammar: TutorPrompts.answerCheckGrammar))
            guard let index = turns.firstIndex(where: { $0.id == turnId }) else { return }
            if let check = TutorPrompts.parseAnswerCheck(result.text, answer: text) {
                turns[index].check = check
            } else {
                turns[index].checkFailed = true
            }
        } catch LlamaError.cancelled {
            // Retried when the AI is idle again.
        } catch {
            if let index = turns.firstIndex(where: { $0.id == turnId }) { turns[index].checkFailed = true }
        }
    }

    // MARK: - End

    func end() async {
        guard isActive else { return }
        capture?.stop()
        capture = nil
        Speaker.shared.stop()
        Speaker.shared.onFinishedAll = nil
        replying = false
        if checkTask != nil { LlamaEngine.shared.cancelCurrent(); await checkTask?.value }

        // Finish the answer checks for the report.
        if aiAvailable {
            let unchecked = turns.filter { $0.speaker == .learner && $0.check == nil && !$0.checkFailed }
            for (index, turn) in unchecked.enumerated() {
                phase = .finishing(done: index, total: unchecked.count)
                await check(turnId: turn.id, text: turn.text)
            }
        }
        phase = .ended
    }

    /// Saves the call, its mistakes (into My Mistakes and Review) and the practice time.
    func save(in context: ModelContext) {
        guard savedRecordId == nil, turns.contains(where: { $0.speaker == .learner }) else { return }
        let seconds = Date().timeIntervalSince(startedAt)
        let record = CallRecord(id: recordId, scenarioId: scenario.id, title: scenario.title, kind: scenario.kind.rawValue,
                                startedAt: startedAt, seconds: seconds, turns: turns)
        context.insert(record)
        MistakeBook.record(turns: turns, in: context)
        LearningStore.log(.call, seconds: seconds, in: context)
        try? context.save()
        savedRecordId = record.id
    }
}

/// Files mistakes from calls and drills into My Mistakes and Review.
@MainActor
enum MistakeBook {
    static func record(turns: [CallTurn], in context: ModelContext, date: Date = .now) {
        for turn in turns where turn.speaker == .learner {
            var entries: [(pattern: String, wrong: String, right: String, why: String, whyTamil: String?)] = []
            for hit in turn.ruleHits {
                guard let rule = MistakeRules.rule(hit.ruleId) else { continue }
                entries.append((rule.id, hit.wrong, rule.right, rule.why, rule.whyTamil))
            }
            for mistake in turn.check?.mistakes ?? [] {
                // Skip AI finds that repeat a rule match.
                let overlaps = turn.ruleHits.contains {
                    let a = AnswerChecker.normalize($0.wrong), b = AnswerChecker.normalize(mistake.wrong)
                    return a.contains(b) || b.contains(a)
                }
                if !overlaps { entries.append((mistake.type, mistake.wrong, mistake.right, mistake.why, nil)) }
            }
            for entry in entries {
                upsert(pattern: entry.pattern, wrong: entry.wrong, right: entry.right, why: entry.why,
                       whyTamil: entry.whyTamil, context: turn.text, clip: turn.clipFile, date: date, in: context)
            }
        }
        try? context.save()
    }

    static func upsert(pattern: String, wrong: String, right: String, why: String, whyTamil: String?,
                       context sentence: String?, clip: String?, date: Date = .now, in context: ModelContext) {
        let key = MistakeRecord.key(pattern: pattern, wrong: wrong)
        let descriptor = FetchDescriptor<MistakeRecord>(predicate: #Predicate { $0.key == key })
        let record: MistakeRecord
        if let existing = try? context.fetch(descriptor).first {
            existing.count += 1
            existing.lastSeen = date
            existing.wrong = wrong
            record = existing
        } else {
            record = MistakeRecord(pattern: pattern, wrong: wrong, right: right, why: why, whyTamil: whyTamil, date: date)
            context.insert(record)
        }
        if let clip { record.lastClipFile = clip }
        if let sentence { record.lastContext = sentence }

        // Also practise it in Review: see what you said, say the better version.
        let cardId = "mistake.\(key)"
        let cardDescriptor = FetchDescriptor<ReviewCard>(predicate: #Predicate { $0.id == cardId })
        if (try? context.fetch(cardDescriptor).first) == nil {
            let due = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date)) ?? date
            context.insert(ReviewCard(id: cardId, kind: .mistake, front: wrong, back: right,
                                      hint: whyTamil ?? why, lessonId: nil, due: due, createdAt: date))
        }
    }
}
