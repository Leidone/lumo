import AVFoundation
import LumoCore
import AppKit
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

/// Screen recording to MP4 with separate system-audio and microphone tracks, plus GIF export.
@MainActor
final class ScreenRecorder: ObservableObject {
    private enum Key {
        static let systemAudio = "recorder.systemAudio"
        static let microphone = "recorder.microphone"
        static let cursor = "recorder.cursor"
    }

    @Published private(set) var isRecording = false
    @Published private(set) var startedAt: Date?
    @Published private(set) var recordings: [URL] = []
    @Published private(set) var exportingGIF: URL?
    @Published var lastError: String?
    @Published var systemAudio: Bool { didSet { store.set(systemAudio, forKey: Key.systemAudio) } }
    @Published var microphone: Bool { didSet { store.set(microphone, forKey: Key.microphone) } }
    @Published var showCursor: Bool { didSet { store.set(showCursor, forKey: Key.cursor) } }

    var t = Localizer(language: .english)
    let folder: URL

    private let store: UserDefaults
    private var stream: SCStream?
    private var writer: RecordingWriter?
    private let hud = RecordingHUD()
    /// Clicks during the recording, for automatic zoom in the editor.
    private var clicks: [AutoZoom.Click] = []
    private var clickMonitor: Any?
    private var captureArea = CGRect.zero
    private var currentURL: URL?

    init(store: UserDefaults) {
        store.register(defaults: [Key.systemAudio: true, Key.cursor: true])
        self.store = store
        systemAudio = store.bool(forKey: Key.systemAudio)
        microphone = store.bool(forKey: Key.microphone)
        showCursor = store.bool(forKey: Key.cursor)
        folder = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0].appendingPathComponent("Lumo", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        reloadRecordings()
    }

    var supportsMicrophone: Bool {
        if #available(macOS 15.0, *) { return true }
        return false
    }

    func toggle() {
        Task { isRecording ? await stop() : await start() }
    }

    // MARK: Recording

    func start() async { await start(region: nil, on: nil) }

    /// Records the whole display under the pointer, or only `region` (global AppKit coordinates).
    func start(region: CGRect?, on chosenScreen: NSScreen?) async {
        guard !isRecording else { return }
        lastError = nil
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let mouse = NSEvent.mouseLocation
            let screen = chosenScreen ?? NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
            let displayID = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
                lastError = t("Не найден экран для записи", "No display to record")
                return
            }
            let ownApps = content.applications.filter { $0.processID == getpid() }
            let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            let scale = screen?.backingScaleFactor ?? 2
            let area = region ?? screen?.frame ?? CGRect(x: 0, y: 0, width: display.width, height: display.height)
            let width = Int(area.width * scale) & ~1
            let height = Int(area.height * scale) & ~1

            let configuration = SCStreamConfiguration()
            if let region, let screen {
                configuration.sourceRect = CGRect(x: region.minX - screen.frame.minX, y: screen.frame.maxY - region.maxY,
                                                  width: region.width, height: region.height)
            }
            configuration.width = width
            configuration.height = height
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.showsCursor = showCursor
            configuration.capturesAudio = systemAudio
            configuration.excludesCurrentProcessAudio = true
            configuration.sampleRate = 48_000
            configuration.channelCount = 2
            let wantsMicrophone = microphone && supportsMicrophone
            if #available(macOS 15.0, *), wantsMicrophone {
                guard await AVCaptureDevice.requestAccess(for: .audio) else {
                    lastError = t("Нет доступа к микрофону", "Microphone access denied")
                    return
                }
                configuration.captureMicrophone = true
            }

            let url = folder.appendingPathComponent("Lumo \(Self.timestamp()).mp4")
            let writer = try RecordingWriter(url: url, width: width, height: height,
                                             systemAudio: systemAudio, microphone: wantsMicrophone)
            let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
            try stream.addStreamOutput(writer, type: .screen, sampleHandlerQueue: writer.queue)
            if systemAudio { try stream.addStreamOutput(writer, type: .audio, sampleHandlerQueue: writer.queue) }
            if #available(macOS 15.0, *), wantsMicrophone {
                try stream.addStreamOutput(writer, type: .microphone, sampleHandlerQueue: writer.queue)
            }
            try await stream.startCapture()
            self.stream = stream
            self.writer = writer
            isRecording = true
            startedAt = Date()
            currentURL = url
            captureArea = area
            clicks = []
            let start = Date()
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                let point = NSEvent.mouseLocation
                MainActor.assumeIsolated {
                    guard let self, self.captureArea.contains(point) else { return }
                    let normalized = CGPoint(x: (point.x - self.captureArea.minX) / self.captureArea.width,
                                             y: (self.captureArea.maxY - point.y) / self.captureArea.height)
                    self.clicks.append(AutoZoom.Click(time: Date().timeIntervalSince(start), point: normalized))
                }
            }
            hud.show(startedAt: Date(), t: t) { [weak self] in self?.toggle() }
        } catch {
            lastError = t("Не удалось начать запись: ", "Couldn't start recording: ") + error.localizedDescription
        }
    }

    func stop() async {
        guard isRecording, let stream, let writer else { return }
        hud.hide()
        try? await stream.stopCapture()
        let url = await writer.finish()
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        if let url, !clicks.isEmpty, let data = try? JSONEncoder().encode(clicks) {
            try? data.write(to: Self.clicksURL(for: url))
        }
        self.stream = nil
        self.writer = nil
        isRecording = false
        startedAt = nil
        reloadRecordings()
        if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    // MARK: Library

    func reloadRecordings() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        recordings = files.filter { ["mp4", "gif"].contains($0.pathExtension) }
            .sorted { (Self.created($0) ?? .distantPast) > (Self.created($1) ?? .distantPast) }
    }

    func exportGIF(_ url: URL) {
        guard exportingGIF == nil else { return }
        exportingGIF = url
        Task {
            do {
                let gif = try await GIFExporter.export(url)
                NSWorkspace.shared.activateFileViewerSelecting([gif])
            } catch {
                lastError = t("Не удалось сделать GIF", "GIF export failed")
            }
            exportingGIF = nil
            reloadRecordings()
        }
    }

    /// Click positions saved next to a recording.
    static func clicksURL(for url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension("clicks.json")
    }

    private static func created(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: Date())
    }
}

