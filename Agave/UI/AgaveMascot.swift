import SwiftUI

/// Один лист агавы. Рисуется в своей системе координат остриём вверх,
/// затем наклоняется на `angle` и уводится кончиком вбок на `bend`.
struct AgaveLeaf: Shape {
    /// Наклон от вертикали в градусах, положительный — вправо.
    var angle: Double
    /// Смещение кончика вбок, в долях размера холста.
    var bend: Double
    /// Длина листа, в долях размера холста.
    var length: Double
    /// Полуширина у основания, в долях размера холста.
    var halfWidth: Double
    /// Точка, из которой растёт лист, в долях холста.
    var origin: CGPoint

    /// Позволяет анимировать наклон и разброс листьев.
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(angle, bend) }
        set {
            angle = newValue.first
            bend = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let size = min(rect.width, rect.height)
        let base = CGPoint(x: rect.minX + origin.x * rect.width,
                           y: rect.minY + origin.y * rect.height)
        let radians = angle * .pi / 180
        let length = self.length * size
        let width = halfWidth * size
        let bend = self.bend * size
        // Кончик нарочно тупой и пухлый — так лист выглядит мультяшным,
        // а не колючим.
        let tip = width * 0.38

        func place(_ x: Double, _ y: Double) -> CGPoint {
            let dx = x * cos(radians) + y * sin(radians)
            let dy = -x * sin(radians) + y * cos(radians)
            return CGPoint(x: base.x + dx, y: base.y - dy)
        }

        var path = Path()
        path.move(to: place(-width, 0))
        path.addCurve(
            to: place(bend - tip, length),
            control1: place(-width * 1.08, length * 0.32),
            control2: place(bend * 0.42 - width * 0.78, length * 0.80)
        )
        path.addQuadCurve(
            to: place(bend + tip, length),
            control: place(bend, length * 1.06)
        )
        path.addCurve(
            to: place(width, 0),
            control1: place(bend * 0.42 + width * 0.78, length * 0.80),
            control2: place(width * 1.08, length * 0.32)
        )
        path.addQuadCurve(to: place(-width, 0), control: place(0, -width * 0.8))
        path.closeSubpath()
        return path
    }
}

