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
}
