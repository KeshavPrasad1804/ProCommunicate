// Renders the app icon and launch image from the same SwiftUI LogoMark the app uses.
//
// Run from the repo root:
//   xcrun swiftc -parse-as-library tools/RenderBrand.swift ProCommunicate/App/Brand/LogoMark.swift -o build/render-brand && build/render-brand
import AppKit
import SwiftUI

@main
struct RenderBrand {
    static let assets = "ProCommunicate/Resources/Assets.xcassets"

    @MainActor
    static func main() throws {
        // App icon: 1024×1024, edge to edge, opaque (iOS rounds the corners itself).
        try render(LogoMark(style: .fullBleed), points: 1024, scale: 1, opaque: true,
                   to: "\(assets)/AppIcon.appiconset/AppIcon.png")

        // Launch image: a 120 pt rounded tile, the exact first frame of the animated intro.
        for scale in [2, 3] {
            try render(LogoMark(style: .tile), points: 120, scale: CGFloat(scale), opaque: false,
                       to: "\(assets)/LaunchLogo.imageset/LaunchLogo@\(scale)x.png")
        }
        print("Rendered app icon and launch logo.")
    }

    @MainActor
    static func render(_ view: some View, points: CGFloat, scale: CGFloat, opaque: Bool, to path: String) throws {
        let renderer = ImageRenderer(content: view.frame(width: points, height: points))
        renderer.scale = scale
        renderer.isOpaque = opaque
        guard let cgImage = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            throw NSError(domain: "RenderBrand", code: 1, userInfo: [NSLocalizedDescriptionKey: "Render failed: \(path)"])
        }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
        print("  \(path)  \(cgImage.width)×\(cgImage.height)")
    }
}