/// Горшок: скруглённая трапеция с ободком.
struct FlowerPot: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let topInset = w * 0.06
        let bottomInset = w * 0.17
        let corner = w * 0.10

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + topInset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topInset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - bottomInset, y: rect.maxY - corner))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - bottomInset - corner, y: rect.maxY),
            control: CGPoint(x: rect.maxX - bottomInset, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + bottomInset + corner, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + bottomInset, y: rect.maxY - corner),
            control: CGPoint(x: rect.minX + bottomInset, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

/// Мультяшная агава в горшке — живая заставка на пустом экране.
struct AgaveMascot: View {
    enum Mood {
        /// Спокойно дышит и покачивается.
        case idle
        /// На неё тащат файлы: подбирается и раскрывает листья.
        case excited
        /// Идёт конвертация: подпрыгивает в такт, по листьям бежит волна.
        case working
    }

    var mood: Mood = .idle
    var size: CGFloat = 150

    private static let leaves: [(angle: Double, bend: Double, length: Double, halfWidth: Double)] = [
        ( -74, -0.020, 0.215, 0.036),
        (  74,  0.020, 0.215, 0.036),
        ( -49, -0.030, 0.300, 0.043),
        (  49,  0.030, 0.300, 0.043),
        ( -25, -0.026, 0.375, 0.050),
        (  25,  0.026, 0.375, 0.050),
        (   0,  0.000, 0.410, 0.054),
    ]

    /// Основание розетки — прячется за ободком горшка.
    private let rosetteOrigin = CGPoint(x: 0.5, y: 0.635)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let breath = sin(time * breathSpeed)

            // За работой горшок подпрыгивает в такт — движение вверх короткое
            // и резкое, приземление мягкое, как у настоящего прыжка.
            let hop = mood == .working
                ? pow(abs(sin(time * 3.1)), 0.6) * size * 0.045
                : 0

            ZStack {
                rosette(time: time)
                pot(breath: breath)
            }
            .frame(width: size, height: size)
            // Дыхание: чуть подрастает и оседает, опираясь на дно горшка.
            .scaleEffect(
                x: 1 + breath * 0.012 + moodScale * 0.4,
                y: 1 - breath * 0.012 + moodScale,
                anchor: .bottom
            )
            .offset(y: -hop)
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.45, dampingFraction: 0.6), value: mood)
    }

    // MARK: - Части

    private func rosette(time: TimeInterval) -> some View {
        ZStack {
            ForEach(Array(Self.leaves.enumerated()), id: \.offset) { index, leaf in
                // Каждый лист качается со своей фазой, иначе розетка движется
                // как единая деталь и выглядит неживой. За работой сдвиг фаз
                // больше — по листьям пробегает заметная волна.
                let phase = Double(index) * (mood == .working ? 1.7 : 0.9)
                let sway = sin(time * swaySpeed + phase) * swayAmount
                let spread = leaf.angle >= 0 ? moodSpread : -moodSpread

                AgaveLeaf(
                    angle: leaf.angle + sway + spread,
                    bend: leaf.bend,
                    length: leaf.length,
                    halfWidth: leaf.halfWidth,
                    origin: rosetteOrigin
                )
                .fill(
                    LinearGradient(
                        colors: [Theme.plantLight, Theme.plant],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    AgaveLeaf(
                        angle: leaf.angle + sway + spread,
                        bend: leaf.bend,
                        length: leaf.length,
                        halfWidth: leaf.halfWidth,
                        origin: rosetteOrigin
                    )
                    .stroke(Theme.plantOutline, lineWidth: size * 0.011)
                }
            }
        }
    }

    private func pot(breath: Double) -> some View {
        let potWidth = size * 0.46
        let potHeight = size * 0.27
        let rimWidth = size * 0.54
        let rimHeight = size * 0.075

        return VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: rimHeight * 0.42, style: .continuous)
                .fill(Theme.potRim)
                .frame(width: rimWidth, height: rimHeight)

            ZStack {
                FlowerPot()
                    .fill(
                        LinearGradient(
                            colors: [Theme.pot, Theme.potDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                face(breath: breath)
                    .frame(width: potWidth, height: potHeight)
            }
            .frame(width: potWidth, height: potHeight)
        }
        .frame(width: size, height: size, alignment: .bottom)
    }

    private func face(breath: Double) -> some View {
        let eye = size * 0.035
        // Моргает изредка и коротко: постоянное моргание выглядит нервным.
        let cycle = breath // используется только для лёгкого покачивания лица
        return VStack(spacing: size * 0.018) {
            HStack(spacing: size * 0.085) {
                Eye(size: eye, mood: mood)
                Eye(size: eye, mood: mood)
            }
            Smile(mood: mood)
                .stroke(Theme.face, style: StrokeStyle(lineWidth: size * 0.014, lineCap: .round))
                .frame(width: size * 0.075, height: size * 0.035)
        }
        .offset(y: size * 0.012 + cycle * size * 0.004)
    }

    // MARK: - Настроение

    private var swayAmount: Double {
        switch mood {
        case .idle: return 1.8
        case .excited: return 4.5
        case .working: return 3.4
        }
    }

    private var swaySpeed: Double {
        switch mood {
        case .idle: return 0.9
        case .excited: return 2.6
        case .working: return 3.1
        }
    }

    private var breathSpeed: Double {
        switch mood {
        case .idle: return 1.15
        case .excited: return 2.2
        // Совпадает с частотой прыжка, иначе дыхание и подскок расходятся
        // и движение выглядит дёрганым.
        case .working: return 3.1
        }
    }

    /// На радостях розетка раскрывается шире.
    private var moodSpread: Double {
        switch mood {
        case .idle: return 0
        case .excited: return 7
        case .working: return 2
        }
    }

    private var moodScale: Double {
        mood == .excited ? 0.05 : 0
    }
}

/// Глаз. На радостях округляется, за работой прищуривается от усердия.
private struct Eye: View {
    let size: CGFloat
    let mood: AgaveMascot.Mood
    @State private var closed = false

    private var openHeight: CGFloat {
        switch mood {
        case .idle: return size
        case .excited: return size * 1.25
        case .working: return size * 0.7
        }
    }

    var body: some View {
        Capsule()
            .fill(Theme.face)
            .frame(width: size, height: closed ? size * 0.16 : openHeight)
            .task {
                // Моргание живёт своим ритмом, не привязанным к покачиванию.
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(Int.random(in: 2600...5200)))
                    withAnimation(.easeInOut(duration: 0.07)) { closed = true }
                    try? await Task.sleep(for: .milliseconds(90))
                    withAnimation(.easeInOut(duration: 0.09)) { closed = false }
                }
            }
    }
}

/// Улыбка: в покое лёгкая дуга, на радостях шире, за работой сосредоточенная.
private struct Smile: Shape {
    let mood: AgaveMascot.Mood

    func path(in rect: CGRect) -> Path {
        let depth: CGFloat
        switch mood {
        case .idle: depth = rect.height * 0.6
        case .excited: depth = rect.height
        case .working: depth = rect.height * 0.32
        }
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.minY + depth * 2)
        )
        return path
    }
}
