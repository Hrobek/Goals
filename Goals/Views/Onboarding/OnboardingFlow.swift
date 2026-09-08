//
//  OnboardingFlow.swift
//  Goals
//

import SwiftUI

/// First launch, end to end: the welcome screen, then a picker of ready-made goals and habits.
/// Hands the caller whatever was chosen (or `nil` when the user skips), which `RootView` turns
/// into the matching Add sheet.
struct OnboardingFlow: View {
    let onFinish: (TemplatePickerView.Selection?) -> Void

    @State private var isShowingPicker = false

    var body: some View {
        FirstRunWelcomeView(
            onContinue: { isShowingPicker = true },
            onSkip: { onFinish(nil) }
        )
        .sheet(isPresented: $isShowingPicker) {
            TemplatePickerView(mode: .both) { selection in
                isShowingPicker = false
                onFinish(selection)
            }
        }
    }
}

#Preview {
    OnboardingFlow { _ in }
}
