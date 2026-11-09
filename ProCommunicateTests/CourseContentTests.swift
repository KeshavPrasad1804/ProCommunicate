import Foundation
import Testing
@testable import ProCommunicate

@Suite("Course content")
struct CourseContentTests {
    let course: Course

    init() throws {
        course = try ContentLoader.loadCourse()
    }

    @Test func isTamilToEnglish() {
        #expect(course.sourceLang == "ta")
        #expect(course.targetLang == "en")
    }

    @Test func meetingsComeFirstThenInterviews() {
        #expect(course.tracksByPriority.map(\.id) == ["meetings", "interviews"])
    }

    @Test func trackUnitCountsMatchFeatures() throws {
        let byId = Dictionary(uniqueKeysWithValues: course.tracks.map { ($0.id, $0) })
        #expect(try #require(byId["meetings"]).units.count == 12)
        #expect(try #require(byId["interviews"]).units.count == 10)
    }

    @Test func idsAreUnique() {
        let trackIds = course.tracks.map(\.id)
        let unitIds = course.tracks.flatMap(\.units).map(\.id)
        #expect(Set(trackIds).count == trackIds.count)
        #expect(Set(unitIds).count == unitIds.count)
    }

    @Test func unitsAreNumberedInOrderFromOne() {
        for track in course.tracks {
            #expect(track.units.map(\.number) == Array(1...track.units.count), "track \(track.id)")
        }
    }

    @Test func everyUnitHasAGoalAndPhrases() {
        for unit in course.tracks.flatMap(\.units) {
            #expect(!unit.goal.isEmpty, "unit \(unit.id)")
            #expect(!unit.examplePhrases.isEmpty, "unit \(unit.id)")
        }
    }

    /// The course teaches the professional alternative to these, so they must never appear as model phrases.
    @Test func phrasesAvoidCommonIndianEnglishMistakes() {
        let banned = ["revert back", "do the needful", "today itself", "discuss about", "myself ", "i am having"]
        for phrase in course.tracks.flatMap(\.units).flatMap(\.examplePhrases) {
            let lower = phrase.lowercased()
            for bad in banned {
                #expect(!lower.contains(bad), "\"\(phrase)\" contains \"\(bad)\"")
            }
        }
    }
}
