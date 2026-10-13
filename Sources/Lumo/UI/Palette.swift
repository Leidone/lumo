import AppKit
import SwiftUI

/// Apple system colors (dark-mode variants, as used across apple.com).
struct PaletteColor {
    let red: Double
    let green: Double
    let blue: Double

    init(_ hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }
    var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
}

enum Palette {
    static let blue = PaletteColor(0x0A84FF)
    static let indigo = PaletteColor(0x5E5CE6)
    static let purple = PaletteColor(0xBF5AF2)
    static let pink = PaletteColor(0xFF375F)
    static let red = PaletteColor(0xFF453A)
    static let orange = PaletteColor(0xFF9F0A)
    static let yellow = PaletteColor(0xFFD60A)
    static let green = PaletteColor(0x30D158)
    static let mint = PaletteColor(0x63E6E2)
    static let cyan = PaletteColor(0x64D2FF)

    // Deep navy theme (shared with Transcribation): calm blues and indigo on a dark blue field.
    static let navy = PaletteColor(0x0B1230)
    static let navyDeep = PaletteColor(0x060A1C)
    static let navyLight = PaletteColor(0x1B2A5C)
    static let plum = PaletteColor(0x2B1A44)
    static let periwinkle = PaletteColor(0x8E9BFF)
    static let azure = PaletteColor(0x4C7DFF)

    /// Closed loops (first == last) for seamless conic gradients.
    static let cpuLoop = [azure, indigo, purple, indigo, blue, azure]
    static let memoryLoop = [cyan, blue, indigo, blue, cyan]
    /// The "working" shimmer: blues and violets only.
    static let rainbowLoop = [blue, indigo, purple, periwinkle, cyan, blue]

    // Rings and charts stay in the navy family: azure, sky and violet.
    static let cpuColors = [azure, indigo, purple].map(\.color)
    static let memoryColors = [cyan, blue, azure].map(\.color)
    static let diskColors = [periwinkle, indigo, purple].map(\.color)
    static let intensityColors = [green, yellow, orange, pink].map(\.color)
    static let thresholdColors = [cyan, azure, indigo].map(\.color)

    /// Headline gradient: white into periwinkle and blue.
    static var brand: LinearGradient {
        LinearGradient(colors: [Color.white, periwinkle.color, azure.color], startPoint: .leading, endPoint: .trailing)
    }

    /// Accent fill for primary buttons and selections.
    static var accent: LinearGradient {
        LinearGradient(colors: [indigo.color, azure.color], startPoint: .leading, endPoint: .trailing)
    }

    /// The dark blue glass used by every floating Lumo panel.
    static var panelFill: LinearGradient {
        LinearGradient(colors: [navyLight.color.opacity(0.92), navy.color.opacity(0.96), plum.color.opacity(0.9)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func health(_ load: Double) -> PaletteColor {
        switch load {
        case ..<0.6: return green
        case ..<0.85: return yellow
        default: return red
        }
    }
}
