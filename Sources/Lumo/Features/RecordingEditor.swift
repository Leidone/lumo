import AppKit
import AVFoundation
import AVKit
import CoreImage
import LumoCore
import SwiftUI

/// Edits a screen recording: trim the ends, cut pieces out, blur private areas, zoom into clicks,
/// then export MP4 or GIF, share it or get a 24-hour link.
@MainActor
final class RecordingEditorModel: ObservableObject {
    @Published var cuts: [EditRanges.Range] = []
    @Published var pendingCutStart: Double?
    @Published var blurRects: [CGRect] = []
    @Published var autoZoom: Bool
    @Published var drawingBlur = false
    @Published private(set) var isExporting = false
    @Published var message: String?

    let source: URL
    let player: AVPlayer
    let clicks: [AutoZoom.Click]
    let t: Localizer
    weak var recorder: ScreenRecorder?
    var trimStart: Double = 0
    var trimEnd: Double = .greatestFiniteMagnitude

    init(source: URL, recorder: ScreenRecorder?, t: Localizer) {
        self.source = source
        self.recorder = recorder
        self.t = t
        player = AVPlayer(url: source)
        let data = try? Data(contentsOf: ScreenRecorder.clicksURL(for: source))
        clicks = data.flatMap { try? JSONDecoder().decode([AutoZoom.Click].self, from: $0) } ?? []
        autoZoom = !clicks.isEmpty
    }

    var now: Double { player.currentTime().seconds }

    func markCut() {
        if let start = pendingCutStart {
            let range = EditRanges.Range(start: min(start, now), end: max(start, now))
            if range.length > 0.1 { cuts.append(range) }
            pendingCutStart = nil
        } else {
            pendingCutStart = now
        }
    }

    /// Picks up the handles from AVPlayerView's built-in trimming.
    func readTrim() {
        guard let item = player.currentItem else { return }
        let start = item.reversePlaybackEndTime
        let end = item.forwardPlaybackEndTime
        trimStart = start.isValid && !start.isIndefinite ? start.seconds : 0
        trimEnd = end.isValid && !end.isIndefinite ? end.seconds : .greatestFiniteMagnitude
    }

    // MARK: Export

    func export(gif: Bool) async -> URL? {
        guard !isExporting else { return nil }
        isExporting = true
        defer { isExporting = false }
        readTrim()
        do {
            let output = try await render()
            if gif { return try await GIFExporter.export(output) }
            return output
        } catch {
            message = t("Не получилось: ", "Failed: ") + error.localizedDescription
            return nil
        }
    }

    private func render() async throws -> URL {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        let kept = EditRanges.kept(duration: duration, trimStart: trimStart, trimEnd: min(trimEnd, duration), cuts: cuts)
        let composition = AVMutableComposition()
        for track in try await asset.load(.tracks) {
            guard let target = composition.addMutableTrack(withMediaType: track.mediaType, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            var cursor = CMTime.zero
            for range in kept {
                let timeRange = CMTimeRange(start: CMTime(seconds: range.start, preferredTimescale: 600),
                                            duration: CMTime(seconds: range.length, preferredTimescale: 600))
                try target.insertTimeRange(timeRange, of: track, at: cursor)
                cursor = cursor + timeRange.duration
            }
        }
        let blur = blurRects
        let zoomClicks = autoZoom ? clicks : []
        let videoComposition = try await AVVideoComposition.videoComposition(with: composition) { request in
            let extent = request.sourceImage.extent
            var image = request.sourceImage
            for rect in blur {
                let area = CGRect(x: rect.minX * extent.width, y: (1 - rect.maxY) * extent.height, width: rect.width * extent.width, height: rect.height * extent.height)
                image = image.clampedToExtent().applyingGaussianBlur(sigma: 22).cropped(to: area).composited(over: image)
            }
            let zoom = AutoZoom.state(at: EditRanges.sourceTime(request.compositionTime.seconds, in: kept), clicks: zoomClicks)
            if zoom.scale > 1.001 {
                let width = extent.width / zoom.scale, height = extent.height / zoom.scale
                let x = min(max(zoom.center.x * extent.width - width / 2, 0), extent.width - width)
                let y = min(max((1 - zoom.center.y) * extent.height - height / 2, 0), extent.height - height)
                image = image.transformed(by: CGAffineTransform(translationX: -x, y: -y).concatenating(CGAffineTransform(scaleX: zoom.scale, y: zoom.scale)))
            }
            request.finish(with: image.cropped(to: extent), context: nil)
        }
        let output = source.deletingPathExtension().appendingPathExtension("edited.mp4")
        try? FileManager.default.removeItem(at: output)
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw CocoaError(.fileWriteUnknown)
        }
        session.videoComposition = videoComposition
        try await session.export(to: output, as: .mp4)
        return output
    }
}

@MainActor
enum RecordingEditor {
    private static var windows: [NSWindow] = []