/// Receives ScreenCaptureKit samples on its own queue and writes them with AVAssetWriter.
final class RecordingWriter: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "lumo.recorder")
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let audio: AVAssetWriterInput?
    private let microphone: AVAssetWriterInput?
    private var started = false

    init(url: URL, width: Int, height: Int, systemAudio: Bool, microphone wantsMicrophone: Bool) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: max(width * height * 3, 6_000_000)],
        ])
        video.expectsMediaDataInRealTime = true
        writer.add(video)
        let audioSettings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
                                            AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 160_000]
        audio = systemAudio ? AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings) : nil
        microphone = wantsMicrophone ? AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings) : nil
        for input in [audio, microphone].compactMap({ $0 }) {
            input.expectsMediaDataInRealTime = true
            writer.add(input)
        }
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        switch type {
        case .screen:
            guard Self.isCompleteFrame(sampleBuffer) else { return }
            if !started {
                writer.startWriting()
                writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
                started = true
            }
            if video.isReadyForMoreMediaData { video.append(sampleBuffer) }
        case .audio:
            if started, let audio, audio.isReadyForMoreMediaData { audio.append(sampleBuffer) }
        default:
            if started, let microphone, microphone.isReadyForMoreMediaData { microphone.append(sampleBuffer) }
        }
    }

    func finish() async -> URL? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard started else { return continuation.resume(returning: nil) }
                [video, audio, microphone].compactMap { $0 }.forEach { $0.markAsFinished() }
                writer.finishWriting { [writer] in
                    continuation.resume(returning: writer.status == .completed ? writer.outputURL : nil)
                }
            }
        }
    }

    private static func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int
        else { return false }
        return SCFrameStatus(rawValue: raw) == .complete
    }
}

enum GIFExporter {
    private static let fps = 12.0
    private static let maxFrames = 720
    private static let maxSide: CGFloat = 720

    static func export(_ url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let seconds = try await asset.load(.duration).seconds
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSide, height: maxSide)
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 24)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 24)

        let count = min(Int(seconds * fps), maxFrames)
        let output = url.deletingPathExtension().appendingPathExtension("gif")
        guard count > 0, let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, count, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary
        for index in 0..<count {
            let time = CMTime(seconds: Double(index) / fps, preferredTimescale: 600)
            let (image, _) = try await generator.image(at: time)
            CGImageDestinationAddImage(destination, image, frameProperties)
        }
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return output
    }
}

// MARK: - Recording HUD

@MainActor
final class RecordingHUD {
    private var panel: NSPanel?

    func show(startedAt: Date, t: Localizer, stop: @escaping () -> Void) {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.sharingType = .none
        let host = NSHostingView(rootView: RecordingHUDView(startedAt: startedAt, stopTitle: t("Стоп", "Stop"), stop: stop))
        panel.contentView = host
        let size = host.fittingSize
        if let screen = NSScreen.main {
            panel.setFrame(CGRect(x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height - 10,
                                  width: size.width, height: size.height), display: true)
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct RecordingHUDView: View {
    let startedAt: Date
    let stopTitle: String
    let stop: () -> Void
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Palette.red.color).frame(width: 10, height: 10)
                .opacity(pulse ? 0.35 : 1)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
            Text(startedAt, style: .timer).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(.white)
            Button(action: stop) {
                Label(stopTitle, systemImage: "stop.fill").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.red.color)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
        .background(Capsule().fill(Color.black.opacity(0.35)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.15)))
        .padding(6)
        .fixedSize()
        .onAppear { pulse = true }
    }
}
