import SwiftUI

/// Small label showing which build phase a feature arrives in.
struct PhaseBadge: View {
    let phase: String

    var body: some View {
        Text("Phase \(phase)")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.tint.opacity(0.12), in: Capsule())
            .foregroundStyle(.tint)
            .accessibilityLabel("Coming in phase \(phase)")
    }
}

/// A row with an icon, a title, a short description and an optional phase badge.
struct FeatureRow: View {
    let systemImage: String
    let title: String
    let detail: String
    var phase: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.headline)
                    Spacer(minLength: 8)
                    if let phase { PhaseBadge(phase: phase) }
                }
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}
