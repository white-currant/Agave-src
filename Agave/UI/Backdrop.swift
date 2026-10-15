import SwiftUI

/// Широкий лист с центральной жилкой. Рисуется черешком в нижней точке,
/// остриём вверх; поворачивать снаружи через `rotationEffect`.
struct TropicalLeaf: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control1: CGPoint(x: rect.minX - w * 0.05, y: rect.maxY - h * 0.35),
            control2: CGPoint(x: rect.minX + w * 0.2, y: rect.minY + h * 0.08)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: rect.maxX - w * 0.2, y: rect.minY + h * 0.08),
            control2: CGPoint(x: rect.maxX + w * 0.05, y: rect.maxY - h * 0.35)
        )
        path.closeSubpath()
        return path
    }
}

/// Центральная жилка и боковые прожилки листа.
///
/// Боковые прожилки нарочно длиннее половины ширины листа: снаружи их обрезает
/// форма самого листа (`clipShape(TropicalLeaf())`), поэтому каждая кончается
/// ровно на краю, как бы лист ни сужался.
struct LeafVeins: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        let reach = rect.width * 0.6
        for step in 1...7 {
            let y = rect.maxY - rect.height * (0.08 + Double(step) * 0.11)
            let rise = rect.height * 0.12
            path.move(to: CGPoint(x: rect.midX, y: y))
            path.addQuadCurve(to: CGPoint(x: rect.midX - reach, y: y - rise),
                              control: CGPoint(x: rect.midX - reach * 0.35, y: y - rise * 0.15))
            path.move(to: CGPoint(x: rect.midX, y: y))
            path.addQuadCurve(to: CGPoint(x: rect.midX + reach, y: y - rise),
                              control: CGPoint(x: rect.midX + reach * 0.35, y: y - rise * 0.15))
        }
        return path
    }
}

/// Фон окна: полумрак тропического леса, крупные листья по краям и косые лучи сквозь полог.
/// Листья медленно колышутся; движение еле заметное, чтобы не отвлекать от списка.
struct Backdrop: View {
    private struct Frond {
        var x: Double      // доля ширины
        var y: Double      // доля высоты
        var width: Double  // в точках
        var height: Double
        var angle: Double
        var tone: Int      // 0 — тёмный, 1 — средний, 2 — светлый
        var phase: Double
    }

    private static let fronds: [Frond] = [
        // Левый нижний угол — густые заросли.
        Frond(x: 0.02, y: 1.04, width: 170, height: 330, angle: 38, tone: 0, phase: 0.0),
        Frond(x: -0.02, y: 0.92, width: 140, height: 260, angle: 62, tone: 1, phase: 1.3),
        Frond(x: 0.10, y: 1.08, width: 120, height: 220, angle: 14, tone: 2, phase: 2.1),
        // Правый нижний угол.
        Frond(x: 0.98, y: 1.06, width: 180, height: 340, angle: -34, tone: 0, phase: 0.7),
        Frond(x: 1.03, y: 0.88, width: 130, height: 250, angle: -66, tone: 1, phase: 2.6),
        // Свисают сверху справа.
        Frond(x: 0.86, y: -0.08, width: 150, height: 280, angle: 200, tone: 0, phase: 1.9),
        Frond(x: 0.97, y: -0.04, width: 110, height: 210, angle: 228, tone: 1, phase: 0.4),
        // И сверху слева, за кнопками окна.
        Frond(x: 0.18, y: -0.10, width: 120, height: 230, angle: 160, tone: 1, phase: 3.0),
    ]

    var body: some View {
        GeometryReader { geometry in
            let time = AnimationClock.shared.time
            Group {
                ZStack {
                    LinearGradient(
                        colors: [Theme.backgroundTop, Theme.background, Theme.backgroundDeep],
                        startPoint: .top, endPoint: .bottom
                    )

                    rays(in: geometry.size, time: time)

                    ForEach(Array(Self.fronds.enumerated()), id: \.offset) { _, frond in
                        leaf(frond, time: time)
                            .position(x: frond.x * geometry.size.width, y: frond.y * geometry.size.height)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func leaf(_ frond: Frond, time: TimeInterval) -> some View {
        let color: Color = switch frond.tone {
        case 0: Theme.leafDeep
        case 1: Theme.leaf
        default: Theme.leafLight
        }
        let sway = sin(time * 0.45 + frond.phase) * 2.2
        return ZStack {
            TropicalLeaf()
                .fill(LinearGradient(colors: [color.opacity(0.95), color.opacity(0.7)], startPoint: .top, endPoint: .bottom))
            LeafVeins()
                .stroke(Color.black.opacity(0.18), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .clipShape(TropicalLeaf())
        }
        .frame(width: frond.width, height: frond.height)
        .opacity(frond.tone == 2 ? 0.55 : 0.8)
        // Вращаем вокруг черешка, чтобы лист качался, а не плавал.
        .rotationEffect(.degrees(frond.angle + sway), anchor: .bottom)
        .offset(y: -frond.height / 2)
    }

    private func rays(in size: CGSize, time: TimeInterval) -> some View {
        ZStack {
            ForEach(0..<3) { index in
                let shimmer = 0.06 + 0.025 * sin(time * 0.3 + Double(index) * 1.7)
                Rectangle()
                    .fill(
                        LinearGradient(colors: [Theme.sun.opacity(shimmer), .clear],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: size.width * (0.10 + Double(index) * 0.05), height: size.height * 1.4)
                    .rotationEffect(.degrees(24))
                    .position(x: size.width * (0.35 + Double(index) * 0.17), y: size.height * 0.35)
                    .blur(radius: 18)
            }
        }
    }
}
