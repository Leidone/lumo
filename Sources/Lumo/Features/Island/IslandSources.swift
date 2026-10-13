import Accelerate
import AppKit
import AVFoundation
import CoreAudio
import LumoCore
import os
import SQLite3
import SwiftUI

// MARK: - Notifications

/// Reads recent banners from Notification Center's own database (needs Full Disk Access).
/// Read-only; polled every few seconds only while the island shows notifications.
@MainActor
final class NotificationFeed: ObservableObject {
    struct Notice: Identifiable, Equatable {
        let id: Int64
        let bundleID: String
        let payload: NotificationPayload
        let date: Date
    }

    nonisolated private static let databaseURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db")
    nonisolated private static let limit = 12

    @Published private(set) var notices: [Notice] = []
    @Published private(set) var hasAccess = false
    var onNew: ((Notice) -> Void)?

    private var timer: Timer?
    private var lastModified: Date?
    private var newestID: Int64?

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.poll() } }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    static func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }

    private func poll() {
        hasAccess = FileManager.default.isReadableFile(atPath: Self.databaseURL.path)
        guard hasAccess else { return }
        let wal = Self.databaseURL.path + "-wal"
        let modified = (try? FileManager.default.attributesOfItem(atPath: wal))?[.modificationDate] as? Date
        guard modified != lastModified || notices.isEmpty else { return }
        lastModified = modified
        let fresh = Self.read()
        let previousNewest = newestID
        newestID = fresh.first?.id ?? newestID
        notices = fresh
        if let previousNewest, let latest = fresh.first, latest.id > previousNewest { onNew?(latest) }
    }

    nonisolated private static func read() -> [Notice] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(database)
            return []
        }
        defer { sqlite3_close(database) }
        let query = """
            SELECT r.rec_id, a.identifier, r.data, r.delivered_date FROM record r
            JOIN app a ON a.app_id = r.app_id ORDER BY r.rec_id DESC LIMIT \(limit)
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var notices: [Notice] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let bundleID = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let length = Int(sqlite3_column_bytes(statement, 2))
            guard length > 0, let blob = sqlite3_column_blob(statement, 2) else { continue }
            let data = Data(bytes: blob, count: length)
            guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let payload = NotificationPayload(plist: plist)
            else { continue }
            let date = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 3))
            notices.append(Notice(id: id, bundleID: bundleID, payload: payload, date: date))
        }
        return notices
    }
}

// MARK: - Camera

/// A mirrored live camera preview; the session runs only while the view is on screen.
struct CameraPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> CameraPreviewView { CameraPreviewView() }

    func updateNSView(_ view: CameraPreviewView, context: Context) {}

    static func dismantleNSView(_ view: CameraPreviewView, coordinator: ()) { view.stop() }
}

final class CameraPreviewView: NSView {
    private let session = AVCaptureSession()
    private let preview: AVCaptureVideoPreviewLayer
    private let queue = DispatchQueue(label: "lumo.camera")

    init() {
        preview = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        preview.videoGravity = .resizeAspectFill
        preview.connection?.automaticallyAdjustsVideoMirroring = false
        layer?.addSublayer(preview)
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted else { return }
            DispatchQueue.main.async { self?.configure() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        preview.frame = bounds
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }
        session.beginConfiguration()
        session.sessionPreset = .medium
        session.addInput(input)
        session.commitConfiguration()
        if let connection = preview.connection, connection.isVideoMirroringSupported {
            connection.isVideoMirrored = true
        }
        let session = self.session
        queue.async { session.startRunning() }
    }

    func stop() {
        let session = self.session
        queue.async { session.stopRunning() }
    }
}

// MARK: - Live equalizer

/// Listens to everything the Mac plays (a private, unmuted CoreAudio tap) and turns it into four
/// frequency bands for the island's equalizer. Runs only while the equalizer is visible.
@available(macOS 14.2, *)
final class AudioLevelMeter: @unchecked Sendable {
    static let bandCount = 4
    private static let frameCount = 512
    private static let bandBins: [ClosedRange<Int>] = [1...2, 3...8, 9...32, 33...128]

    private let levels = OSAllocatedUnfairLock(initialState: [Float](repeating: 0, count: bandCount))
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var aggregate = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "lumo.meter", qos: .userInteractive)
    private let dft = try? vDSP.DiscreteFourierTransform(previous: nil, count: frameCount, direction: .forward, transformType: .complexComplex, ofType: Float.self)
    private var samples = [Float](repeating: 0, count: frameCount)
    private var filled = 0
    private let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: frameCount, isHalfWindow: false)

    var current: [Float] { levels.withLock { $0 } }

    func start() -> Bool {
        guard procID == nil, let outputUID = AudioHW.deviceUID(AudioHW.defaultOutputDevice()) else { return procID != nil }
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        description.isPrivate = true
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr else { return false }
        let configuration: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Lumo Meter",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        guard AudioHardwareCreateAggregateDevice(configuration as CFDictionary, &aggregate) == noErr else {
            stop()
            return false
        }
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregate, queue) { [weak self] _, input, _, output, _ in
            self?.process(input, output)
        }
        guard status == noErr, let procID, AudioDeviceStart(aggregate, procID) == noErr else {
            stop()
            return false
        }
        return true
    }

    func stop() {
        if let procID {
            AudioDeviceStop(aggregate, procID)
            AudioDeviceDestroyIOProcID(aggregate, procID)
        }
        procID = nil
        if aggregate != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregate) }
        if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
        aggregate = AudioObjectID(kAudioObjectUnknown)
        tap = AudioObjectID(kAudioObjectUnknown)
        levels.withLock { $0 = [Float](repeating: 0, count: Self.bandCount) }
    }

    private func process(_ input: UnsafePointer<AudioBufferList>, _ output: UnsafeMutablePointer<AudioBufferList>) {
        // We only listen: the aggregate's own output stays silent.
        for buffer in UnsafeMutableAudioBufferListPointer(output) {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = inputs.first, let data = first.mData else { return }
        let channels = max(Int(first.mNumberChannels), 1)
        let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size / channels
        let pointer = data.assumingMemoryBound(to: Float.self)
        for frame in 0..<frames {
            samples[filled] = pointer[frame * channels]
            filled += 1
            if filled == Self.frameCount {
                analyze()
                filled = 0
            }
        }
    }

    private func analyze() {
        guard let dft else { return }
        let windowed = vDSP.multiply(samples, window)
        let imaginary = [Float](repeating: 0, count: Self.frameCount)
        let (real, imag) = dft.transform(real: windowed, imaginary: imaginary)
        var bands = [Float](repeating: 0, count: Self.bandCount)
        for (index, bins) in Self.bandBins.enumerated() {
            var energy: Float = 0
            for bin in bins { energy += real[bin] * real[bin] + imag[bin] * imag[bin] }
            let decibels = 10 * log10(max(energy / Float(bins.count), 1e-9))
            bands[index] = min(max((decibels + 10) / 50, 0), 1)
        }
        let measured = bands
        levels.withLock { current in
            for index in current.indices {
                // Fast attack, slow release, like a real VU meter.
                current[index] = measured[index] > current[index] ? measured[index] : current[index] * 0.82 + measured[index] * 0.18
            }
        }
    }
}
