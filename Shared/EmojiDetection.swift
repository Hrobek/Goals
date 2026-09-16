//
//  EmojiDetection.swift
//  Goals
//

import Foundation

extension Character {
    /// Whether this grapheme cluster is an emoji - shared by the emoji-only keyboard filter
    /// (`EmojiPickerSheet`) and the goal/habit title fields, which strip emoji out as you type: the
    /// dedicated emoji field is the one place for it, so a title stays plain text everywhere it's
    /// rendered small (widgets, notifications, the Today list).
    var isEmojiCharacter: Bool {
        guard let first = unicodeScalars.first else { return false }
        return first.properties.isEmojiPresentation
            || (first.properties.isEmoji && unicodeScalars.contains { $0.value == 0xFE0F })
            || unicodeScalars.contains { (0x1F1E6...0x1F1FF).contains($0.value) }
    }
}

extension String {
    /// This string with every emoji character removed.
    func strippingEmoji() -> String {
        filter { !$0.isEmojiCharacter }
    }
}
