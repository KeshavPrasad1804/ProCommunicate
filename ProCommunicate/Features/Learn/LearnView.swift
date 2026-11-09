import SwiftUI

/// Course map: tracks in priority order, each with its units.
struct LearnView: View {
    let course: Course

    var body: some View {
        NavigationStack {
            List {
                ForEach(course.tracksByPriority) { track in
                    Section {
                        ForEach(track.units) { unit in
                            NavigationLink(value: unit) {
                                HStack(spacing: 12) {
                                    Text("\(unit.number)")
                                        .font(.subheadline.monospacedDigit().weight(.semibold))
                                        .frame(width: 28, height: 28)
                                        .background(.tint.opacity(0.12), in: Circle())
                                        .foregroundStyle(.tint)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(unit.title).font(.body)
                                        Text(unit.goal)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                    } header: {
                        Label(track.title, systemImage: track.systemImage)
                    } footer: {
                        Text(track.subtitle)
                    }
                }
            }
            .navigationTitle("Learn")
            .navigationDestination(for: CourseUnit.self) { unit in
                UnitDetailView(unit: unit)
            }
        }
    }
}

struct UnitDetailView: View {
    let unit: CourseUnit

    var body: some View {
        List {
            Section("You will be able to") {
                Text(unit.goal)
            }
            Section("Key phrases") {
                ForEach(unit.examplePhrases, id: \.self) { phrase in
                    Label(phrase, systemImage: "quote.opening")
                }
            }
            Section {
                FeatureRow(systemImage: "play.circle.fill", title: "Start lesson",
                           detail: "Listen, repeat, and use the phrases in your own sentences.", phase: "1")
                FeatureRow(systemImage: "phone.fill", title: "Practise on a call",
                           detail: "A short voice role-play using this unit's phrases.", phase: "3")
            }
        }
        .navigationTitle(unit.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview { LearnView(course: .preview) }
