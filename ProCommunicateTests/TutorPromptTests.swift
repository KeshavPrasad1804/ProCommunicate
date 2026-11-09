import Foundation
import Testing
@testable import ProCommunicate

@Suite("Gemma prompt format")
struct GemmaPromptTests {
    @Test func matchesTheModelsOwnTemplate() {
        // Expected output taken from llama-server /apply-template with the real Gemma 4 E2B file.
        let prompt = GemmaPrompt.format([
            ChatMessage(role: .system, content: "SYS"),
            ChatMessage(role: .user, content: "U1"),
            ChatMessage(role: .assistant, content: "A1"),
            ChatMessage(role: .user, content: "U2"),
        ])
        #expect(prompt == "<|turn>system\nSYS<turn|>\n<|turn>user\nU1<turn|>\n<|turn>model\nA1<turn|>\n<|turn>user\nU2<turn|>\n<|turn>model\n")
    }

    @Test func cleansStrayTurnMarkers() {
        #expect(GemmaPrompt.clean("Hello there.<turn|>\n") == "Hello there.")
    }
}

@Suite("Answer check parsing")
struct AnswerCheckParsingTests {
    let answer = "Myself Karthik and I am having two years of experience in sales."

    @Test func keepsRealMistakes() throws {
        let json = #"{"better": "I am Karthik, and I have two years of experience in sales.", "mistakes": [{"wrong": "Myself Karthik", "right": "I am Karthik", "type": "grammar", "why": "Don't start with myself."}]}"#
        let check = try #require(TutorPrompts.parseAnswerCheck(json, answer: answer))
        #expect(check.mistakes.count == 1)
        #expect(check.better.hasPrefix("I am Karthik"))
    }

    @Test func dropsNoChangeAndInventedQuotes() throws {
        let json = #"{"better": "x", "mistakes": [{"wrong": "since 2021", "right": "since 2021", "type": "grammar", "why": "-"}, {"wrong": "I was having", "right": "I had", "type": "grammar", "why": "-"}, {"wrong": "I am having", "right": "I have", "type": "grammar", "why": "-"}]}"#
        let check = try #require(TutorPrompts.parseAnswerCheck(json, answer: answer))
        #expect(check.mistakes.map(\.wrong) == ["I am having"])
    }

    @Test func badJSONReturnsNil() {
        #expect(TutorPrompts.parseAnswerCheck("{\"better\": ", answer: answer) == nil)
    }

    @Test func grammarAllowsAtMostThreeMistakes() {
        #expect(TutorPrompts.answerCheckGrammar.contains("( ws \",\" ws mistake ){0,2}"))
    }
}
