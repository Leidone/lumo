import AppKit
import AVFoundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import Vision

/// Local media helpers: compress video, make GIFs, convert/resize/watermark images and pull text out of them.
@MainActor
final class MediaToolsModel: ObservableObject {
    enum ImageFormat: String, CaseIterable, Identifiable {
        case jpeg, png, heic

        var id: Self { self }
        var type: UTType {
            switch self {
            case .jpeg: return .jpeg
            case .png: return .png
            case .heic: return .heic
            }
        }
    }

    @Published var files: [URL] = []
    @Published var format = ImageFormat.jpeg
    @Published var quality = 0.82
    @Published var maxSide = 0
    @Published var watermark = ""
    @Published private(set) var busy = false
    @Published private(set) var status: String?
    let t: Localizer

    init(t: Localizer) {
        self.t = t
    }

    var videos: [URL] { files.filter { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .movie) == true } }
    var images: [URL] { files.filter { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true } }

    func add(_ urls: [URL]) {
        files = Array(Set(files + urls.filter { $0.isFileURL })).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func pick() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .movie]
        if panel.runModal() == .OK { add(panel.urls) }
    }

    private func run(_ label: String, _ work: @escaping @Sendable () async -> [URL]) {
        guard !busy else { return }
        busy = true
        status = label
        Task {
            let outputs = await work()
            busy = false
            status = t("Готово: \(outputs.count)", "Done: \(outputs.count)")
            if !outputs.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(outputs) }
        }
    }

    // MARK: Video

    func compress(hevc: Bool) {
        let inputs = videos
        run(t("Сжимаю видео…", "Compressing video…")) {
            var outputs: [URL] = []
            for url in inputs {
                let preset = hevc ? AVAssetExportPresetHEVC1920x1080 : AVAssetExportPreset1280x720
                guard let session = AVAssetExportSession(asset: AVURLAsset(url: url), presetName: preset) else { continue }
                let output = Self.sibling(of: url, suffix: hevc ? "HEVC" : "720p", ext: "mp4")
                if (try? await session.export(to: output, as: .mp4)) != nil { outputs.append(output) }
            }
            return outputs
        }
    }

    func makeGIFs() {
        let inputs = videos
        run(t("Делаю GIF…", "Making GIFs…")) {
            var outputs: [URL] = []
            for url in inputs {
                if let gif = try? await GIFExporter.export(url) { outputs.append(gif) }
            }
            return outputs
        }
    }

    // MARK: Images

    func convertImages() {
        let inputs = images, format = format, quality = quality, maxSide = maxSide, watermark = watermark
        run(t("Обрабатываю картинки…", "Processing images…")) {
            inputs.compactMap { Self.convert($0, format: format, quality: quality, maxSide: maxSide, watermark: watermark) }
        }
    }

    func extractText() {
        let inputs = images
        run(t("Распознаю текст…", "Reading text…")) {
            var texts: [String] = []
            for url in inputs {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
                else { continue }
                let request = VNRecognizeTextRequest()
                request.recognitionLanguages = ["ru-RU", "en-US"]
                try? VNImageRequestHandler(cgImage: image).perform([request])
                let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                if !text.isEmpty { texts.append("— \(url.lastPathComponent) —\n\(text)") }
            }
            guard let first = inputs.first, !texts.isEmpty else { return [] }
            let output = Self.sibling(of: first, suffix: "text", ext: "txt")
            let joined = texts.joined(separator: "\n\n")
            try? joined.write(to: output, atomically: true, encoding: .utf8)
            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(joined, forType: .string)
            }
            return [output]
        }
    }

    nonisolated private static func convert(_ url: URL, format: ImageFormat, quality: Double, maxSide: Int, watermark: String) -> URL? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        var options: [CFString: Any] = [kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceCreateThumbnailFromImageAlways: true]
        if maxSide > 0 { options[kCGImageSourceThumbnailMaxPixelSize] = maxSide } else {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 4096, height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 4096
            options[kCGImageSourceThumbnailMaxPixelSize] = max(width, height)
        }
        guard var image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        if !watermark.isEmpty, let marked = stamp(image, text: watermark) { image = marked }
        let output = sibling(of: url, suffix: "Lumo", ext: format == .jpeg ? "jpg" : format.rawValue)
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, format.type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output : nil
    }

    /// Draws the text in the bottom-right corner with a soft shadow.
    nonisolated private static func stamp(_ image: CGImage, text: String) -> CGImage? {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let size = CGFloat(max(width, height)) * 0.025
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
        shadow.shadowBlurRadius = size * 0.2
        let attributed = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: NSColor.white.withAlphaComponent(0.8), .shadow: shadow,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        context.textPosition = CGPoint(x: CGFloat(width) - bounds.width - size, y: size)
        CTLineDraw(line, context)
        return context.makeImage()
    }

    nonisolated private static func sibling(of url: URL, suffix: String, ext: String) -> URL {
        let base = url.deletingPathExtension().lastPathComponent
        var candidate = url.deletingLastPathComponent().appendingPathComponent("\(base) (\(suffix)).\(ext)")
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = url.deletingLastPathComponent().appendingPathComponent("\(base) (\(suffix) \(index)).\(ext)")
            index += 1
        }
        return candidate
    }
}

