import AppKit
import Carbon
import LumoCore
import SwiftUI
import Vision

/// Screenshots with markup, on-screen text recognition (OCR + QR), a color picker and pinned images.
@MainActor
final class CaptureTools: ObservableObject {
    enum ColorFormat: String, CaseIterable, Identifiable {
        case hex, rgb, hsl, swiftUI

        var id: Self { self }
        var title: String {
            switch self {
            case .hex: return "HEX"
            case .rgb: return "RGB"
            case .hsl: return "HSL"
            case .swiftUI: return "SwiftUI"
            }
        }

        func string(_ color: PickedColor) -> String {
            switch self {
            case .hex: return color.hex
            case .rgb: return color.rgb
            case .hsl: return color.hsl
            case .swiftUI: return color.swiftUI
            }
        }
    }

    enum Mode { case area, window, screen }

    private enum Key {
        static let hotkeys = "capture.hotkeys"
        static let colors = "capture.colors"
        static let format = "capture.colorFormat"
        static let selector = "capture.useSelector"
    }

    @Published var hotkeysEnabled: Bool { didSet { store.set(hotkeysEnabled, forKey: Key.hotkeys); registerHotKeys() } }
    @Published var colorFormat: ColorFormat { didSet { store.set(colorFormat.rawValue, forKey: Key.format) } }
    /// Lumo's own selector (mode bar, loupe, scrolling capture) instead of macOS's crosshair.
    @Published var useSelector: Bool { didSet { store.set(useSelector, forKey: Key.selector) } }
    weak var recorder: ScreenRecorder?
    @Published private(set) var colors: [PickedColor] = []
    @Published private(set) var lastText: String?

    var t = Localizer(language: .english)
    var onRecordToggle: (() -> Void)?

    private let store: UserDefaults
    private let hotKeys = HotKeyCenter()
    private let hint = HintPanel()
    private var pins: [NSPanel] = []

    init(store: UserDefaults) {
        store.register(defaults: [Key.selector: true])
        self.store = store
        hotkeysEnabled = store.bool(forKey: Key.hotkeys)
        useSelector = store.bool(forKey: Key.selector)
        colorFormat = ColorFormat(rawValue: store.string(forKey: Key.format) ?? "") ?? .hex
        if let data = store.data(forKey: Key.colors), let saved = try? JSONDecoder().decode([PickedColor].self, from: data) {
            colors = saved
        }
        registerHotKeys()
    }

    // MARK: Screenshots

    func screenshot(_ mode: Mode) {
        let selectorMode: CaptureSelector.Mode = mode == .area ? .area : mode == .window ? .window : .screen
        if useSelector, CaptureSelector.run(selectorMode, tools: self, recorder: recorder) { return }
        Task {
            guard let image = await Self.capture(mode) else { return }
            ScreenshotEditorController.open(image: image, tools: self)
        }
    }

    /// Uses the system `screencapture` selector (area/window with the usual magnifier and Esc to cancel).
    static func capture(_ mode: Mode) async -> NSImage? {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("lumo-\(UUID().uuidString).png")
        let arguments: [String]
        switch mode {
        case .area: arguments = ["-i", "-x", file.path]
        case .window: arguments = ["-i", "-W", "-x", file.path]
        case .screen: arguments = ["-x", "-m", file.path]
        }
        _ = await Shell.run("/usr/sbin/screencapture", arguments)
        defer { try? FileManager.default.removeItem(at: file) }
        guard let data = try? Data(contentsOf: file) else { return nil }
        return NSImage(data: data)
    }

    // MARK: Text & QR

    /// Opens the selector straight in scrolling mode.
    func scrollingScreenshot() {
        if !CaptureSelector.run(.scrolling, tools: self, recorder: recorder) {
            hint.show(HintView(symbol: "rectangle.dashed.badge.record", text: t("Нужна «Запись экрана»", "Needs Screen Recording access")))
            hint.hide(after: 2)
        }
    }

    func recognizeText() {
        if useSelector, CaptureSelector.run(.text, tools: self, recorder: recorder) { return }
        Task {
            guard let image = await Self.capture(.area) else { return }
            await copyText(from: image)
        }
    }

