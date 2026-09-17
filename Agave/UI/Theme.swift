import AppKit
import SwiftUI

/// Общие константы оформления.
enum Theme {
    static let cornerRadius: CGFloat = 12
    static let rowHeight: CGFloat = 54
    /// Отступ слева под кнопки светофора в окне без заголовка.
    static let trafficLightInset: CGFloat = 78

    static let accent = Color.accentColor

    // Палитра талисмана. Листья сизо-зелёные, как у живой агавы, горшок —
    // акцентная терракота: вместе выходит домашний цветок на подоконнике.
    static let plantLight = Color(red: 0.612, green: 0.741, blue: 0.663)
    static let plant = Color(red: 0.443, green: 0.596, blue: 0.518)
    static let plantOutline = Color(red: 0.290, green: 0.427, blue: 0.365)

    static let pot = Color(red: 0.804, green: 0.451, blue: 0.290)
    static let potDeep = Color(red: 0.678, green: 0.337, blue: 0.204)
    static let potRim = Color(red: 0.847, green: 0.514, blue: 0.353)
    static let face = Color(red: 0.267, green: 0.153, blue: 0.106)
}

/// Подложка окна с системным размытием.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// Позволяет таскать окно за фон и убирает полосу заголовка.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        configure(view.window)
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.isMovableByWindowBackground = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // Оформление всегда светлое: приложение задумано как светлое стеклянное,
        // и акцент подобран под светлый фон.
        window.appearance = NSAppearance(named: .aqua)
        NSApp.appearance = NSAppearance(named: .aqua)
    }
}

extension View {
    /// Подпись слева от компактного элемента управления.
    func labeledControl(_ title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            self
        }
    }
}
