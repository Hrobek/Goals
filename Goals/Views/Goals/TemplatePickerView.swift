//
//  TemplatePickerView.swift
//  Goals
//

import SwiftUI

/// A grid of ready-made goals and/or habits, so a new user (or anyone adding one) starts from
/// something concrete instead of a blank sheet. Every pick lands in the normal Add sheet, still
/// fully editable; the "Custom" card opens it empty.
struct TemplatePickerView: View {
    enum Mode {
        /// Goal templates only - the Goals tab's add flow.
        case goalsOnly
        /// Habit templates only - the Habits tab's add flow.
        case habitsOnly
        /// Both, in labelled sections - first-run onboarding.
        case both
    }

    enum Selection {
        case goal(GoalTemplate)
        case habit(HabitTemplate)
        case customGoal
        case customHabit
    }

    var mode: Mode = .goalsOnly
    /// Called with the choice. The caller dismisses this sheet and presents the matching Add sheet.
    let onPick: (Selection) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    private var showsGoals: Bool { mode != .habitsOnly }
    private var showsHabits: Bool { mode != .goalsOnly }
    private var isSectioned: Bool { mode == .both }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.section) {
                    if !isSectioned {
                        Text("templatePicker.subtitle")
                            .font(Theme.Typo.body)
                            .foregroundStyle(Theme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }

                    if showsGoals {
                        section(title: isSectioned ? "templatePicker.section.goals" : nil) {
                            ForEach(GoalTemplate.all) { template in
                                card(emoji: template.emoji, title: template.localizedTitle, subtitle: template.targetSummary) {
                                    onPick(.goal(template))
                                }
                            }
                            customCard(title: "templatePicker.custom.goal") { onPick(.customGoal) }
                        }
                    }

                    if showsHabits {
                        section(title: isSectioned ? "templatePicker.section.habits" : nil) {
                            ForEach(HabitTemplate.all) { template in
                                card(emoji: template.emoji, title: template.localizedTitle, subtitle: template.summary) {
                                    onPick(.habit(template))
                                }
                            }
                            customCard(title: "templatePicker.custom.habit") { onPick(.customHabit) }
                        }
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

    @ViewBuilder
    private func section<Cards: View>(title: LocalizedStringKey?, @ViewBuilder cards: () -> Cards) -> some View {
        if let title {
            LabeledSection(title) {
                LazyVGrid(columns: columns, spacing: 10) { cards() }
            }
        } else {
            LazyVGrid(columns: columns, spacing: 10) { cards() }
        }
    }

    private func card(emoji: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            cardBody(glyph: Text(emoji).font(.system(size: 25)), title: title, subtitle: subtitle)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(subtitle))
    }

    private func customCard(title: String.LocalizationValue, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            cardBody(
                glyph: Image(systemName: "plus").font(.system(size: 20, weight: .medium)).foregroundStyle(Theme.textMuted),
                title: String(localized: title, bundle: AppLanguage.currentBundle),
                subtitle: String(localized: "templatePicker.custom.subtitle", bundle: AppLanguage.currentBundle)
            )
        }
        .buttonStyle(.plain)
    }

    private func cardBody(glyph: some View, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            glyph
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
                    .lineLimit(1)
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
}

#Preview {
    TemplatePickerView(mode: .both) { _ in }
}
