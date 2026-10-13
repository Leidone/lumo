import SwiftUI

enum FeatureCategory: String, CaseIterable, Identifiable {
    case sound, system, windows, input, clipboard, capture, everyday, energy

    var id: Self { self }

    func title(_ t: Localizer) -> String {
        switch self {
        case .sound: return t("Звук", "Sound")
        case .system: return t("Система", "System")
        case .windows: return t("Окна и Dock", "Windows & Dock")
        case .input: return t("Клавиатура и мышь", "Keyboard & mouse")
        case .clipboard: return t("Буфер, файлы и ссылки", "Clipboard, files & links")
        case .capture: return t("Захват экрана", "Screen capture")
        case .everyday: return t("Каждый день", "Everyday")
        case .energy: return t("Энергия и дисплеи", "Energy & displays")
        }
    }
}

/// Every tool Lumo offers, grouped into categories on the Tools tab.
enum FeatureID: String, CaseIterable, Identifiable {
    case optimizer, cleaner, uninstaller, sensors, network, updates, messaging, readouts
    case windowLayout, appSwitcher, dock, quitProtection
    case mouse, keyboard, shortcuts
    case clipboard, snippets, shelf, fileTools
    case screenshot, recorder
    case mixer, audio
    case commandBar, island, notes, quickPanel, radial
    case keepAwake, displays

    var id: Self { self }


    var category: FeatureCategory {
        switch self {
        case .optimizer, .cleaner, .uninstaller, .sensors, .network, .updates, .messaging, .readouts: return .system
        case .windowLayout, .quitProtection, .appSwitcher, .dock: return .windows
        case .mouse, .keyboard, .shortcuts: return .input
        case .clipboard, .snippets, .shelf, .fileTools: return .clipboard
        case .screenshot, .recorder: return .capture
        case .mixer, .audio: return .sound
        case .commandBar, .island, .notes, .quickPanel, .radial: return .everyday
        case .keepAwake, .displays: return .energy
        }
    }

    var symbol: String {
        switch self {
        case .optimizer: return "wand.and.stars"
        case .cleaner: return "sparkles.rectangle.stack.fill"
        case .uninstaller: return "trash.square.fill"
        case .sensors: return "thermometer.variable.and.figure"
        case .network: return "network"
        case .messaging: return "bubble.left.and.bubble.right.fill"
        case .updates: return "arrow.down.app.fill"
        case .readouts: return "menubar.rectangle"
        case .windowLayout: return "rectangle.split.2x2.fill"
        case .quitProtection: return "hand.raised.fill"
        case .mouse: return "computermouse.fill"
        case .keyboard: return "keyboard.fill"
        case .shortcuts: return "command.circle.fill"
        case .appSwitcher: return "square.on.square.dashed"
        case .dock: return "dock.rectangle"
        case .clipboard: return "doc.on.clipboard.fill"
        case .snippets: return "text.badge.plus"
        case .shelf: return "tray.full.fill"
        case .fileTools: return "link.badge.plus"
        case .screenshot: return "camera.viewfinder"
        case .recorder: return "record.circle.fill"
        case .mixer: return "slider.vertical.3"
        case .audio: return "hifispeaker.and.homepod.fill"
        case .commandBar: return "command.square.fill"
        case .island: return "capsule.portrait.fill"
        case .notes: return "note.text"
        case .keepAwake: return "cup.and.saucer.fill"
        case .displays: return "sun.max.fill"
        case .quickPanel: return "square.grid.3x3.fill"
        case .radial: return "circle.circle.fill"
        }
    }

    var colors: [Color] {
        let pair: (PaletteColor, PaletteColor)
        switch self {
        case .optimizer: pair = (Palette.purple, Palette.pink)
        case .cleaner: pair = (Palette.cyan, Palette.blue)
        case .uninstaller: pair = (Palette.orange, Palette.red)
        case .sensors: pair = (Palette.yellow, Palette.orange)
        case .network: pair = (Palette.cyan, Palette.blue)
        case .messaging: pair = (Palette.green, Palette.cyan)
        case .updates: pair = (Palette.blue, Palette.indigo)
        case .readouts: pair = (Palette.indigo, Palette.purple)
        case .windowLayout: pair = (Palette.blue, Palette.cyan)
        case .quitProtection: pair = (Palette.red, Palette.pink)
        case .mouse: pair = (Palette.mint, Palette.green)
        case .keyboard: pair = (Palette.indigo, Palette.purple)
        case .shortcuts: pair = (Palette.blue, Palette.cyan)
        case .appSwitcher: pair = (Palette.purple, Palette.indigo)
        case .dock: pair = (Palette.cyan, Palette.indigo)
        case .clipboard: pair = (Palette.yellow, Palette.orange)
        case .snippets: pair = (Palette.green, Palette.mint)
        case .shelf: pair = (Palette.cyan, Palette.indigo)
        case .fileTools: pair = (Palette.blue, Palette.green)
        case .screenshot: pair = (Palette.cyan, Palette.indigo)
        case .recorder: pair = (Palette.pink, Palette.red)
        case .mixer: pair = (Palette.orange, Palette.pink)
        case .audio: pair = (Palette.pink, Palette.purple)
        case .commandBar: pair = (Palette.indigo, Palette.blue)
        case .island: pair = (Palette.purple, Palette.blue)
        case .notes: pair = (Palette.yellow, Palette.green)
        case .keepAwake: pair = (Palette.orange, Palette.yellow)
        case .displays: pair = (Palette.yellow, Palette.pink)
        case .quickPanel: pair = (Palette.pink, Palette.orange)
        case .radial: pair = (Palette.purple, Palette.cyan)
        }
        return [pair.0.color, pair.1.color]
    }

