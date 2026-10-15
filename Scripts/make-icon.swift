import AppKit
import SwiftUI

// Иконка Agave Audio: розетка листьев агавы на зелёной плашке, без горшка и украшений.
// Сборка и запуск: Scripts/make-icon.sh

struct IconView: View {
    /// Те же листья, что у талисмана, только крупнее и из одной точки у нижнего края плашки.
    private let leaves: [(angle: Double, bend: Double, length: Double, halfWidth: Double)] = [
        (-70, -0.025, 0.36, 0.050),
        ( 70,  0.025, 0.36, 0.050),
        (-46, -0.035, 0.49, 0.058),
        ( 46,  0.035, 0.49, 0.058),
        (-22, -0.030, 0.61, 0.064),
        ( 22,  0.030, 0.61, 0.064),
        (  0,  0.000, 0.68, 0.070),
    ]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Theme.backgroundTop, Theme.background, Theme.backgroundDeep], startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)

            ZStack {
                ForEach(Array(leaves.enumerated()), id: \.offset) { _, leaf in
                    let shape = AgaveLeaf(angle: leaf.angle, bend: leaf.bend, length: leaf.length,
                                          halfWidth: leaf.halfWidth, origin: CGPoint(x: 0.5, y: 0.90))
                    shape
                        .fill(LinearGradient(colors: [Theme.leafTip, Theme.plantLight, Theme.plant], startPoint: .top, endPoint: .bottom))
                        .overlay { shape.stroke(Theme.plantOutline, lineWidth: 9) }
                }
            }
            .frame(width: 1024, height: 1024)
            .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
        }
        .frame(width: 1024, height: 1024)
        // Всё, включая тень, обрезается по плашке.
        .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous).inset(by: 100))
    }
}

@main
struct MakeIcon {
    @MainActor static func main() {
        let out = URL(fileURLWithPath: CommandLine.arguments[1])
        let sizes: [(String, Int)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]
        for (name, pixels) in sizes {
            let renderer = ImageRenderer(content: IconView())
            renderer.scale = CGFloat(pixels) / 1024
            guard let image = renderer.cgImage else { fatalError("не отрисовалось") }
            let rep = NSBitmapImageRep(cgImage: image)
            try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("\(name).png"))
        }
        print("иконка готова")
    }
}
