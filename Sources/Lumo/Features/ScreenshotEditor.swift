import AppKit
import SwiftUI

/// Window with markup tools for a fresh screenshot.
@MainActor
enum ScreenshotEditorController {
    private static var windows: [NSWindow] = []

    static func open(image: NSImage, tools: CaptureTools) {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let maxSize = CGSize(width: screen.width * 0.7, height: screen.height * 0.7)
        let scale = min(1, maxSize.width / image.size.width, (maxSize.height - 70) / image.size.height)
        let canvas = CGSize(width: max(image.size.width * scale, 420), height: image.size.height * scale + 70)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: canvas),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ScreenshotEditorView(image: image, tools: tools) { window.close() })
        window.center()
        windows.append(window)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { note in
            let closed = note.object as? NSWindow
            MainActor.assumeIsolated { windows.removeAll { $0 === closed } }
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

private struct Mark: Identifiable {
    enum Tool: String, CaseIterable, Identifiable {
        case pen, arrow, rectangle, highlighter, redact, crop

        var id: Self { self }
        var symbol: String {
            switch self {
            case .pen: return "pencil.tip"
            case .arrow: return "arrow.up.right"
            case .rectangle: return "rectangle"
            case .highlighter: return "highlighter"
            case .redact: return "eye.slash.fill"
            case .crop: return "crop"
            }
        }
    }

    let id = UUID()
    let tool: Tool
    let color: Color
    /// Normalised 0…1 coordinates, so marks survive window resizing and export at full resolution.
    var points: [CGPoint]
}

/// Gradient frames that make a screenshot presentation-ready.
private enum Backdrop: String, CaseIterable, Identifiable {
    case none, sunset, ocean, forest, graphite

    var id: Self { self }
    var colors: [Color] {
        switch self {
        case .none: return [.clear]
        case .sunset: return [Palette.orange.color, Palette.pink.color, Palette.purple.color]
        case .ocean: return [Palette.cyan.color, Palette.blue.color, Palette.indigo.color]
        case .forest: return [Palette.mint.color, Palette.green.color, Palette.cyan.color]
        case .graphite: return [Color(white: 0.32), Color(white: 0.12)]
        }
    }
}

/// The final picture: cropped, framed and watermarked. Used for export.
private struct FinalShot: View {
    let image: NSImage
    let backdrop: Backdrop
    let watermark: String

    var body: some View {
        let size = image.size
        let pad = backdrop == .none ? 0 : max(size.width, size.height) * 0.06
        Image(nsImage: image).resizable()
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .bottomTrailing) { WatermarkText(text: watermark, base: max(size.width, size.height)) }
            .clipShape(RoundedRectangle(cornerRadius: backdrop == .none ? 0 : max(size.width, size.height) * 0.012, style: .continuous))
            .shadow(color: .black.opacity(backdrop == .none ? 0 : 0.35), radius: pad * 0.4, y: pad * 0.15)
            .padding(pad)
            .background(LinearGradient(colors: backdrop.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

private struct WatermarkText: View {
    let text: String
    let base: CGFloat

    var body: some View {
        if !text.isEmpty {
            Text(text).font(.system(size: max(base * 0.022, 9), weight: .semibold))
                .foregroundStyle(.white.opacity(0.75)).shadow(color: .black.opacity(0.5), radius: 2)
                .padding(base * 0.015)
        }
    }
}

/// Gives SwiftUI buttons a real view to anchor the Share menu to.
private struct ShareAnchor: NSViewRepresentable {
    let holder: ViewHolder

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        holder.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class ViewHolder {
    weak var view: NSView?
}

private struct ScreenshotEditorView: View {
    let image: NSImage
    let tools: CaptureTools
    let close: () -> Void

    @State private var marks: [Mark] = []
    @State private var draft: Mark?
    @State private var tool: Mark.Tool = .arrow
    @State private var color = Palette.red.color
    @State private var toast: String?
    @State private var crop: CGRect?
    @State private var backdrop = Backdrop.none
    @State private var watermark = ""
    @State private var showStyle = false
    private let shareHolder = ViewHolder()

    private let palette = [Palette.red, Palette.orange, Palette.yellow, Palette.green, Palette.blue].map(\.color)

    var body: some View {
        let t = tools.t
        VStack(spacing: 0) {
            toolbar(t)
            GeometryReader { geometry in
                let size = Self.fit(image.size, in: geometry.size)
                ZStack {
                    AnnotatedImage(image: image, marks: marks + (draft.map { [$0] } ?? []))
                        .frame(width: size.width, height: size.height)
                        .overlay { cropOverlay(size) }
                        .overlay(alignment: .bottomTrailing) {
                            WatermarkText(text: watermark, base: max(size.width, size.height))
                                .offset(x: crop.map { -size.width * (1 - $0.maxX) } ?? 0, y: crop.map { -size.height * (1 - $0.maxY) } ?? 0)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                        .gesture(DragGesture(minimumDistance: 1)
                            .onChanged { value in draw(value, in: size) }
                            .onEnded { _ in commit() })
                        .padding(backdrop == .none ? 0 : 24)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: backdrop.colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(14)
        }
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(.ultraThinMaterial)).padding(18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: toast)
    }

    private func toolbar(_ t: Localizer) -> some View {
        HStack(spacing: 6) {
            ForEach(Mark.Tool.allCases) { item in
                Button { tool = item } label: {
                    Image(systemName: item.symbol).frame(width: 28, height: 24)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(tool == item ? Palette.blue.color.opacity(0.25) : .clear))
                }
                .buttonStyle(.plain)
                .help(item.rawValue)
            }
            Divider().frame(height: 18)
            ForEach(palette.indices, id: \.self) { index in
                Circle().fill(palette[index]).frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: color == palette[index] ? 2 : 0))
                    .onTapGesture { color = palette[index] }
            }
            Divider().frame(height: 18)
            Button { _ = marks.popLast() } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(.plain).disabled(marks.isEmpty).keyboardShortcut("z", modifiers: .command)
            Spacer()
            Button { showStyle.toggle() } label: { Image(systemName: "paintpalette.fill") }
                .buttonStyle(.bordered).help(t("Фон и водяной знак", "Background and watermark"))
                .popover(isPresented: $showStyle) { stylePanel(t) }
            Button { share() } label: { Image(systemName: "square.and.arrow.up") }
                .buttonStyle(.bordered).help(t("Поделиться", "Share"))
                .background(ShareAnchor(holder: shareHolder))
            Button { link(t) } label: { Image(systemName: "link") }
                .buttonStyle(.bordered).help(t("Ссылка на 24 часа", "24-hour link"))
            action("text.viewfinder", t("Текст", "Text")) { Task { await tools.copyText(from: rendered()) } }
            action("pin.fill", t("Закрепить", "Pin")) { tools.pin(rendered()); close() }
            action("square.and.arrow.down", t("Сохранить", "Save")) { save(t) }
            Button {
                copy()
                toast = t("Скопировано", "Copied")
                Task { try? await Task.sleep(for: .seconds(1.2)); toast = nil }
            } label: {
                Label(t("Копировать", "Copy"), systemImage: "doc.on.doc.fill")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("c", modifiers: .command)
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.leading, 78)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
    }

    private func stylePanel(_ t: Localizer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("Фон", "Background")).font(.system(size: 12, weight: .semibold))
            HStack(spacing: 8) {
                ForEach(Backdrop.allCases) { option in
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(option == .none ? AnyShapeStyle(Color.primary.opacity(0.08))
                                              : AnyShapeStyle(LinearGradient(colors: option.colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
                        .frame(width: 34, height: 26)
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.accentColor, lineWidth: backdrop == option ? 2 : 0))
                        .overlay { if option == .none { Image(systemName: "slash.circle").foregroundStyle(.secondary) } }
                        .onTapGesture { backdrop = option }
                }
            }
            Text(t("Водяной знак", "Watermark")).font(.system(size: 12, weight: .semibold))
            TextField(t("Например, @username", "e.g. @username"), text: $watermark).textFieldStyle(.roundedBorder).frame(width: 220)
            if crop != nil {
                Button(t("Сбросить обрезку", "Reset crop")) { crop = nil }
            }
        }
        .padding(14)
    }

    @ViewBuilder
    private func cropOverlay(_ size: CGSize) -> some View {
        if let crop {
            let rect = CGRect(x: crop.minX * size.width, y: crop.minY * size.height, width: crop.width * size.width, height: crop.height * size.height)
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRect(rect)
            }
            .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
            Rectangle().strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])).foregroundStyle(.white)
                .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
        }
    }

    private func share() {
        guard let url = temporaryPNG(), let view = shareHolder.view else { return }
        NSSharingServicePicker(items: [url]).show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    private func link(_ t: Localizer) {
        guard let url = temporaryPNG() else { return }
        Task { await LinkUploader.share(url, t: t) }
    }

    private func temporaryPNG() -> URL? {
        let image = rendered()
        guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Lumo \(formatter.string(from: Date())).png")
        return (try? png.write(to: url)) != nil ? url : nil
    }

    private func action(_ symbol: String, _ title: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { Label(title, systemImage: symbol) }.buttonStyle(.bordered)
    }

    // MARK: Drawing

    private func draw(_ value: DragGesture.Value, in size: CGSize) {
        let point = CGPoint(x: min(max(value.location.x / size.width, 0), 1), y: min(max(value.location.y / size.height, 0), 1))
        if tool == .crop {
            let start = CGPoint(x: value.startLocation.x / size.width, y: value.startLocation.y / size.height)
            let rect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x), height: abs(point.y - start.y))
            crop = rect.width > 0.02 && rect.height > 0.02 ? rect : nil
            return
        }
        if var current = draft {
            if tool == .pen || tool == .highlighter {
                current.points.append(point)
            } else {
                current.points = [current.points[0], point]
            }
            draft = current
        } else {
            let start = CGPoint(x: value.startLocation.x / size.width, y: value.startLocation.y / size.height)
            draft = Mark(tool: tool, color: color, points: [start, point])
        }
    }

    private func commit() {
        if let draft { marks.append(draft) }
        draft = nil
    }

    // MARK: Export

    /// Marks drawn at full resolution, then crop, frame and watermark.
    private func rendered() -> NSImage {
        let pixels = image.representations.first.map { CGFloat($0.pixelsWide) } ?? image.size.width
        let scale = max(pixels / max(image.size.width, 1), 1)
        let marked = ImageRenderer(content: AnnotatedImage(image: image, marks: marks).frame(width: image.size.width, height: image.size.height))
        marked.scale = scale
        guard var cgImage = marked.cgImage else { return image }
        var size = image.size
        if let crop, let cropped = cgImage.cropping(to: CGRect(x: crop.minX * CGFloat(cgImage.width), y: crop.minY * CGFloat(cgImage.height),
                                                               width: crop.width * CGFloat(cgImage.width), height: crop.height * CGFloat(cgImage.height)).integral) {
            cgImage = cropped
            size = CGSize(width: size.width * crop.width, height: size.height * crop.height)
        }
        let base = NSImage(cgImage: cgImage, size: size)
        guard backdrop != .none || !watermark.isEmpty else { return base }
        let final = ImageRenderer(content: FinalShot(image: base, backdrop: backdrop, watermark: watermark))
        final.scale = scale
        return final.nsImage ?? base
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([rendered()])
    }

    private func save(_ t: Localizer) {
        let image = rendered()
        guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let url = desktop.appendingPathComponent("Lumo \(formatter.string(from: Date())).png")
        guard (try? png.write(to: url, options: .atomic)) != nil else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        toast = t("Сохранено на Рабочий стол", "Saved to Desktop")
        Task { try? await Task.sleep(for: .seconds(1.4)); toast = nil }
    }

    private static func fit(_ size: CGSize, in bounds: CGSize) -> CGSize {
        let scale = min(bounds.width / max(size.width, 1), bounds.height / max(size.height, 1), 1)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

/// The screenshot with all marks drawn on top; used both on screen and for export.
private struct AnnotatedImage: View {
    let image: NSImage
    let marks: [Mark]

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Image(nsImage: image).resizable()
                Canvas { context, _ in
                    for mark in marks { Self.draw(mark, in: &context, size: size) }
                }
            }
        }
    }

    private static func draw(_ mark: Mark, in context: inout GraphicsContext, size: CGSize) {
        let points = mark.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        guard let first = points.first, let last = points.last else { return }
        let width = max(size.width, size.height) / 260
        let rect = CGRect(x: min(first.x, last.x), y: min(first.y, last.y), width: abs(last.x - first.x), height: abs(last.y - first.y))
        switch mark.tool {
        case .pen, .highlighter:
            var path = Path()
            path.addLines(points)
            let highlight = mark.tool == .highlighter
            context.stroke(path, with: .color(mark.color.opacity(highlight ? 0.35 : 1)),
                           style: StrokeStyle(lineWidth: highlight ? width * 5 : width, lineCap: .round, lineJoin: .round))
        case .rectangle:
            context.stroke(Path(roundedRect: rect, cornerRadius: width * 1.5), with: .color(mark.color),
                           style: StrokeStyle(lineWidth: width, lineJoin: .round))
        case .redact:
            context.fill(Path(roundedRect: rect, cornerRadius: width), with: .color(.black))
        case .crop:
            break
        case .arrow:
            var path = Path()
            path.move(to: first)
            path.addLine(to: last)
            let angle = atan2(last.y - first.y, last.x - first.x)
            let head = width * 4.5
            for offset in [-0.45, 0.45] {
                path.move(to: last)
                path.addLine(to: CGPoint(x: last.x - head * cos(angle + offset), y: last.y - head * sin(angle + offset)))
            }
            context.stroke(path, with: .color(mark.color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
    }
}