    func copyText(from image: NSImage) async {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let result = await Task.detached(priority: .userInitiated) { Self.recognize(cgImage) }.value
        let text = ([result.codes.joined(separator: "\n"), result.text]).filter { !$0.isEmpty }.joined(separator: "\n\n")
        guard !text.isEmpty else {
            hint.show(HintView(symbol: "text.magnifyingglass", text: t("Текст не найден", "No text found")))
            hint.hide(after: 1.6)
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        lastText = text
        let preview = String(text.prefix(48)).replacingOccurrences(of: "\n", with: " ")
        let label = result.codes.isEmpty ? t("Скопирован текст", "Text copied") : t("Скопирован QR-код", "QR code copied")
        hint.show(HintView(symbol: result.codes.isEmpty ? "doc.on.doc.fill" : "qrcode", text: "\(label): \(preview)"))
        hint.hide(after: 2.2)
    }

    nonisolated private static func recognize(_ image: CGImage) -> (text: String, codes: [String]) {
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.recognitionLanguages = ["ru-RU", "en-US"]
        textRequest.usesLanguageCorrection = true
        let barcodeRequest = VNDetectBarcodesRequest()
        try? VNImageRequestHandler(cgImage: image).perform([textRequest, barcodeRequest])
        let text = (textRequest.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        let codes = (barcodeRequest.results ?? []).compactMap(\.payloadStringValue)
        return (text, codes)
    }

    // MARK: Color picker

    func pickColor() {
        if useSelector, CaptureSelector.run(.color, tools: self, recorder: recorder) { return }
        NSColorSampler().show { [weak self] color in
            guard let self, let rgb = color?.usingColorSpace(.sRGB) else { return }
            self.remember(PickedColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent))
        }
    }

    /// Copies a picked color and keeps it in the recent list.
    func remember(_ picked: PickedColor) {
        copy(picked)
        colors = Array(([picked] + colors.filter { $0 != picked }).prefix(24))
        if let data = try? JSONEncoder().encode(colors) { store.set(data, forKey: Key.colors) }
    }

    func copy(_ color: PickedColor) {
        let value = colorFormat.string(color)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        hint.show(HintView(symbol: "eyedropper.full", text: t("Скопирован цвет \(value)", "Copied \(value)")))
        hint.hide(after: 1.6)
    }

    func clearColors() {
        colors = []
        store.removeObject(forKey: Key.colors)
    }

    // MARK: Pins

    /// Keeps an image floating above other windows; drag to move, double-click to close.
    func pin(_ image: NSImage) {
        let maxSide: CGFloat = 520
        let scale = min(1, maxSide / max(image.size.width, image.size.height, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel, .resizable],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentAspectRatio = size
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: PinnedImageView(image: image) { [weak self, weak panel] in
            guard let panel else { return }
            panel.orderOut(nil)
            self?.pins.removeAll { $0 === panel }
        })
        panel.center()
        panel.orderFrontRegardless()
        pins.append(panel)
    }

    // MARK: Hot keys

    private func registerHotKeys() {
        hotKeys.unregisterAll()
        guard hotkeysEnabled else { return }
        hotKeys.register(.captureArea) { [weak self] in self?.screenshot(.area) }
        hotKeys.register(.captureWindow) { [weak self] in self?.screenshot(.window) }
        hotKeys.register(.captureText) { [weak self] in self?.recognizeText() }
        hotKeys.register(.captureColor) { [weak self] in self?.pickColor() }
        hotKeys.register(.captureRecord) { [weak self] in self?.onRecordToggle?() }
        // With the takeover on, the familiar macOS combinations open Lumo's tools instead.
        if ShortcutStore.shared.takeoverScreenshots {
            let shiftCommand = UInt32(shiftKey | cmdKey)
            hotKeys.register(keyCode: UInt32(kVK_ANSI_3), modifiers: shiftCommand) { [weak self] in self?.screenshot(.screen) }
            hotKeys.register(keyCode: UInt32(kVK_ANSI_4), modifiers: shiftCommand) { [weak self] in self?.screenshot(.area) }
            hotKeys.register(keyCode: UInt32(kVK_ANSI_5), modifiers: shiftCommand) { [weak self] in self?.onRecordToggle?() }
        }
    }
}

private struct PinnedImageView: View {
    let image: NSImage
    let close: () -> Void
    @State private var hovering = false

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if hovering {
                    Button(action: close) {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 18)).symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .transition(.opacity)
                }
            }
            .onHover { hovering = $0 }
            .onTapGesture(count: 2, perform: close)
            .animation(.easeOut(duration: 0.15), value: hovering)
    }
}
