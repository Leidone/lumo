import AppKit
import LumoCore
import ScreenCaptureKit
import SwiftUI

/// Lumo's own capture selector: the screen freezes, a mode bar switches between screenshot kinds,
/// recording, text and color, and a pixel loupe follows the pointer.
@MainActor
final class CaptureSelector {
    enum Mode: Int, CaseIterable, Identifiable {
        case area = 1, window, screen, scrolling, record, text, color

        var id: Self { self }
        var symbol: String {
            switch self {
            case .area: return "rectangle.dashed"
            case .window: return "macwindow"
            case .screen: return "display"
            case .scrolling: return "arrow.up.and.down.text.horizontal"
            case .record: return "record.circle"
            case .text: return "text.viewfinder"
            case .color: return "eyedropper.halffull"
            }
        }

        func title(_ t: Localizer) -> String {
            switch self {
            case .area: return t("Область", "Area")
            case .window: return t("Окно", "Window")
            case .screen: return t("Экран", "Screen")
            case .scrolling: return t("Прокрутка", "Scrolling")
            case .record: return t("Запись", "Record")
            case .text: return t("Текст", "Text")
            case .color: return t("Цвет", "Color")
            }
        }
    }

    private static var current: CaptureSelector?

    let state: SelectorState
    private let tools: CaptureTools
    private let recorder: ScreenRecorder?
    private var windows: [NSWindow] = []

    private init(mode: Mode, tools: CaptureTools, recorder: ScreenRecorder?) {
        state = SelectorState(mode: mode)
        self.tools = tools
        self.recorder = recorder
    }

    /// Opens the selector; returns false when Screen Recording isn't allowed (callers fall back to macOS's tool).
    @discardableResult
    static func run(_ mode: Mode, tools: CaptureTools, recorder: ScreenRecorder?) -> Bool {
        guard CGPreflightScreenCaptureAccess() else { return false }
        current?.close()
        let selector = CaptureSelector(mode: mode, tools: tools, recorder: recorder)
        current = selector
        Task { await selector.open() }
        return true
    }

    private func open() async {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return close() }
        let own = content.windows.filter { $0.owningApplication?.processID == getpid() }
        state.windowFrames = AppSwitcher.onScreenWindows().filter { $0.pid != getpid() }.map(\.bounds)
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let display = content.displays.first(where: { $0.displayID == id })
            else { continue }
            let configuration = SCStreamConfiguration()
            configuration.width = Int(screen.frame.width * screen.backingScaleFactor)
            configuration.height = Int(screen.frame.height * screen.backingScaleFactor)
            configuration.showsCursor = false
            let filter = SCContentFilter(display: display, excludingWindows: own)
            guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) else { continue }
            windows.append(makeWindow(screen: screen, image: image))
        }
        guard !windows.isEmpty else { return close() }
        NSApp.activate()
        windows.forEach { $0.orderFrontRegardless() }
        windows.first { $0.screen?.frame.contains(NSEvent.mouseLocation) == true }?.makeKey()
        NSCursor.crosshair.push()
    }

    private func makeWindow(screen: NSScreen, image: CGImage) -> NSWindow {
        let window = KeyPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.level = .screenSaver
        window.isOpaque = true
        window.backgroundColor = .black
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        // Top-left of this screen in global (Accessibility) coordinates, to place window outlines.
        let origin = CGPoint(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY)
        window.contentView = NSHostingView(rootView: SelectorView(state: state, image: image, scale: screen.backingScaleFactor,
                                                                  screenOrigin: origin, t: tools.t,
                                                                  finish: { [weak self] rect in self?.finish(rect, image: image, screen: screen) },
                                                                  cancel: { [weak self] in self?.close() }))
        return window
    }

    private func close() {
        NSCursor.pop()
        windows.forEach { $0.orderOut(nil) }
        windows = []
        if Self.current === self { Self.current = nil }
    }

    /// `rect` is in the screen's own points, top-left origin.
    private func finish(_ rect: CGRect, image: CGImage, screen: NSScreen) {
        let mode = state.mode
        let scale = screen.backingScaleFactor
        let pixels = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale).integral
        close()
        let global = CGRect(x: screen.frame.minX + rect.minX, y: screen.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        switch mode {
        case .area, .window, .screen:
            guard let cropped = image.cropping(to: pixels) else { return }
            ScreenshotEditorController.open(image: NSImage(cgImage: cropped, size: rect.size), tools: tools)
        case .text:
            guard let cropped = image.cropping(to: pixels) else { return }
            Task { await tools.copyText(from: NSImage(cgImage: cropped, size: rect.size)) }
        case .color:
            guard let color = Self.pixel(in: image, at: CGPoint(x: pixels.midX, y: pixels.midY)) else { return }
            tools.remember(color)
        case .record:
            Task { await recorder?.start(region: global, on: screen) }
        case .scrolling:
            let tools = self.tools
            Task {
                guard let image = await ScrollingCapture.run(region: global, screen: screen) else { return }
                ScreenshotEditorController.open(image: image, tools: tools)
            }
        }
    }

    static func pixel(in image: CGImage, at point: CGPoint) -> PickedColor? {
        guard let cropped = image.cropping(to: CGRect(x: point.x, y: point.y, width: 1, height: 1)) else { return nil }
        var bytes = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return PickedColor(red: Double(bytes[0]) / 255, green: Double(bytes[1]) / 255, blue: Double(bytes[2]) / 255)
    }
}

