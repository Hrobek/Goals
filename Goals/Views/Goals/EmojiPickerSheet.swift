//
//  EmojiPickerSheet.swift
//  Goals
//

import SwiftUI
import UIKit

/// Instead of a custom grid, the picker shows the system emoji keyboard — the same one the user
/// already knows, with skin tones, search, recents and every new emoji the OS supports.
struct EmojiPickerSheet: View {
    @Binding var selection: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Theme.control)
                        .overlay { Circle().strokeBorder(Theme.hairline, lineWidth: 1) }
                        .frame(width: 96, height: 96)
                    if let selection {
                        Text(selection).font(.system(size: 56))
                    } else {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                Text("emoji.custom.placeholder")
                    .font(Theme.Typo.body)
                    .foregroundStyle(Theme.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                EmojiKeyboardField { emoji in
                    selection = emoji
                    dismiss()
                }
                .frame(height: 1)
                .opacity(0)
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 40)
            .screenGround()
            .toolbarBackground(Theme.ground, for: .navigationBar)
            .navigationTitle("goal.field.emoji")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                if selection != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("action.clear") {
                            selection = nil
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

/// A hidden, always-first-responder text field wired up to the emoji input mode. The moment the
/// user taps an emoji the field reports it and swallows the insertion, so nothing is actually kept
/// in the field — the sheet just needs the keystroke.
private struct EmojiKeyboardField: UIViewRepresentable {
    var onPick: (String) -> Void

    func makeUIView(context: Context) -> EmojiOnlyTextField {
        let field = EmojiOnlyTextField(frame: .zero)
        field.delegate = context.coordinator
        field.tintColor = .clear
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.smartInsertDeleteType = .no
        return field
    }

    func updateUIView(_ uiView: EmojiOnlyTextField, context: Context) {
        if !uiView.isFirstResponder {
            DispatchQueue.main.async { uiView.becomeFirstResponder() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        let onPick: (String) -> Void

        init(onPick: @escaping (String) -> Void) { self.onPick = onPick }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            guard let emoji = string.last(where: { $0.isEmojiCharacter }) else { return false }
            onPick(String(emoji))
            return false
        }
    }
}

/// The emoji keyboard is just another `UITextInputMode`; there's no `UIKeyboardType` for it. Naming
/// a unique input context stops iOS from restoring the last keyboard the user was on, and
/// `textInputMode` then picks the emoji mode explicitly.
private final class EmojiOnlyTextField: UITextField {
    override var textInputContextIdentifier: String? { "goals.emoji.only" }

    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" }
            ?? super.textInputMode
    }
}

private extension Character {
    /// Whether this grapheme cluster is an emoji — used to filter out anything the emoji keyboard
    /// might still insert (a plain space, for example, if the user long-presses to switch languages).
    var isEmojiCharacter: Bool {
        guard let first = unicodeScalars.first else { return false }
        return first.properties.isEmojiPresentation
            || (first.properties.isEmoji && unicodeScalars.contains { $0.value == 0xFE0F })
            || unicodeScalars.contains { (0x1F1E6...0x1F1FF).contains($0.value) }
    }
}

#Preview {
    EmojiPickerSheet(selection: .constant("🎯"))
}
