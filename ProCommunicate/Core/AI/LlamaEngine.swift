import Foundation
import os
#if canImport(llama)
import llama
#endif

struct GenerationOptions: Sendable {
    var maxTokens: Int = 256
    var temperature: Float = 0.7
    var topK: Int32 = 40
    var topP: Float = 0.95
    var minP: Float = 0.05
    /// GBNF grammar the output must follow (for JSON answers).
    var grammar: String?
    var seed: UInt32 = UInt32.random(in: 1...UInt32.max)
}

/// Separate slots in the model's memory, so a conversation's cached prompt survives a
/// side job (like checking an answer) and the next reply doesn't re-read the whole call.
enum LlamaSlot: Int32, Sendable {
    case conversation = 0
    case utility = 1
}

struct GenerationStats: Sendable, Equatable {
    var promptTokens = 0
    /// Tokens of the prompt that were already in the cache from the previous turn.
    var reusedTokens = 0
    var generatedTokens = 0
    var promptSeconds: Double = 0
    var generationSeconds: Double = 0

    var tokensPerSecond: Double { generationSeconds > 0 ? Double(generatedTokens) / generationSeconds : 0 }
    /// Time from sending the prompt to the first generated token.
    var firstTokenSeconds: Double { promptSeconds + (generatedTokens > 0 ? generationSeconds / Double(generatedTokens) : 0) }
}

enum LlamaError: LocalizedError {
    case unavailable, notLoaded, modelLoadFailed, contextFailed, tokenizeFailed, decodeFailed(Int32), grammarFailed, contextFull, cancelled

    var errorDescription: String? {
        switch self {
        case .unavailable: "The AI engine only runs on a real iPhone, not in the Simulator."
        case .notLoaded: "The AI model isn't loaded."
        case .modelLoadFailed: "The AI model couldn't be loaded."
        case .contextFailed: "The AI couldn't start (not enough memory?)."
        case .tokenizeFailed: "The text couldn't be prepared for the AI."
        case .decodeFailed(let code): "The AI stopped with an error (\(code))."
        case .grammarFailed: "The answer format couldn't be set up."
        case .contextFull: "The conversation is too long for the AI's memory."
        case .cancelled: "Stopped."
        }
    }
}

/// Runs Gemma on the iPhone with llama.cpp: GPU (Metal), memory-mapped weights, lazy per-layer
/// embeddings and a q8_0 KV cache, as measured in PLAN.md "Keeping memory low".
/// All llama.cpp calls happen on one serial queue. Two memory slots (see `LlamaSlot`) keep the
/// conversation's prompt cache while answer checks run.
final class LlamaEngine: @unchecked Sendable {
    static let shared = LlamaEngine()

    static var isAvailable: Bool {
        #if canImport(llama)
        true
        #else
        false
        #endif
    }

    private let queue = DispatchQueue(label: "dev.procommunicate.llama", qos: .userInitiated)
    private let cancelRequested = OSAllocatedUnfairLock(initialState: false)

    #if canImport(llama)
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var cachedTokens: [Int32: [llama_token]] = [:]
    private static let backendInit: Void = { llama_backend_init() }()
    #endif
    private var loadedPath: String?
    private var loadedContextSize: Int32 = 0