@MainActor
final class SelectorState: ObservableObject {
    @Published var mode: CaptureSelector.Mode
    @Published var pointer: CGPoint?
    @Published var dragStart: CGPoint?
    @Published var dragEnd: CGPoint?
    var windowFrames: [CGRect] = []

    init(mode: CaptureSelector.Mode) {
        self.mode = mode
    }

    var selection: CGRect? {
        guard let start = dragStart, let end = dragEnd else { return nil }
        return CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
}

private struct SelectorView: View {
    @ObservedObject var state: SelectorState
    let image: CGImage
    let scale: CGFloat
    let screenOrigin: CGPoint
    let t: Localizer
    let finish: (CGRect) -> Void
    let cancel: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size)
            let target = highlight(in: bounds)
            ZStack(alignment: .topLeading) {
                Image(decorative: image, scale: scale).resizable().frame(width: bounds.width, height: bounds.height)
                // Dim everything except the target.
                Path { path in
                    path.addRect(bounds)
                    if let target { path.addRect(target) }
                }
                .fill(Color.black.opacity(0.38), style: FillStyle(eoFill: true))
                if let target {
                    Rectangle().strokeBorder(Color.white, lineWidth: 1.5)
                        .frame(width: target.width, height: target.height)
                        .offset(x: target.minX, y: target.minY)
                    if state.mode == .area || state.mode == .scrolling || state.mode == .record || state.mode == .text {
                        Text("\(Int(target.width)) × \(Int(target.height))")
                            .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(.black.opacity(0.7))).foregroundStyle(.white)
                            .offset(x: target.minX, y: max(target.minY - 24, 4))
                    }
                }
                if let pointer = state.pointer {
                    Loupe(image: image, scale: scale, point: pointer)
                        .offset(x: min(pointer.x + 22, bounds.width - 130), y: min(pointer.y + 22, bounds.height - 160))
                }
                modeBar.frame(maxWidth: .infinity).padding(.top, 60)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                if case .active(let point) = phase { state.pointer = point } else { state.pointer = nil }
            }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    state.pointer = value.location
                    if state.dragStart == nil { state.dragStart = value.startLocation }
                    state.dragEnd = value.location
                }
                .onEnded { value in complete(value, bounds: bounds) })
        }
        .ignoresSafeArea()
        .onKeyPress(.escape) { cancel(); return .handled }
        .onKeyPress(characters: .decimalDigits) { press in
            if let number = Int(press.characters), let mode = CaptureSelector.Mode(rawValue: number) { state.mode = mode }
            return .handled
        }
    }

    private var modeBar: some View {
        HStack(spacing: 4) {
            ForEach(CaptureSelector.Mode.allCases) { mode in
                Button { state.mode = mode } label: {
                    VStack(spacing: 3) {
                        Image(systemName: mode.symbol).font(.system(size: 15, weight: .semibold))
                        Text(mode.title(t)).font(.system(size: 9.5, weight: .medium))
                    }
                    .frame(width: 66, height: 46)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(state.mode == mode ? Palette.blue.color.opacity(0.85) : .clear))
                    .foregroundStyle(.white)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(mode.rawValue)")
            }
            Button(action: cancel) { Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).frame(width: 34, height: 46) }
                .buttonStyle(.plain).foregroundStyle(.white.opacity(0.8))
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.black.opacity(0.72)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.15)))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state.mode)
    }

    /// The rectangle that would be captured right now.
    private func highlight(in bounds: CGRect) -> CGRect? {
        switch state.mode {
        case .screen: return bounds
        case .window: return hoveredWindow(in: bounds)
        case .color: return nil
        default: return state.selection
        }
    }

    private func hoveredWindow(in bounds: CGRect) -> CGRect? {
        guard let pointer = state.pointer else { return nil }
        let global = CGPoint(x: pointer.x + screenOrigin.x, y: pointer.y + screenOrigin.y)
        return state.windowFrames.first { $0.contains(global) }
            .map { $0.offsetBy(dx: -screenOrigin.x, dy: -screenOrigin.y).intersection(bounds) }
    }

    private func complete(_ value: DragGesture.Value, bounds: CGRect) {
        defer {
            state.dragStart = nil
            state.dragEnd = nil
        }
        let moved = hypot(value.translation.width, value.translation.height) > 4
        switch state.mode {
        case .screen: finish(bounds)
        case .window: if let window = hoveredWindow(in: bounds) { finish(window) }
        case .color: finish(CGRect(x: value.location.x, y: value.location.y, width: 1, height: 1))
        default:
            if moved, let selection = state.selection, selection.width > 4, selection.height > 4 { finish(selection) }
        }
    }
}

