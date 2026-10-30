import AppKit
import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Two-stop diagonal gradient, the building block of every ring, number and pill.
struct Shade {
    var from: UInt32
    var to: UInt32

    var gradient: LinearGradient {
        LinearGradient(colors: [Color(hex: from), Color(hex: to)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    var track: Color { Color(hex: to, opacity: 0.2) }
    var nsColor: NSColor {
        NSColor(red: CGFloat((to >> 16) & 0xFF) / 255, green: CGFloat((to >> 8) & 0xFF) / 255,
                blue: CGFloat(to & 0xFF) / 255, alpha: 1)
    }
}

/// One color family per provider; shades run deep → light (outer ring → inner ring).
struct SectionTheme {
    var shades: [Shade]
    var glassTint: Color

    func shade(_ i: Int) -> Shade { shades[min(i, shades.count - 1)] }

    static let autodl = SectionTheme(
        shades: [Shade(from: 0xB07CFF, to: 0x6E3BFF), Shade(from: 0xD3B4FF, to: 0x9B6BFF)],
        glassTint: Color(hex: 0x8B5CFF, opacity: 0.22))
    static let runpod = SectionTheme(
        shades: [Shade(from: 0xFF7AB8, to: 0xE5307A), Shade(from: 0xFFB3D6, to: 0xF0609E)],
        glassTint: Color(hex: 0xF0609E, opacity: 0.22))
    static let vast = SectionTheme(
        shades: [Shade(from: 0x3FD9C9, to: 0x0E9F96), Shade(from: 0x8FEADF, to: 0x2FC3B5)],
        glassTint: Color(hex: 0x2FC3B5, opacity: 0.22))
    static let other = SectionTheme(
        shades: [Shade(from: 0x8EDB5A, to: 0x1FAE6E), Shade(from: 0x4FD9A6, to: 0x0E9F76)],
        glassTint: Color(hex: 0x50D296, opacity: 0.22))
    static let accounts = SectionTheme(
        shades: [Shade(from: 0x4FC3FF, to: 0x3B6CFF), Shade(from: 0x6CC8F5, to: 0x2F80ED)],
        glassTint: Color(hex: 0x648CFF, opacity: 0.22))

    /// Amber, for idle machines and low balances.
    static let warn = Shade(from: 0xFFD27A, to: 0xFFA92E)
}