    private func onQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try work() }) }
        }
    }

    func isLoaded() async -> Bool {
        (try? await onQueue { self.loadedPath != nil }) ?? false
    }

    /// Loads the model (no-op if the same file and context size are already loaded). Returns seconds taken.
    @discardableResult
    func load(modelPath: String, contextSize: Int32 = 8192) async throws -> Double {
        try await onQueue { try self.loadOnQueue(path: modelPath, contextSize: contextSize) }
    }

    func unload() async {
        _ = try? await onQueue { self.unloadOnQueue() }
    }

    /// Stops the generation that is running now (it throws `LlamaError.cancelled`).
    func cancelCurrent() {
        cancelRequested.withLock { $0 = true }
    }

    /// Forgets a slot's cached prompt (e.g. when a new call starts).
    func reset(_ slot: LlamaSlot) async {
        _ = try? await onQueue { self.resetOnQueue(slot) }
    }

    /// Generates a reply for a full prompt. Calls `onPiece` with text as it arrives.
    func generate(prompt: String, slot: LlamaSlot = .conversation, options: GenerationOptions = .init(),
                  onPiece: @escaping @Sendable (String) -> Void = { _ in }) async throws -> (text: String, stats: GenerationStats) {
        try await onQueue {
            self.cancelRequested.withLock { $0 = false }
            return try self.generateOnQueue(prompt: prompt, slot: slot, options: options, onPiece: onPiece)
        }
    }

    // MARK: - Queue-confined implementation

    private func unloadOnQueue() {
        #if canImport(llama)
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        context = nil
        model = nil
        cachedTokens = [:]
        #endif
        loadedPath = nil
    }

    private func resetOnQueue(_ slot: LlamaSlot) {
        #if canImport(llama)
        guard let context else { return }
        _ = llama_memory_seq_rm(llama_get_memory(context), slot.rawValue, 0, -1)
        cachedTokens[slot.rawValue] = []
        #endif
    }

    private func loadOnQueue(path: String, contextSize: Int32) throws -> Double {
        #if canImport(llama)
        if loadedPath == path, loadedContextSize == contextSize, context != nil { return 0 }
        unloadOnQueue()
        _ = Self.backendInit
        let start = Date()

        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 99                    // everything on the GPU (Metal)
        modelParams.load_mode = LLAMA_LOAD_MODE_MMAP     // weights stay file-backed: not counted against the app
        modelParams.lazy_mode = LLAMA_LAZY_MODE_ON       // per-layer embeddings read on demand: ~half the RAM
        guard let model = llama_model_load_from_file(path, modelParams) else { throw LlamaError.modelLoadFailed }

        var contextParams = llama_context_default_params()
        contextParams.n_ctx = UInt32(contextSize)
        contextParams.n_batch = 512
        contextParams.n_ubatch = 512
        contextParams.n_seq_max = 2                      // conversation + utility slots
        contextParams.kv_unified = true
        contextParams.n_threads = 4
        contextParams.n_threads_batch = 4
        contextParams.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED
        contextParams.type_k = GGML_TYPE_Q8_0
        contextParams.type_v = GGML_TYPE_Q8_0
        contextParams.swa_full = true                    // lets the next turn reuse the cached prompt
        contextParams.no_perf = true
        guard let context = llama_init_from_model(model, contextParams) else {
            llama_model_free(model)
            throw LlamaError.contextFailed
        }
        self.model = model
        self.context = context
        cachedTokens = [:]
        loadedPath = path
        loadedContextSize = contextSize
        return Date().timeIntervalSince(start)
        #else
        throw LlamaError.unavailable
        #endif
    }

    private func generateOnQueue(prompt: String, slot: LlamaSlot, options: GenerationOptions,
                                 onPiece: @Sendable (String) -> Void) throws -> (text: String, stats: GenerationStats) {
        #if canImport(llama)
        guard let model, let context else { throw LlamaError.notLoaded }
        let vocab = llama_model_get_vocab(model)
        let seq = slot.rawValue
        let memory = llama_get_memory(context)
        var stats = GenerationStats()

        // Tokenize (adds <bos>, understands <|turn> / <turn|>).
        let tokens = try tokenize(prompt, vocab: vocab)
        let contextSize = Int(llama_n_ctx(context))
        let otherSlotsUsed = cachedTokens.filter { $0.key != seq }.values.reduce(0) { $0 + $1.count }
        guard tokens.count + options.maxTokens + otherSlotsUsed < contextSize else { throw LlamaError.contextFull }
        stats.promptTokens = tokens.count

        // Reuse the part of the prompt already cached in this slot (at least the last token is re-read
        // so there are fresh logits to sample from).
        var cached = cachedTokens[seq] ?? []
        var common = 0
        while common < min(cached.count, tokens.count) - 1, cached[common] == tokens[common] { common += 1 }
        if common < cached.count {
            if !llama_memory_seq_rm(memory, seq, llama_pos(common), -1) {
                _ = llama_memory_seq_rm(memory, seq, 0, -1)
                common = 0
            }
            cached = Array(cached.prefix(common))
        }
        cachedTokens[seq] = cached
        stats.reusedTokens = common

        // Read the new part of the prompt in batches of up to 512 tokens.
        let promptStart = Date()
        var index = common
        while index < tokens.count {
            let end = min(index + 512, tokens.count)
            try decode(Array(tokens[index..<end]), startPos: index, seq: seq, logitsForLast: end == tokens.count)
            cachedTokens[seq, default: []].append(contentsOf: tokens[index..<end])
            index = end
            if cancelRequested.withLock({ $0 }) { throw LlamaError.cancelled }
        }
        stats.promptSeconds = Date().timeIntervalSince(promptStart)

        // Sampler chain: grammar (optional) → top-k → top-p → min-p → temperature → random pick.
        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())
        defer { llama_sampler_free(chain) }
        if let grammar = options.grammar {
            guard let grammarSampler = llama_sampler_init_grammar(vocab, grammar, "root") else { throw LlamaError.grammarFailed }
            llama_sampler_chain_add(chain, grammarSampler)
        }
        if options.temperature <= 0 {
            llama_sampler_chain_add(chain, llama_sampler_init_greedy())
        } else {
            llama_sampler_chain_add(chain, llama_sampler_init_top_k(options.topK))
            llama_sampler_chain_add(chain, llama_sampler_init_top_p(options.topP, 1))
            llama_sampler_chain_add(chain, llama_sampler_init_min_p(options.minP, 1))
            llama_sampler_chain_add(chain, llama_sampler_init_temp(options.temperature))
            llama_sampler_chain_add(chain, llama_sampler_init_dist(options.seed))
        }

        // Generate.
        let generationStart = Date()
        var output = Data()
        var emittedCount = 0
        for _ in 0..<options.maxTokens {
            if cancelRequested.withLock({ $0 }) { throw LlamaError.cancelled }
            let token = llama_sampler_sample(chain, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            output.append(piece(for: token, vocab: vocab))
            stats.generatedTokens += 1
            // Emit only complete UTF-8 (Tamil characters span several tokens).
            if let text = String(data: output, encoding: .utf8), text.count > emittedCount {
                onPiece(String(text.dropFirst(emittedCount)))
                emittedCount = text.count
            }
            let position = cachedTokens[seq, default: []].count
            try decode([token], startPos: position, seq: seq, logitsForLast: true)
            cachedTokens[seq, default: []].append(token)
            if position + otherSlotsUsed >= contextSize - 2 { break }
        }
        stats.generationSeconds = Date().timeIntervalSince(generationStart)
        return (GemmaPrompt.clean(String(decoding: output, as: UTF8.self)), stats)
        #else
        throw LlamaError.unavailable
        #endif
    }

    #if canImport(llama)
    /// Decodes tokens into one slot at explicit positions.
    private func decode(_ tokens: [llama_token], startPos: Int, seq: Int32, logitsForLast: Bool) throws {
        guard let context else { throw LlamaError.notLoaded }
        var batch = llama_batch_init(Int32(tokens.count), 0, 1)
        defer { llama_batch_free(batch) }
        for (i, token) in tokens.enumerated() {
            batch.token[i] = token
            batch.pos[i] = llama_pos(startPos + i)
            batch.n_seq_id[i] = 1
            batch.seq_id[i]![0] = seq
            batch.logits[i] = (logitsForLast && i == tokens.count - 1) ? 1 : 0
        }
        batch.n_tokens = Int32(tokens.count)
        let result = llama_decode(context, batch)
        guard result == 0 else {
            _ = llama_memory_seq_rm(llama_get_memory(context), seq, 0, -1)
            cachedTokens[seq] = []
            throw LlamaError.decodeFailed(result)
        }
    }

    private func tokenize(_ text: String, vocab: OpaquePointer?) throws -> [llama_token] {
        let utf8Count = Int32(text.utf8.count)
        var tokens = [llama_token](repeating: 0, count: Int(utf8Count) + 8)
        var count = llama_tokenize(vocab, text, utf8Count, &tokens, Int32(tokens.count), true, true)
        if count < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-count))
            count = llama_tokenize(vocab, text, utf8Count, &tokens, Int32(tokens.count), true, true)
        }
        guard count >= 0 else { throw LlamaError.tokenizeFailed }
        return Array(tokens.prefix(Int(count)))
    }

    private func piece(for token: llama_token, vocab: OpaquePointer?) -> Data {
        var buffer = [CChar](repeating: 0, count: 64)
        var length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        if length < 0 {
            buffer = [CChar](repeating: 0, count: Int(-length))
            length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        }
        guard length > 0 else { return Data() }
        return buffer.prefix(Int(length)).withUnsafeBytes { Data($0) }
    }
    #endif
}

/// How much memory the app is using, as iOS counts it, and how much is left before iOS would close it.
enum MemoryUsage {
    static func footprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    static func availableBytes() -> UInt64 {
        UInt64(os_proc_available_memory())
    }
}
