//
//  ThemedSecureField.swift
//  Goals
//

import SwiftUI
import UIKit

/// A password field of the app's own, for two reasons SwiftUI's `SecureField` can't be talked out
/// of: it hands the last character typed to SwiftUI to draw, which puts one white bullet on the end
/// of a row of UIKit's near-black ones, and inside a form whose rows come and go it will happily
/// recycle a plain text field into a password row — which is how a confirmation field ends up
/// showing the password in the clear.
///
/// Owning the `UITextField` settles both: every bullet is drawn by UIKit in one colour, and the
/// field is secure from the moment it's made. The text colour deliberately matches what AutoFill
/// draws with, so a filled-in password and a typed one look the same.
struct ThemedSecureField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var textContentType: UITextContentType?
    /// Called when the keyboard's return key is tapped, so the field can submit the form.
    var onSubmit: () -> Void = {}

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.isSecureTextEntry = true
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.returnKeyType = .go
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.textColor = .black
        field.tintColor = UIColor(Theme.accent)
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged), for: .editingChanged)
        // Without this the field insists on its full intrinsic width and pushes the form's row out.
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        // Compare against the last value *we* reported up, not against `field.text` itself: AutoFill
        // can still be inserting characters into `field.text` when this runs, and a SwiftUI render
        // carrying an older `text` snapshot would otherwise stomp on those in-flight characters.
        if context.coordinator.lastReportedText != text {
            field.text = text
            context.coordinator.lastReportedText = text
        }
        field.textContentType = textContentType
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor(Theme.textGhost).resolvedColor(with: field.traitCollection)]
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: ThemedSecureField
        /// The last text this field reported up to SwiftUI, so `updateUIView` can tell an echo of its
        /// own edit apart from a genuinely external change (e.g. the fields being reset on mode switch).
        var lastReportedText: String

        init(parent: ThemedSecureField) {
            self.parent = parent
            self.lastReportedText = parent.text
        }

        /// Fires for typing and for an AutoFill insertion alike, which is what keeps the binding in
        /// step with a generated password.
        @objc func editingChanged(_ field: UITextField) {
            let value = field.text ?? ""
            lastReportedText = value
            if parent.text != value { parent.text = value }
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            field.resignFirstResponder()
            parent.onSubmit()
            return true
        }
    }
}
