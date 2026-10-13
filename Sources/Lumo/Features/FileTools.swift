import AppKit
import SwiftUI

// MARK: - Floating shelf

/// The Shelf as a floating panel: open it with a shortcut, or shake the pointer while dragging
/// something and it appears right there to drop onto.
@MainActor
final class ShelfPanelController: ObservableObject {
    private enum Key {
        static let shake = "files.shelfShake"
        static let hotKey = "files.shelfHotKey"
    }

    private static let size = CGSize(width: 360, height: 170)
    private static let shakeWindow: TimeInterval = 0.6
    private static let shakeReversals = 3

    @Published var shakeToOpen: Bool { didSet { store.set(shakeToOpen, forKey: Key.shake); configure() } }
    @Published var hotKeyEnabled: Bool { didSet { store.set(hotKeyEnabled, forKey: Key.hotKey); configure() } }

    var t = Localizer(language: .english)
    private let shelf: ShelfStore
    private let store: UserDefaults
    private let hotKeys = HotKeyCenter()
    private var panel: NSPanel?
    private var monitors: [Any] = []
    private var dragChange = NSPasteboard(name: .drag).changeCount
    private var lastX: CGFloat?
    private var lastDirection = 0
    private var reversals: [TimeInterval] = []

    init(shelf: ShelfStore, store: UserDefaults) {
        self.shelf = shelf
        self.store = store
        store.register(defaults: [Key.shake: true, Key.hotKey: true])
        shakeToOpen = store.bool(forKey: Key.shake)
        hotKeyEnabled = store.bool(forKey: Key.hotKey)
    }

    func start() { configure() }

    func toggle() {
        if panel?.isVisible == true { return hide() }
        show(at: NSEvent.mouseLocation)
    }

    func hide() { panel?.orderOut(nil) }

    private func configure() {
        hotKeys.unregisterAll()
        if hotKeyEnabled { hotKeys.register(.shelf) { [weak self] in self?.toggle() } }
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        guard shakeToOpen else { return }
        if let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.beginDrag() }
        }) { monitors.append(down) }
        if let drag = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] event in
            let x = NSEvent.mouseLocation.x
            let timestamp = event.timestamp
            MainActor.assumeIsolated { self?.dragged(x: x, at: timestamp) }
        }) { monitors.append(drag) }
    }

    private func beginDrag() {
        dragChange = NSPasteboard(name: .drag).changeCount
        lastX = nil
        lastDirection = 0
        reversals = []
    }

    /// Three quick left-right reversals while something is being dragged count as a shake.
    private func dragged(x: CGFloat, at time: TimeInterval) {
        guard NSPasteboard(name: .drag).changeCount != dragChange, panel?.isVisible != true else { return }
        defer { lastX = x }
        guard let last = lastX, abs(x - last) > 6 else { return }
        let direction = x > last ? 1 : -1
        if lastDirection != 0, direction != lastDirection {
            reversals = reversals.filter { time - $0 < Self.shakeWindow } + [time]
            if reversals.count >= Self.shakeReversals {
                reversals = []
                show(at: NSEvent.mouseLocation)
            }
        }
        lastDirection = direction
    }

    private func show(at point: CGPoint) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main ?? NSScreen.screens[0]
        var origin = CGPoint(x: point.x - Self.size.width / 2, y: point.y + 24)
        origin.x = min(max(origin.x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - Self.size.width - 8)
        origin.y = min(max(origin.y, screen.visibleFrame.minY + 8), screen.visibleFrame.maxY - Self.size.height - 8)
        panel.setFrame(CGRect(origin: origin, size: Self.size), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; panel.animator().alphaValue = 1 }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: ShelfPanelView(shelf: shelf, t: t) { [weak self] in self?.hide() })
        return panel
    }
}

private struct ShelfPanelView: View {
    @ObservedObject var shelf: ShelfStore
    let t: Localizer
    let close: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Label(t("Полка", "Shelf"), systemImage: "tray.full.fill").font(.system(size: 12, weight: .bold, design: .rounded))
                Spacer()
                Button(action: close) { Image(systemName: "xmark.circle.fill").font(.system(size: 14)) }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.6))
            }
            IslandFilesTab(shelf: shelf, t: t)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navyGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
    }
}

// MARK: - Disk image installer

/// When a disk image with an app is mounted, offers to install it, eject the image and
/// (optionally) move the downloaded .dmg to the Trash.
@MainActor
final class DMGInstaller: ObservableObject {
    private enum Key {
        static let enabled = "files.dmgInstaller"
        static let trashImage = "files.dmgTrash"
    }

