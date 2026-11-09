import Testing
@testable import ProCommunicate

@Suite("Mistake rules")
struct MistakeRuleTests {
    @Test(arguments: [
        ("Good morning sir. Myself Priya and I have three years of experience.", "myself-intro"),
        ("I am having three years experience in Java.", "am-having"),
        ("I am working in Infosys since 2021.", "since-continuous"),
        ("I will revert back by tomorrow.", "revert-back"),
        ("Please revert to me with the status.", "revert-to-me"),
        ("Please send it today itself.", "itself"),
        ("Kindly do the needful and send the files.", "do-the-needful"),
        ("We discussed about the budget yesterday.", "discuss-about"),
        ("I have one doubt about the timeline.", "doubt-question"),
        ("Can we prepone the demo to Monday?", "prepone"),
        ("What is your good name?", "good-name"),
        ("My cousin brother's wedding was on Sunday.", "cousin-brother"),
        ("I passed out in 2019 from Anna University.", "passed-out"),
        ("Waiting for the updation of the sheet.", "updation"),
        ("Please share the details of the same.", "the-same"),
        ("I will be out of station next week.", "out-of-station"),
        ("My native is Madurai.", "my-native"),
        ("Please do one thing, send me the logs.", "do-one-thing"),
        ("The build is fine only.", "only-emphasis"),
        ("I didn't went to office yesterday.", "did-past"),
        ("This approach is more better.", "more-better"),
    ])
    func catchesThePattern(sentence: String, ruleId: String) {
        #expect(MistakeRules.check(sentence).map(\.ruleId).contains(ruleId), "\(sentence)")
    }

    @Test(arguments: [
        "I'm Priya, and I have three years of experience in Java.",
        "I have been working at Infosys since 2021.",
        "I'll get back to you by tomorrow.",
        "I did it myself last week.",
        "We discussed the budget yesterday.",
        "I have a question about the timeline.",
        "Could we bring the demo forward to Monday?",
        "I'm having lunch with the team.",
        "I graduated in 2019 from Anna University.",
        "Tamil is my native language.",
        "Only two members are on leave.",
        "I didn't go to the office yesterday.",
        "This approach is much better.",
        "I'm working on the payment service today.",
    ])
    func leavesCorrectSentencesAlone(sentence: String) {
        #expect(MistakeRules.check(sentence).isEmpty, "\(sentence): \(MistakeRules.check(sentence).map(\.ruleId))")
    }

    @Test func everyRuleHasATamilExplanationAndValidPattern() throws {
        for rule in MistakeRules.all {
            #expect(rule.whyTamil.unicodeScalars.contains { (0x0B80...0x0BFF).contains($0.value) }, "\(rule.id)")
            #expect(throws: Never.self) { try NSRegularExpression(pattern: rule.pattern, options: .caseInsensitive) }
        }
        #expect(Set(MistakeRules.all.map(\.id)).count == MistakeRules.all.count)
    }

    @Test func fluencyNumbers() {
        #expect(FluencyMetrics.wordCount("Hello, I'm Priya. 80% done.") == 4)
        #expect(FluencyMetrics.wordsPerMinute(words: 120, seconds: 60) == 120)
        #expect(FluencyMetrics.fillerCount("Um, actually I basically finished it, you know.") == 4)
        #expect(FluencyMetrics.fillerCount("The actual result is basic.") == 0)
    }
}

import Foundation
