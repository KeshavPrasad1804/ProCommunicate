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
    case unavailable, notLoaded, modelLoadFailed, contextFailed, tokenizeFailed, decodeFailed(Int32), grammarFailed, contextFull

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
        }
    }
}

/// Runs Gemma on the iPhone with llama.cpp: GPU (Metal), memory-mapped weights, lazy per-layer
/// embeddings and a q8_0 KV cache, as measured in PLAN.md "Keeping memory low".
/// All llama.cpp calls happen on one serial queue; the prompt cache is reused between turns.
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

    #if canImport(llama)
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var cachedTokens: [llama_token] = []
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
    func load(modelPath: String, contextSize: Int32 = 4096) async throws -> Double {
        try await onQueue { try self.loadOnQueue(path: modelPath, contextSize: contextSize) }
    }

    func unload() async {
        _ = try? await onQueue { self.unloadOnQueue() }
    }

    /// Generates a reply for a full prompt. Calls `onPiece` with text as it arrives.
    func generate(prompt: String, options: GenerationOptions = .init(),
                  onPiece: @escaping @Sendable (String) -> Void = { _ in }) async throws -> (text: String, stats: GenerationStats) {
        try await onQueue { try self.generateOnQueue(prompt: prompt, options: options, onPiece: onPiece) }
    }

    // MARK: - Queue-confined implementation

    private func unloadOnQueue() {
        #if canImport(llama)
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        context = nil
        model = nil
        cachedTokens = []
        #endif
        loadedPath = nil
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
        contextParams.n_seq_max = 1
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
        cachedTokens = []
        loadedPath = path
        loadedContextSize = contextSize
        return Date().timeIntervalSince(start)
        #else
        throw LlamaError.unavailable
        #endif
    }

    private func generateOnQueue(prompt: String, options: GenerationOptions,
                                 onPiece: @Sendable (String) -> Void) throws -> (text: String, stats: GenerationStats) {
        #if canImport(llama)
        guard let model, let context else { throw LlamaError.notLoaded }
        let vocab = llama_model_get_vocab(model)
        var stats = GenerationStats()

        // Tokenize (adds <bos>, understands <|turn> / <turn|>).
        var tokens = try tokenize(prompt, vocab: vocab)
        let contextSize = Int(llama_n_ctx(context))
        guard tokens.count + options.maxTokens < contextSize else { throw LlamaError.contextFull }
        stats.promptTokens = tokens.count

        // Reuse the part of the prompt that is already in the KV cache from the last turn.
        let memory = llama_get_memory(context)
        var common = 0
        while common < min(cachedTokens.count, tokens.count) - 1, cachedTokens[common] == tokens[common] { common += 1 }
        if common < cachedTokens.count {
            if !llama_memory_seq_rm(memory, 0, llama_pos(common), -1) {
                llama_memory_clear(memory, true)
                common = 0
            }
        }
        cachedTokens = Array(cachedTokens.prefix(common))
        stats.reusedTokens = common

        // Read the new part of the prompt in batches.
        let promptStart = Date()
        var index = common
        while index < tokens.count {
            let end = min(index + 512, tokens.count)
            let result = tokens.withUnsafeMutableBufferPointer { buffer in
                llama_decode(context, llama_batch_get_one(buffer.baseAddress! + index, Int32(end - index)))
            }
            guard result == 0 else { cachedTokens = []; llama_memory_clear(memory, true); throw LlamaError.decodeFailed(result) }
            cachedTokens.append(contentsOf: tokens[index..<end])
            index = end
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
            var token = llama_sampler_sample(chain, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            output.append(piece(for: token, vocab: vocab))
            stats.generatedTokens += 1
            // Emit only complete UTF-8 (Tamil characters span several tokens).
            if let text = String(data: output, encoding: .utf8), text.count > emittedCount {
                onPiece(String(text.dropFirst(emittedCount)))
                emittedCount = text.count
            }
            let result = llama_decode(context, llama_batch_get_one(&token, 1))
            guard result == 0 else { throw LlamaError.decodeFailed(result) }
            cachedTokens.append(token)
            if cachedTokens.count >= contextSize - 1 { break }
        }
        stats.generationSeconds = Date().timeIntervalSince(generationStart)
        tokens.removeAll()
        let text = String(decoding: output, as: UTF8.self)
        return (GemmaPrompt.clean(text), stats)
        #else
        throw LlamaError.unavailable
        #endif
    }

    #if canImport(llama)
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