/// An 8× pixel loupe with the color code under the pointer.
private struct Loupe: View {
    let image: CGImage
    let scale: CGFloat
    let point: CGPoint
    private static let pixels = 15

    var body: some View {
        let center = CGPoint(x: (point.x * scale).rounded(), y: (point.y * scale).rounded())
        let half = CGFloat(Self.pixels / 2)
        let crop = image.cropping(to: CGRect(x: center.x - half, y: center.y - half, width: CGFloat(Self.pixels), height: CGFloat(Self.pixels)))
        let color = CaptureSelector.pixel(in: image, at: center)
        VStack(spacing: 4) {
            ZStack {
                if let crop {
                    Image(decorative: crop, scale: 1).resizable().interpolation(.none)
                }
                Rectangle().strokeBorder(Color.white, lineWidth: 1.5).frame(width: 8, height: 8)
            }
            .frame(width: 112, height: 112)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5))
            Text(color?.hex ?? "").font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(.black.opacity(0.7))).foregroundStyle(.white)
        }
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        .allowsHitTesting(false)
    }
}

// MARK: - Scrolling capture

/// Captures a region, scrolls it, captures again and stitches the frames until the page stops moving.
@MainActor
enum ScrollingCapture {
    private static let maxFrames = 40
    private static let settle: UInt64 = 350_000_000

    static func run(region: CGRect, screen: NSScreen) async -> NSImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let display = content.displays.first(where: { $0.displayID == id })
        else { return nil }
        let scale = screen.backingScaleFactor
        let configuration = SCStreamConfiguration()
        // sourceRect is in the display's points with a top-left origin.
        configuration.sourceRect = CGRect(x: region.minX - screen.frame.minX, y: screen.frame.maxY - region.maxY,
                                          width: region.width, height: region.height)
        configuration.width = Int(region.width * scale)
        configuration.height = Int(region.height * scale)
        configuration.showsCursor = false
        let filter = SCContentFilter(display: display, excludingWindows: content.windows.filter { $0.owningApplication?.processID == getpid() })
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let center = CGPoint(x: region.midX, y: primaryHeight - region.midY)
        CGWarpMouseCursorPosition(center)

        var slices: [CGImage] = []
        var previousRows: [UInt64] = []
        for _ in 0..<maxFrames {
            guard let frame = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration),
                  let rows = signatures(frame)
            else { break }
            if previousRows.isEmpty {
                slices.append(frame)
            } else {
                guard let overlap = ScrollStitcher.overlap(previous: previousRows, next: rows, minimum: 12), overlap < rows.count else { break }
                guard let fresh = frame.cropping(to: CGRect(x: 0, y: overlap, width: frame.width, height: frame.height - overlap)) else { break }
                slices.append(fresh)
            }
            previousRows = rows
            scroll(by: -Int(region.height * 0.6), at: center)
            try? await Task.sleep(nanoseconds: settle)
        }
        return combine(slices, scale: scale)
    }

    private static func scroll(by pixels: Int, at point: CGPoint) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(pixels), wheel2: 0, wheel3: 0) else { return }
        event.location = point
        event.setIntegerValueField(.eventSourceUserData, value: InputTap.syntheticMarker)
        event.post(tap: .cghidEventTap)
    }

    /// One hash per row of pixels (every fourth pixel sampled).
    private static func signatures(_ image: CGImage) -> [UInt64]? {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (0..<height).map { row in
            var hash: UInt64 = 1_469_598_103_934_665_603
            let base = row * width * 4
            for column in stride(from: 0, to: width * 4, by: 16) {
                hash = (hash ^ UInt64(data[base + column]) ^ UInt64(data[base + column + 1]) << 8 ^ UInt64(data[base + column + 2]) << 16)
                    &* 1_099_511_628_211
            }
            return hash
        }
    }

    private static func combine(_ slices: [CGImage], scale: CGFloat) -> NSImage? {
        guard let first = slices.first else { return nil }
        let width = first.width
        let height = slices.reduce(0) { $0 + $1.height }
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        var top = height
        for slice in slices {
            top -= slice.height
            context.draw(slice, in: CGRect(x: 0, y: top, width: slice.width, height: slice.height))
        }
        guard let joined = context.makeImage() else { return nil }
        return NSImage(cgImage: joined, size: CGSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale))
    }
}