    static func open(_ url: URL, recorder: ScreenRecorder?, t: Localizer) {
        let model = RecordingEditorModel(source: url, recorder: recorder, t: t)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 640),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = url.deletingPathExtension().lastPathComponent
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: RecordingEditorView(model: model))
        window.center()
        windows.append(window)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { note in
            let closed = note.object as? NSWindow
            MainActor.assumeIsolated {
                model.player.pause()
                windows.removeAll { $0 === closed }
            }
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

private struct PlayerHost: NSViewRepresentable {
    let model: RecordingEditorModel

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = model.player
        view.controlsStyle = .floating
        view.showsFrameSteppingButtons = true
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {}
}

private struct RecordingEditorView: View {
    @ObservedObject var model: RecordingEditorModel
    @State private var draft: CGRect?
    @State private var playerView: AVPlayerView?

    var body: some View {
        let t = model.t
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack {
                    PlayerHost(model: model)
                    if model.drawingBlur || !model.blurRects.isEmpty {
                        blurOverlay(size: geometry.size)
                    }
                }
            }
            toolbar(t)
        }
        .frame(minWidth: 640, minHeight: 440)
    }

    private func blurOverlay(size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array((model.blurRects + (draft.map { [$0] } ?? [])).enumerated()), id: \.offset) { _, rect in
                RoundedRectangle(cornerRadius: 6).fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.orange.color, lineWidth: 1.5))
                    .frame(width: rect.width * size.width, height: rect.height * size.height)
                    .offset(x: rect.minX * size.width, y: rect.minY * size.height)
            }
            if model.drawingBlur {
                Color.clear.contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            let a = CGPoint(x: value.startLocation.x / size.width, y: value.startLocation.y / size.height)
                            let b = CGPoint(x: value.location.x / size.width, y: value.location.y / size.height)
                            draft = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
                        }
                        .onEnded { _ in
                            if let draft, draft.width > 0.01 { model.blurRects.append(draft) }
                            draft = nil
                            model.drawingBlur = false
                        })
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(model.drawingBlur)
    }

    private func toolbar(_ t: Localizer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button { trim() } label: { Label(t("Обрезать края", "Trim"), systemImage: "timeline.selection") }
                Button { model.markCut() } label: {
                    Label(model.pendingCutStart == nil ? t("Начать вырезку", "Start cut") : t("Закончить вырезку", "End cut"),
                          systemImage: "scissors")
                }
                .tint(model.pendingCutStart == nil ? nil : Palette.orange.color)
                Button { model.drawingBlur = true } label: { Label(t("Размыть область", "Blur an area"), systemImage: "eye.slash") }
                if !model.blurRects.isEmpty {
                    Button(t("Убрать размытие", "Clear blur")) { model.blurRects = [] }
                }
                Toggle(t("Автозум к кликам", "Auto zoom on clicks"), isOn: $model.autoZoom)
                    .disabled(model.clicks.isEmpty)
                    .help(model.clicks.isEmpty ? t("В этой записи не было кликов", "No clicks were recorded") : "")
                Spacer()
            }
            if !model.cuts.isEmpty {
                HStack(spacing: 6) {
                    Text(t("Вырезано:", "Cut:")).font(.system(size: 11))
                    ForEach(Array(model.cuts.enumerated()), id: \.offset) { index, cut in
                        Button { model.cuts.remove(at: index) } label: {
                            Text(String(format: "%.1f–%.1f s ✕", cut.start, cut.end)).font(.system(size: 10.5, design: .rounded))
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
            HStack(spacing: 8) {
                if let message = model.message { Text(message).font(.system(size: 11)).foregroundStyle(.secondary) }
                Spacer()
                if model.isExporting { ProgressView().controlSize(.small) }
                Button(t("Сохранить GIF", "Save GIF")) { finish(gif: true, then: .reveal) }
                Button(t("Поделиться", "Share")) { finish(gif: false, then: .share) }
                Button(t("Ссылка на 24 ч", "24-hour link")) { finish(gif: false, then: .link) }
                Button(t("Сохранить MP4", "Save MP4")) { finish(gif: false, then: .reveal) }.buttonStyle(.borderedProminent)
            }
            .disabled(model.isExporting)
        }
        .padding(12)
        .background(.bar)
    }

    private enum After { case reveal, share, link }

    private func trim() {
        guard let view = findPlayerView() else { return }
        view.beginTrimming { _ in model.readTrim() }
    }

    private func findPlayerView() -> AVPlayerView? {
        NSApp.keyWindow?.contentView.flatMap { Self.search($0) }
    }

    private static func search(_ view: NSView) -> AVPlayerView? {
        if let player = view as? AVPlayerView { return player }
        for child in view.subviews { if let found = search(child) { return found } }
        return nil
    }

    private func finish(gif: Bool, then after: After) {
        Task {
            guard let url = await model.export(gif: gif) else { return }
            model.recorder?.reloadRecordings()
            switch after {
            case .reveal: NSWorkspace.shared.activateFileViewerSelecting([url])
            case .link: await LinkUploader.share(url, t: model.t)
            case .share:
                if let view = NSApp.keyWindow?.contentView {
                    NSSharingServicePicker(items: [url]).show(relativeTo: CGRect(x: view.bounds.maxX - 200, y: 0, width: 1, height: 1), of: view, preferredEdge: .maxY)
                }
            }
        }
    }
}
