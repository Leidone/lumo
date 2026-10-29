import Combine
import CoreAudio
import Foundation

/// Which apps are producing sound right now, pushed by CoreAudio instead of polled.
/// Audio taps cost energy for as long as they run (the output device and a Bluetooth link
/// can't idle), so the mixer and the island's equalizer start them only while sound plays.
@MainActor
final class AudioActivity: ObservableObject {
    static let shared = AudioActivity()

    /// Process objects of other apps that are running audio output.
    @Published private(set) var playing: Set<AudioObjectID> = []

    var isAnythingPlaying: Bool { !playing.isEmpty }

    private static let system = AudioObjectID(kAudioObjectSystemObject)
    private static let settleDelay: TimeInterval = 0.25

    private let queue = DispatchQueue.main
    private var users = 0
    private var watched: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var listListener: AudioObjectPropertyListenerBlock?
    private var pendingUpdate: DispatchWorkItem?

    private init() {}

    /// Starts listening on the first user; stops when the last one leaves.
    func retain() {
        users += 1
        guard users == 1 else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.scheduleUpdate() }
        }
        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        AudioObjectAddPropertyListenerBlock(Self.system, &address, queue, listener)
        listListener = listener
        update()
    }

    func release() {
        guard users > 0 else { return }
        users -= 1
        guard users == 0 else { return }
        if let listListener {
            var address = Self.address(kAudioHardwarePropertyProcessObjectList)
            AudioObjectRemovePropertyListenerBlock(Self.system, &address, queue, listListener)
        }
        listListener = nil
        watched.keys.forEach(unwatch)
        pendingUpdate?.cancel()
        playing = []
    }

    /// Several properties change together when playback starts; read them once they settle.
    private func scheduleUpdate() {
        pendingUpdate?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.update() } }
        pendingUpdate = work
        queue.asyncAfter(deadline: .now() + Self.settleDelay, execute: work)
    }

    private func update() {
        guard users > 0 else { return }
        let ownPID = getpid()
        let processes = AudioHW.ids(Self.system, kAudioHardwarePropertyProcessObjectList)
            .filter { (AudioHW.scalar($0, kAudioProcessPropertyPID, initial: pid_t(-1)) ?? -1) != ownPID }
        let alive = Set(processes)
        for object in watched.keys where !alive.contains(object) { unwatch(object) }
        for object in processes where watched[object] == nil { watch(object) }
        let next = Set(processes.filter { (AudioHW.scalar($0, kAudioProcessPropertyIsRunningOutput, initial: UInt32(0)) ?? 0) != 0 })
        if next != playing { playing = next }
    }

    private func watch(_ object: AudioObjectID) {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.scheduleUpdate() }
        }
        var address = Self.address(kAudioProcessPropertyIsRunningOutput)
        guard AudioObjectAddPropertyListenerBlock(object, &address, queue, listener) == noErr else { return }
        watched[object] = listener
    }

    private func unwatch(_ object: AudioObjectID) {
        guard let listener = watched.removeValue(forKey: object) else { return }
        var address = Self.address(kAudioProcessPropertyIsRunningOutput)
        AudioObjectRemovePropertyListenerBlock(object, &address, queue, listener)
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
}
