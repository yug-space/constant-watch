import AppKit
import SwiftUI
import Foundation

@main struct IconGenerator {
    @MainActor static func main() throws {
        let folder = URL(fileURLWithPath: "build/AppIcon.iconset")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = size * scale
                let renderer = ImageRenderer(content: ConstantAppIcon(size: CGFloat(pixels)))
                renderer.scale = 1
                guard let image = renderer.cgImage else { throw NSError(domain: "IconGeneration", code: 1) }
                let rep = NSBitmapImageRep(cgImage: image)
                let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
                try rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(filename))
            }
        }
    }
}