    struct Offer: Identifiable {
        let id = UUID()
        let app: URL
        let volume: URL
        let image: URL?
    }

    @Published var isEnabled: Bool { didSet { store.set(isEnabled, forKey: Key.enabled); configure() } }
    @Published var trashImage: Bool { didSet { store.set(trashImage, forKey: Key.trashImage) } }
    @Published private(set) var offer: Offer?
    @Published private(set) var isInstalling = false

    var t = Localizer(language: .english)
    private let store: UserDefaults
    private var observer: NSObjectProtocol?
    private var panel: NSPanel?

    init(store: UserDefaults) {
        self.store = store
        store.register(defaults: [Key.trashImage: true])
        isEnabled = store.bool(forKey: Key.enabled)
        trashImage = store.bool(forKey: Key.trashImage)
    }

    func start() { configure() }

    private func configure() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
        guard isEnabled else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] note in
            let volume = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
            MainActor.assumeIsolated { volume.map { self?.mounted($0) } }
        }
    }

    private func mounted(_ volume: URL) {
        let items = (try? FileManager.default.contentsOfDirectory(at: volume, includingPropertiesForKeys: [.isSymbolicLinkKey])) ?? []
        guard let app = items.first(where: {
            $0.pathExtension == "app" && (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
        }) else { return }
        Task {
            let image = await Self.imagePath(for: volume)
            offer = Offer(app: app, volume: volume, image: image)
            showPanel()
        }
    }

    func dismiss() {
        offer = nil
        panel?.orderOut(nil)
    }

    func install() {
        guard let offer, !isInstalling else { return }
        isInstalling = true
        let trash = trashImage
        Task {
            let destination = URL(fileURLWithPath: "/Applications").appendingPathComponent(offer.app.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try? await NSWorkspace.shared.recycle([destination])
            }
            let copied = await Task.detached { (try? FileManager.default.copyItem(at: offer.app, to: destination)) != nil }.value
            isInstalling = false
            dismiss()
            guard copied else {
                Toast.show("xmark.octagon.fill", t("Не удалось установить", "Couldn't install"), subtitle: offer.app.lastPathComponent, tint: Palette.red.color)
                return
            }
            try? NSWorkspace.shared.unmountAndEjectDevice(at: offer.volume)
            let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path
            if trash, let image = offer.image, image.path.hasPrefix(downloads) {
                _ = try? await NSWorkspace.shared.recycle([image])
            }
            Toast.show("checkmark.seal.fill", t("Установлено", "Installed"), subtitle: destination.deletingPathExtension().lastPathComponent,
                       tint: Palette.green.color)
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        }
    }

    /// The .dmg file behind a mounted volume, from `hdiutil info`.
    private static func imagePath(for volume: URL) async -> URL? {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = ["info", "-plist"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let images = plist["images"] as? [[String: Any]]
            else { return nil }
            for image in images {
                let entities = image["system-entities"] as? [[String: Any]] ?? []
                if entities.contains(where: { ($0["mount-point"] as? String) == volume.path }), let path = image["image-path"] as? String {
                    return URL(fileURLWithPath: path)
                }
            }
            return nil
        }.value
    }

    private func showPanel() {
        let panel = self.panel ?? {
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: DMGOfferView(installer: self))
            return panel
        }()
        self.panel = panel
        guard let screen = NSScreen.main else { return }
        let size = CGSize(width: 340, height: 150)
        panel.setFrame(CGRect(x: screen.visibleFrame.maxX - size.width - 16, y: screen.visibleFrame.maxY - size.height - 16,
                              width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }
}

private struct DMGOfferView: View {
    @ObservedObject var installer: DMGInstaller

    var body: some View {
        let t = installer.t
        VStack(alignment: .leading, spacing: 10) {
            if let offer = installer.offer {
                HStack(spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: offer.app.path)).resizable().frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("Установить ", "Install ") + offer.app.deletingPathExtension().lastPathComponent + "?")
                            .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(t("Скопирую в «Программы» и извлеку образ", "I'll copy it to Applications and eject the image"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Toggle(t("Удалить .dmg из «Загрузок»", "Move the .dmg from Downloads to Trash"), isOn: $installer.trashImage)
                    .font(.system(size: 11)).toggleStyle(.checkbox)
                HStack {
                    Button(t("Не сейчас", "Not now")) { installer.dismiss() }
                    Spacer()
                    Button {
                        installer.install()
                    } label: {
                        if installer.isInstalling { ProgressView().controlSize(.small) } else { Text(t("Установить", "Install")) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navyGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
