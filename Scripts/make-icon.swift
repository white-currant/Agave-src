import AppKit
import Foundation

// Рисует иконку Agave: розетка агавы на скруглённом квадрате с тёплым
// терракотовым градиентом — цвет пустынной глины, родной среды растения.

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])

func draw(into context: CGContext, side: CGFloat) {
    let scale = side / 1024
    // Сетка иконок macOS: полотно 1024, само изображение 824 со скруглением 185.
    let inset = 100.0 * scale
    let rect = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let radius = 185.0 * scale

    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.saveGState()
    context.addPath(path)
    context.clip()

    // Тёплая терракота, тот же тон, что у акцентного цвета приложения.
    let colors = [
        CGColor(srgbRed: 0.855, green: 0.494, blue: 0.322, alpha: 1),
        CGColor(srgbRed: 0.639, green: 0.306, blue: 0.173, alpha: 1),
    ] as CFArray
    if let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]
    ) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: []
        )
    }

    // Розетка агавы. Листьев намеренно немного и они широкие: на значке в
    // 16 точек тонкие лучи превращаются в кашу.
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))

    let base = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.19)

    // Каждый лист слегка уводится наружу (`bend` — смещение кончика вбок):
    // без изгиба симметричные лучи из одной точки читаются как лист конопли.
    // Порядок важен — сначала крайние, центральные ложатся поверх, как в живой
    // розетке. Обводка обязательна: без неё белые листья сливаются в пятно.
    let leaves: [(angle: CGFloat, bend: CGFloat, length: CGFloat, halfWidth: CGFloat)] = [
        ( -78,  -70, 300, 52),
        (  78,   70, 300, 52),
        ( -54,  -80, 395, 60),
        (  54,   80, 395, 60),
        ( -28,  -60, 470, 68),
        (  28,   60, 470, 68),
        (   0,    0, 505, 72),
    ]

    for leaf in leaves {
        let radians = leaf.angle * .pi / 180
        let length = leaf.length * scale
        let halfWidth = leaf.halfWidth * scale
        let bend = leaf.bend * scale

        // Лист строим в своей системе координат остриём вверх, затем поворачиваем.
        func place(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: base.x + x * cos(radians) - y * sin(radians),
                y: base.y + x * sin(radians) + y * cos(radians)
            )
        }

        // Лист расширяется к трети высоты, дальше плавно сходится к притупленному
        // кончику: острая игла на мелком значке всё равно пропадает.
        // Листья начинаются не из одной точки, а с небольшого выноса вдоль своей
        // оси — иначе все обводки сходятся внизу в тёмный ком.
        let origin = 70 * scale
        let tip = halfWidth * 0.14
        let path = CGMutablePath()
        path.move(to: place(-halfWidth, origin))
        path.addCurve(
            to: place(bend - tip, origin + length),
            control1: place(-halfWidth * 1.05, origin + length * 0.30),
            control2: place(bend * 0.42 - halfWidth * 0.7, origin + length * 0.78)
        )
        path.addQuadCurve(
            to: place(bend + tip, origin + length),
            control: place(bend, origin + length * 1.04)
        )
        path.addCurve(
            to: place(halfWidth, origin),
            control1: place(bend * 0.42 + halfWidth * 0.7, origin + length * 0.78),
            control2: place(halfWidth * 1.05, origin + length * 0.30)
        )
        // Основание скруглённое, а не срезанное по прямой.
        path.addQuadCurve(
            to: place(-halfWidth, origin),
            control: place(0, origin - halfWidth * 0.75)
        )
        path.closeSubpath()

        context.addPath(path)
        context.setStrokeColor(CGColor(srgbRed: 0.416, green: 0.184, blue: 0.098, alpha: 1))
        context.setLineWidth(16 * scale)
        context.setLineJoin(.round)
        context.drawPath(using: .fillStroke)
    }

    context.restoreGState()
}

for (name, pixels) in sizes {
    guard let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { continue }

    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high
    draw(into: context, side: CGFloat(pixels))

    guard let image = context.makeImage() else { continue }
    let destination = outputDirectory.appendingPathComponent("\(name).png")
    let representation = NSBitmapImageRep(cgImage: image)
    guard let data = representation.representation(using: .png, properties: [:]) else { continue }
    try data.write(to: destination)
    print("\(name).png — \(pixels)×\(pixels)")
}
