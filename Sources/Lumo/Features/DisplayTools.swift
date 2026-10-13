import AppKit
import CoreGraphics
import IOKit
import QuartzCore

/// Brightness for every display: the built-in panel through DisplayServices, external monitors over DDC/CI,
/// finer steps for the brightness keys, software dimming (also below the minimum) and XDR extra brightness.
@MainActor
final class DisplayTools: ObservableObject {
    struct Display: Identifiable, Equatable {
        let id: CGDirectDisplayID
        let name: String
        let isBuiltIn: Bool
        let hasDDC: Bool
        let edrHeadroom: CGFloat
        var brightness: Double
        var dimming: Double
    }

    enum StepMode: String, CaseIterable, Identifiable {
        case normal, half, quarter

        var id: Self { self }
        var divisor: Double {
            switch self {
            case .normal: return 1
            case .half: return 2
            case .quarter: return 4
            }
        }
    }

    private enum Key {
        static let steps = "display.steps"
        static let extraDimming = "display.extraDimming"
        static let xdr = "display.xdr"
        static let boost = "display.xdrBoost"
        static let external = "display.externalBrightness"
    }

    private static let keyStep = 1.0 / 16

    @Published private(set) var displays: [Display] = []
    @Published var steps: StepMode { didSet { store.set(steps.rawValue, forKey: Key.steps); onChange?() } }
    @Published var extraDimming: Bool { didSet { store.set(extraDimming, forKey: Key.extraDimming) } }
    @Published var xdrBoost: Bool { didSet { store.set(xdrBoost, forKey: Key.xdr); applyXDR() } }
    @Published var boost: Double { didSet { store.set(boost, forKey: Key.boost); applyXDR() } }

    var onChange: (() -> Void)?
    var t = Localizer(language: .english)
    private let store: UserDefaults
    private var overlays: [NSWindow] = []
    private var swallowKeyUp = false

    init(store: UserDefaults) {
        store.register(defaults: [Key.boost: 1.5])
        self.store = store
        steps = StepMode(rawValue: store.string(forKey: Key.steps) ?? "") ?? .normal
        extraDimming = store.bool(forKey: Key.extraDimming)
        xdrBoost = store.bool(forKey: Key.xdr)
        boost = store.double(forKey: Key.boost)
    }

    var supportsXDR: Bool { displays.contains { $0.edrHeadroom > 1 } }

