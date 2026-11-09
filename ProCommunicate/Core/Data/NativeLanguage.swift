import Foundation

/// The learner's own language. The English side of the course is the same for everyone; each language
/// has its own content folder (meanings, explanations, mistake notes) under `content/<code>-en/`.
enum NativeLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case tamil = "ta"
    case hindi = "hi"

    static let settingsKey = "nativeLanguage"

    /// The language chosen in onboarding or Settings (Tamil until chosen).
    static var current: NativeLanguage {
        UserDefaults.standard.string(forKey: settingsKey).flatMap(NativeLanguage.init(rawValue:)) ?? .tamil
    }

    var id: String { rawValue }

    /// "Tamil", "Hindi".
    var name: String {
        switch self {
        case .tamil: "Tamil"
        case .hindi: "Hindi"
        }
    }

    /// The language's name in its own script.
    var nativeName: String {
        switch self {
        case .tamil: "தமிழ்"
        case .hindi: "हिन्दी"
        }
    }

    /// The script name used in AI instructions.
    var scriptName: String {
        switch self {
        case .tamil: "Tamil script"
        case .hindi: "Devanagari script"
        }
    }

    /// The language written in English letters.
    var romanisedName: String {
        switch self {
        case .tamil: "Tanglish"
        case .hindi: "Hinglish"
        }
    }

    var contentFolder: String { "\(rawValue)-en" }

    /// A city for the Indian side of role-plays.
    var officeCity: String {
        switch self {
        case .tamil: "Chennai"
        case .hindi: "Pune"
        }
    }

    /// An example request in the romanised language (for hints).
    var romanisedExample: String {
        switch self {
        case .tamil: "naalaikku client call la delay pathi sollanum"
        case .hindi: "kal client call mein delay ke baare mein batana hai"
        }
    }

    /// Placeholder for Ask in <language>.
    var askPlaceholder: String {
        switch self {
        case .tamil: "எப்படி சொல்வது? / eppadi solradhu?"
        case .hindi: "कैसे बोलूँ? / kaise bolun?"
        }
    }

    var askExample: String {
        switch self {
        case .tamil: "manager kitta naalaikku leave kekkanum, eppadi professional-a solradhu?"
        case .hindi: "manager se kal ki chhutti maangni hai, professional tarike se kaise bolun?"
        }
    }

    /// Fixed lines shown in the app in this language.
    enum Line { case tagline, whatDidYouHear, chooseCorrect, inMyLanguage, standUpYesterday, standUpToday, standUpBlockers }

    func text(_ line: Line) -> String {
        switch (self, line) {
        case (.tamil, .tagline): "Client meetings மற்றும் job interviews-இல் தெளிவான, professional ஆங்கிலம் பேச உதவும் app."
        case (.hindi, .tagline): "Client meetings और job interviews में साफ़, professional English बोलने में मदद करने वाला app।"
        case (.tamil, .whatDidYouHear): "நீங்கள் கேட்டது எது?"
        case (.hindi, .whatDidYouHear): "आपने क्या सुना?"
        case (.tamil, .chooseCorrect): "சரியான வாக்கியத்தைத் தேர்ந்தெடுங்கள்."
        case (.hindi, .chooseCorrect): "सही sentence चुनिए।"
        case (.tamil, .inMyLanguage): "தமிழில்"
        case (.hindi, .inMyLanguage): "हिंदी में"
        case (.tamil, .standUpYesterday): "நேற்று என்ன செய்தீர்கள்"
        case (.hindi, .standUpYesterday): "कल आपने क्या किया"
        case (.tamil, .standUpToday): "இன்று என்ன செய்யப் போகிறீர்கள்"
        case (.hindi, .standUpToday): "आज आप क्या करेंगे"
        case (.tamil, .standUpBlockers): "ஏதேனும் தடை இருக்கிறதா"
        case (.hindi, .standUpBlockers): "कोई blocker है क्या"
        }
    }

    /// Unicode block of the script.
    private var scriptRange: ClosedRange<UInt32> {
        switch self {
        case .tamil: 0x0B80...0x0BFF
        case .hindi: 0x0900...0x097F
        }
    }

    /// True if the text contains this language's script.
    func containsScript(_ text: String) -> Bool {
        text.unicodeScalars.contains { scriptRange.contains($0.value) }
    }

    /// How to write in this language, added to AI instructions.
    var styleNote: String {
        switch self {
        case .tamil:
            "Write simple, everyday spoken Tamil in Tamil script; keep English work words (meeting, deadline, testing, client) in English."
        case .hindi:
            "Write simple, everyday spoken Hindi as used in Indian offices, in Devanagari script; keep English work words (meeting, deadline, testing, client, project) in English. Avoid formal Sanskrit-heavy words."
        }
    }
}