@MainActor
enum MediaToolsWindow {
    private static var window: NSWindow?

    static func open(t: Localizer) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 560), styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = t("Медиа-инструменты", "Media tools")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MediaToolsView(model: MediaToolsModel(t: t)))
        window.center()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

private struct MediaToolsView: View {
    @ObservedObject var model: MediaToolsModel
    @State private var targeted = false

    var body: some View {
        let t = model.t
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down.on.square.fill").font(.system(size: 30)).foregroundStyle(Palette.blue.color)
                    Text(t("Перетащите видео и картинки сюда", "Drop videos and images here")).font(.system(size: 13, weight: .semibold))
                    Button(t("Выбрать файлы…", "Choose files…")) { model.pick() }
                }
                .frame(maxWidth: .infinity, minHeight: 130)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .foregroundStyle(targeted ? Palette.blue.color : Color.secondary.opacity(0.4)))
                .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                    for provider in providers {
                        _ = provider.loadObject(ofClass: URL.self) { url, _ in
                            guard let url else { return }
                            Task { @MainActor in model.add([url]) }
                        }
                    }
                    return true
                }
                if !model.files.isEmpty {
                    Text(t("Видео: \(model.videos.count) · Картинки: \(model.images.count)", "Videos: \(model.videos.count) · Images: \(model.images.count)"))
                        .font(.system(size: 12, weight: .medium))
                }
                GroupBox(t("Видео", "Video")) {
                    HStack {
                        Button(t("Сжать в HEVC 1080p", "Compress to HEVC 1080p")) { model.compress(hevc: true) }
                        Button(t("Уменьшить до 720p", "Shrink to 720p")) { model.compress(hevc: false) }
                        Button(t("Сделать GIF", "Make GIF")) { model.makeGIFs() }
                    }
                    .disabled(model.videos.isEmpty || model.busy)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox(t("Картинки", "Images")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker(t("Формат", "Format"), selection: $model.format) {
                            Text("JPEG").tag(MediaToolsModel.ImageFormat.jpeg)
                            Text("PNG").tag(MediaToolsModel.ImageFormat.png)
                            Text("HEIC").tag(MediaToolsModel.ImageFormat.heic)
                        }
                        .pickerStyle(.segmented)
                        HStack {
                            Text(t("Качество", "Quality"))
                            Slider(value: $model.quality, in: 0.4...1)
                            Text(Format.percent(model.quality)).monospacedDigit()
                        }
                        Picker(t("Размер", "Size"), selection: $model.maxSide) {
                            Text(t("Как есть", "Original")).tag(0)
                            ForEach([3840, 2048, 1280, 800], id: \.self) { Text(t("до \($0) px", "up to \($0) px")).tag($0) }
                        }
                        TextField(t("Водяной знак (необязательно)", "Watermark (optional)"), text: $model.watermark).textFieldStyle(.roundedBorder)
                        HStack {
                            Button(t("Конвертировать", "Convert")) { model.convertImages() }.buttonStyle(.borderedProminent)
                            Button(t("Достать текст", "Extract text")) { model.extractText() }
                        }
                    }
                    .disabled(model.images.isEmpty || model.busy)
                }
                HStack {
                    if model.busy { ProgressView().controlSize(.small) }
                    if let status = model.status { Text(status).font(.system(size: 11.5)).foregroundStyle(.secondary) }
                    Spacer()
                    if !model.files.isEmpty { Button(t("Очистить список", "Clear list")) { model.files = [] } }
                }
                Text(t("Всё делается на этом Mac. Новые файлы сохраняются рядом с исходными.", "Everything runs on this Mac. New files are saved next to the originals."))
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
            .padding(20)
        }
        .frame(minWidth: 480, minHeight: 480)
    }
}