    func refresh() {
        let externalServices = DDC.externalServices()
        var externalIndex = 0
        let saved = store.dictionary(forKey: Key.external) as? [String: Double] ?? [:]
        displays = NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
            let builtIn = CGDisplayIsBuiltin(id) != 0
            let hasDDC = !builtIn && externalIndex < externalServices.count
            if !builtIn { externalIndex += 1 }
            let brightness = builtIn ? (BuiltInBrightness.get(id) ?? 0.5) : (saved[String(id)] ?? 0.7)
            let previous = displays.first { $0.id == id }
            return Display(id: id, name: screen.localizedName, isBuiltIn: builtIn, hasDDC: hasDDC,
                           edrHeadroom: screen.maximumPotentialExtendedDynamicRangeColorComponentValue,
                           brightness: brightness, dimming: previous?.dimming ?? 0)
        }
    }

    func setBrightness(_ display: Display, _ value: Double) {
        let clamped = min(max(value, 0), 1)
        if display.isBuiltIn {
            BuiltInBrightness.set(display.id, clamped)
        } else if display.hasDDC, let service = service(for: display) {
            DDC.setBrightness(service, Int((clamped * 100).rounded()))
            var saved = store.dictionary(forKey: Key.external) as? [String: Double] ?? [:]
            saved[String(display.id)] = clamped
            store.set(saved, forKey: Key.external)
        } else {
            // No hardware control: fall back to dimming the picture itself.
            return setDimming(display, 1 - clamped)
        }
        update(display.id) { $0.brightness = clamped }
    }

    /// Software dimming through the display's gamma table (0 = off, 0.85 = darkest).
    func setDimming(_ display: Display, _ value: Double) {
        let level = min(max(value, 0), 0.85)
        let top = CGGammaValue(1 - level)
        CGSetDisplayTransferByFormula(display.id, 0, top, 1, 0, top, 1, 0, top, 1)
        update(display.id) { $0.dimming = level }
    }

    func shutdown() {
        CGDisplayRestoreColorSyncSettings()
        overlays.forEach { $0.orderOut(nil) }
        overlays = []
    }

    private func update(_ id: CGDirectDisplayID, _ change: (inout Display) -> Void) {
        displays = displays.map { display in
            guard display.id == id else { return display }
            var copy = display
            change(&copy)
            return copy
        }
    }

    private func service(for display: Display) -> AnyObject? {
        let externals = displays.filter { !$0.isBuiltIn }
        guard let index = externals.firstIndex(where: { $0.id == display.id }) else { return nil }
        let services = DDC.externalServices()
        return index < services.count ? services[index] : nil
    }

    // MARK: Brightness keys

    var usesTap: Bool { steps != .normal || extraDimming }

    var handlers: [(mask: CGEventMask, handle: InputTap.Handler)] {
        guard usesTap else { return [] }
        let systemDefined = CGEventType(rawValue: 14)!
        return [(InputTap.mask(systemDefined), { [weak self] _, event in self?.handleKey(event) ?? event })]
    }

    private func handleKey(_ event: CGEvent) -> CGEvent? {
        guard let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return event }
        let key = (ns.data1 & 0xFFFF_0000) >> 16
        let pressed = (ns.data1 & 0xFF00) >> 8 == 0x0A
        guard key == Int(NX_KEYTYPE_BRIGHTNESS_UP) || key == Int(NX_KEYTYPE_BRIGHTNESS_DOWN) else { return event }
        guard pressed else { return nil }
        if displays.isEmpty { refresh() }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        let id = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        guard let display = displays.first(where: { $0.id == id }) ?? displays.first else { return event }
        let delta = Self.keyStep / steps.divisor * (key == Int(NX_KEYTYPE_BRIGHTNESS_UP) ? 1 : -1)
        if delta < 0, display.brightness <= 0.001, extraDimming {
            setDimming(display, display.dimming + 0.05)
        } else if delta > 0, display.dimming > 0 {
            setDimming(display, display.dimming - 0.05)
        } else {
            setBrightness(display, display.brightness + delta)
        }
        let current = displays.first { $0.id == display.id }
        let percent = current.map { $0.dimming > 0 ? -$0.dimming : $0.brightness } ?? 0
        Toast.show(percent < 0 ? "moon.fill" : "sun.max.fill",
                   percent < 0 ? t("Затемнение ", "Dimmed ") + Format.percent(-percent) : t("Яркость ", "Brightness ") + Format.percent(percent),
                   subtitle: display.name, tint: Palette.yellow.color)
        return nil
    }

    // MARK: XDR extra brightness

    /// An EDR overlay that multiplies the picture above SDR white on displays with HDR headroom.
    private func applyXDR() {
        overlays.forEach { $0.orderOut(nil) }
        overlays = []
        guard xdrBoost else { return }
        for screen in NSScreen.screens where screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1 {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.ignoresMouseEvents = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            if let layer = view.layer {
                layer.wantsExtendedDynamicRangeContent = true
                let value = CGFloat(min(boost, Double(screen.maximumPotentialExtendedDynamicRangeColorComponentValue)))
                layer.backgroundColor = CGColor(colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!, components: [value, value, value, 1])
                layer.compositingFilter = "multiplyBlendMode"
            }
            window.contentView = view
            window.orderFrontRegardless()
            overlays.append(window)
        }
    }
}

/// The built-in panel's brightness (private DisplayServices calls, as used by Control Center).
enum BuiltInBrightness {
    private typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Set = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    static func get(_ id: CGDirectDisplayID) -> Double? {
        guard let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        var value: Float = 0
        return unsafeBitCast(symbol, to: Get.self)(id, &value) == 0 ? Double(value) : nil
    }

    static func set(_ id: CGDirectDisplayID, _ value: Double) {
        guard let symbol = dlsym(handle, "DisplayServicesSetBrightness") else { return }
        _ = unsafeBitCast(symbol, to: Set.self)(id, Float(value))
    }
}

/// DDC/CI over the Apple silicon display pipe (IOAVService), for external monitors that support it.
enum DDC {
    private typealias Create = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<AnyObject>?
    private typealias Write = @convention(c) (AnyObject, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> Int32
    private static let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
    private static let brightnessCode: UInt8 = 0x10

    static func externalServices() -> [AnyObject] {
        guard let createSymbol = dlsym(handle, "IOAVServiceCreateWithService") else { return [] }
        let create = unsafeBitCast(createSymbol, to: Create.self)
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var services: [AnyObject] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            let location = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
            guard location == "External", let service = create(kCFAllocatorDefault, entry)?.takeRetainedValue() else { continue }
            services.append(service)
        }
        return services
    }

    /// VCP 0x10 (luminance), 0…100.
    static func setBrightness(_ service: AnyObject, _ value: Int) {
        guard let writeSymbol = dlsym(handle, "IOAVServiceWriteI2C") else { return }
        let write = unsafeBitCast(writeSymbol, to: Write.self)
        let clamped = UInt16(min(max(value, 0), 100))
        var packet: [UInt8] = [0x84, 0x03, brightnessCode, UInt8(clamped >> 8), UInt8(clamped & 0xFF), 0]
        packet[5] = packet[0..<5].reduce(0x6E ^ 0x51) { $0 ^ $1 }
        // Some monitors drop the first write; sending it twice is the usual remedy.
        for _ in 0..<2 {
            _ = packet.withUnsafeMutableBytes { write(service, 0x37, 0x51, $0.baseAddress!, UInt32($0.count)) }
            usleep(10_000)
        }
    }
}
