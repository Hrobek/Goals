//
//  ColorPalette.swift
//  Goals
//

import SwiftUI

enum ColorPalette {
    static let hexValues: [String] = [
        "#FF6B6B", "#FF9F43", "#FECA57", "#1DD1A1",
        "#10AC84", "#54A0FF", "#5F27CD", "#EE5A9E", "#8395A7"
    ]

    static let defaultHex = hexValues[5]
}

extension Color {
    init(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized = sanitized.replacingOccurrences(of: "#", with: "")

        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)

        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255

        self.init(red: r, green: g, blue: b)
    }

    /// `#RRGGBB` for the color, clamped to sRGB — the form stores a hex string, so a colour
    /// picked from the wheel has to round-trip back through one.
    var hexString: String {
        let resolved = UIColor(self).cgColor.converted(
            to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil
        ) ?? UIColor(self).cgColor
        let comps = resolved.components ?? [0, 0, 0, 1]
        let r = Int((comps[safe: 0] ?? 0) * 255 + 0.5)
        let g = Int((comps[safe: 1] ?? 0) * 255 + 0.5)
        let b = Int((comps[safe: 2] ?? 0) * 255 + 0.5)
        return String(format: "#%02X%02X%02X", min(max(r, 0), 255), min(max(g, 0), 255), min(max(b, 0), 255))
    }
}

private extension Array where Element == CGFloat {
    subscript(safe index: Int) -> CGFloat? {
        indices.contains(index) ? self[index] : nil
    }
}
