//
//  TemplatePickerView.swift
//  Goals
//

import SwiftUI

/// The step between the first-run welcome and the Add Goal form: a grid of ready-made goals so a
/// new user starts from something concrete instead of a blank sheet. Every pick lands in the
/// normal Add Goal sheet, still fully editable; "Custom" opens it empty.
struct TemplatePickerView: View {
    /// Called with the chosen template, or `nil` for "start from scratch". The caller is
    /// responsible for dismissing this sheet and presenting Add Goal.
    let onPick: (GoalTemplate?) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("templatePicker.subtitle")
                        .font(Theme.Typo.body)
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(GoalTemplate.all) { template in
                            card(
                                emoji: template.emoji,
                                title: template.localizedTitle,
                                subtitle: template.scheduleSummary
                            ) { onPick(template) }
                        }

                        card(
                            emoji: "✏️",
                            title: String(localized: "templatePicker.custom", bundle: AppLanguage.currentBundle),
                            subtitle: String(localized: "templatePicker.custom.subtitle", bundle: AppLanguage.currentBundle)
                        ) { onPick(nil) }
                    }
                }
                .padding(.horizontal, Theme.Space.screen)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .screenGround()
            .navigationTitle(Text("templatePicker.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.ground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                        .foregroundStyle(Theme.textMuted)
                }
            }
        }
    }

    private func card(
        emoji: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Text(emoji)
                    .font(.system(size: 25))
                    .frame(width: 44, height: 44)
                    .background(Theme.control, in: .circle)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Theme.Typo.rowTitle)
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(Theme.Typo.footnote)
                        .foregroundStyle(Theme.textFaint)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 134, alignment: .topLeading)
            .padding(14)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(subtitle))
    }
}

#Preview {
    TemplatePickerView { _ in }
}
