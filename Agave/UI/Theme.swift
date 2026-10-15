import AppKit
import SwiftUI

/// Общие константы оформления. Окно тёмное: тропический лес в тени полога,
/// на нём яркая агава и коралловые акценты. Синяя ночная родня — Agave Video.
enum Theme {
    static let cornerRadius: CGFloat = 12
    static let rowHeight: CGFloat = 58
    /// Отступ слева под кнопки светофора в окне без заголовка.
    static let trafficLightInset: CGFloat = 78

    /// Коралл, притемнённый под кнопку: белый текст читается с контрастом около 5:1.
    static let accent = Color(red: 0.784, green: 0.271, blue: 0.110)
    /// Тёплый оттенок для предупреждений на тёмном фоне.
    static let warning = Color(red: 1.0, green: 0.478, blue: 0.239)
    /// Лаймовая подсветка: готовые файлы, прогресс, название в шапке.
    static let highlight = Color(red: 0.706, green: 0.898, blue: 0.333)
    /// Лучи сквозь полог.
    static let sun = Color(red: 1.0, green: 0.824, blue: 0.247)

    // Лес: от света под пологом к глубокой тени у земли.
    static let backgroundTop = Color(red: 0.118, green: 0.400, blue: 0.275)
    static let background = Color(red: 0.071, green: 0.271, blue: 0.196)
    static let backgroundDeep = Color(red: 0.035, green: 0.165, blue: 0.122)

    // Листья по краям окна.
    static let leafDeep = Color(red: 0.035, green: 0.165, blue: 0.122)
    static let leaf = Color(red: 0.169, green: 0.522, blue: 0.333)
    static let leafLight = Color(red: 0.239, green: 0.651, blue: 0.392)

    /// Подложки строк и панелей поверх фона.
    static let panel = Color.white.opacity(0.07)
    static let panelStrong = Color.white.opacity(0.11)

    // Талисман: сочная тропическая агава в коралловом горшке.
    static let plantLight = Color(red: 0.561, green: 0.843, blue: 0.478)
    static let plant = Color(red: 0.243, green: 0.620, blue: 0.353)
    static let plantOutline = Color(red: 0.090, green: 0.302, blue: 0.180)
    /// Светлые кончики листьев на иконке.
    static let leafTip = Color(red: 0.706, green: 0.898, blue: 0.333)

    static let pot = Color(red: 0.941, green: 0.478, blue: 0.227)
    static let potDeep = Color(red: 0.784, green: 0.271, blue: 0.110)
    static let potRim = Color(red: 1.0, green: 0.604, blue: 0.353)
    static let face = Color(red: 0.227, green: 0.102, blue: 0.047)
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
        // Оформление всегда тёмное: элементы управления должны читаться на тёмном фоне.
        window.appearance = NSAppearance(named: .darkAqua)
        NSApp.appearance = NSAppearance(named: .darkAqua)
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