    func title(_ t: Localizer) -> String {
        switch self {
        case .optimizer: return t("Оптимизация", "Optimizer")
        case .cleaner: return t("Очистка", "Cleaner")
        case .uninstaller: return t("Удаление приложений", "Uninstaller")
        case .sensors: return t("Датчики", "Sensors")
        case .network: return t("Сеть", "Network")
        case .messaging: return t("Загрузки мессенджеров", "Messenger downloads")
        case .updates: return t("Обновления", "Updates")
        case .readouts: return t("Строка меню", "Menu bar")
        case .windowLayout: return t("Раскладка окон", "Window layout")
        case .quitProtection: return t("Защита ⌘Q/⌘W", "⌘Q/⌘W guard")
        case .mouse: return t("Мышь и скролл", "Mouse & scroll")
        case .keyboard: return t("Клавиатура", "Keyboard")
        case .shortcuts: return t("Сочетания клавиш", "Shortcuts")
        case .appSwitcher: return t("Переключатель", "App switcher")
        case .dock: return t("Dock и окна", "Dock & windows")
        case .clipboard: return t("История буфера", "Clipboard")
        case .snippets: return t("Сниппеты", "Snippets")
        case .shelf: return t("Полка", "Shelf")
        case .fileTools: return t("Finder, ссылки, DMG", "Finder, links, DMG")
        case .screenshot: return t("Скриншоты", "Screenshots")
        case .recorder: return t("Запись экрана", "Screen recording")
        case .mixer: return t("Микшер", "Volume mixer")
        case .audio: return t("Выходы и микрофон", "Outputs & mic")
        case .commandBar: return "Command Bar"
        case .island: return "Dynamic Island"
        case .notes: return t("Заметки и AI", "Notes & AI")
        case .keepAwake: return t("Не спать", "Stay awake")
        case .displays: return t("Дисплеи", "Displays")
        case .quickPanel: return t("Быстрые действия", "Quick actions")
        case .radial: return t("Радиальное меню", "Radial menu")
        }
    }

    func subtitle(_ t: Localizer) -> String {
        switch self {
        case .optimizer: return t("Тяжёлые процессы", "Heavy processes")
        case .cleaner: return t("Кэши, логи, остатки", "Caches, logs, leftovers")
        case .uninstaller: return t("Вместе со следами", "With all traces")
        case .sensors: return t("Температуры, GPU, энергия", "Temps, GPU, energy")
        case .network: return t("Трафик и скорость", "Traffic & speed test")
        case .messaging: return t("Telegram, WhatsApp…", "Telegram, WhatsApp…")
        case .updates: return t("Homebrew, App Store, Sparkle", "Homebrew, App Store, Sparkle")
        case .readouts: return t("Свои индикаторы", "Your own readouts")
        case .windowLayout: return t("Половины и четверти", "Halves & quarters")
        case .quitProtection: return t("Без случайных выходов", "No accidental quits")
        case .mouse: return t("Кнопки, жесты, фокус", "Buttons, gestures, focus")
        case .keyboard: return t("Super key, без дребезга", "Super key, debounce")
        case .shortcuts: return t("Все в одном месте", "All in one place")
        case .appSwitcher: return t("⌘Tab с превью", "⌘Tab with previews")
        case .dock: return t("Превью, клики, Spaces", "Previews, clicks, Spaces")
        case .clipboard: return t("Всё, что копировали", "Everything you copied")
        case .snippets: return t("Текст по сокращению", "Text from shortcuts")
        case .shelf: return t("Файлы под рукой", "Files at hand")
        case .fileTools: return t("Без трекеров и лишних шагов", "No trackers, fewer steps")
        case .screenshot: return t("Текст, цвет, разметка", "Text, color, markup")
        case .recorder: return t("Видео и GIF", "Video & GIF")
        case .mixer: return t("Громкость приложений", "Per-app volume")
        case .audio: return t("Переключение, mute", "Switch & mute")
        case .commandBar: return t("Поиск всего", "Search everything")
        case .island: return t("Вокруг выреза", "Around the notch")
        case .notes: return t("Черновик, лимиты агентов", "Scratchpad, agent limits")
        case .keepAwake: return t("Правила, крышка, Bluetooth", "Rules, lid, Bluetooth")
        case .displays: return t("Яркость, DDC, XDR", "Brightness, DDC, XDR")
        case .quickPanel: return t("Панель ⌃⌘V, чистка", "⌃⌘V panel, cleaning")
        case .radial: return t("Колесо у курсора", "A wheel at the pointer")
        }
    }
}
