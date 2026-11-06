//
//  DesignKit.swift
//  Goals
//
//  The parts every screen is assembled from. Nothing here holds state or touches the model — a
//  card is a card whether it's showing a goal, a streak or a paywall bullet.
//

import SwiftUI

// MARK: - Screen scaffolding

extension View {
    /// The page ground, painted edge to edge behind the content.
    func screenGround() -> some View {
        background(Theme.ground.ignoresSafeArea())
    }

    /// A raised card: surface fill, hairline edge, the shared corner radius.
    func cardSurface(
        muted: Bool = false,
        radius: CGFloat = Theme.Radius.card,
        padding: CGFloat? = 14
    ) -> some View {
        modifier(CardSurface(muted: muted, radius: radius, padding: padding))
    }

    /// Keeps scrolling content clear of the iPad's floating tab bar. The system tab bar used
    /// everywhere else insets the content on its own.
    func tabBarClearance() -> some View {
        safeAreaPadding(.bottom, MainTabView.usesFloatingBar ? Theme.tabBarClearance : 0)
    }

    /// Caps a screen's content at a comfortable width and centers it, so it doesn't stretch edge to
    /// edge on a wide screen (an unfolded iPhone Duo, an iPad). Leaves a phone's layout alone.
    func readableWidth(_ width: CGFloat = Theme.readableWidth) -> some View {
        frame(maxWidth: width, alignment: .leading)
            .frame(maxWidth: .infinity)
    }

    /// For the handful of secondary sheets still built on a system `Form`/`List`: puts them on the
    /// app's own ground and surfaces instead of the stock grouped greys.
    func themedList() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Theme.ground.ignoresSafeArea())
            .toolbarBackground(Theme.ground, for: .navigationBar)
    }
}

/// Two columns side by side, for a screen with room for them. On a screen that folds (the iPhone
/// Duo's inner display) the gap between them lands on the fold when there's room for both columns
/// either side of it, so no card is bent across the hinge; anywhere else they split evenly.
struct HingeAwareColumns<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    /// `nil` until the first layout pass has measured the row.
    @State private var split: ColumnSplit?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            leading
                .frame(width: split?.leading, alignment: .top)
                .frame(maxWidth: split == nil ? .infinity : nil)
            Color.clear
                .frame(width: split?.gap ?? 0, height: 0)
            trailing
                .frame(width: split?.trailing, alignment: .top)
                .frame(maxWidth: split == nil ? .infinity : nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: ColumnSplit.self) { proxy in
            ColumnSplit(proxy)
        } action: { newSplit in
            split = newSplit
        }
    }
}

extension EnvironmentValues {
    /// True inside the detail side of a `ListDetailSplit`, where a detail screen is a pane next to
    /// its list rather than a page pushed over it - so it has nothing to go back from.
    @Entry var isDetailPane = false
}

/// A list with the selected item's detail beside it, for the unfolded iPhone Duo held sideways.
/// The detail gets its own navigation stack so its sheets and menus behave as they do when pushed,
/// and it can't hide the tab bar the way a pushed detail does.
struct ListDetailSplit<Primary: View, Detail: View>: View {
    @ViewBuilder var list: Primary
    @ViewBuilder var detail: Detail

    var body: some View {
        HingeAwareColumns {
            list
        } trailing: {
            NavigationStack {
                detail
                    .environment(\.isDetailPane, true)
            }
        }
    }
}

/// The highlight on the row whose detail is showing in the pane next to the list.
extension View {
    func selectedRowOutline(_ isSelected: Bool) -> some View {
        overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(Theme.accent, lineWidth: 1.5)
            }
        }
    }
}

private nonisolated struct ColumnSplit: Equatable, Sendable {
    var leading: CGFloat
    var gap: CGFloat
    var trailing: CGFloat

    /// Narrower than this and a goal or habit card starts truncating, so the columns would rather
    /// split evenly over the fold than squeeze one side.
    private static let minimumColumn: CGFloat = 250

    init(_ proxy: GeometryProxy) {
        let width = proxy.size.width
        if #available(iOS 27.1, *),
           let fold = proxy.reservedRegions(kind: .division)
               .map(\.frame)
               .first(where: { $0.height > $0.width && $0.minX > 0 && $0.maxX < width }),
           fold.minX >= Self.minimumColumn,
           width - fold.maxX >= Self.minimumColumn {
            leading = fold.minX
            gap = fold.width
            trailing = width - fold.maxX
        } else {
            leading = (width / 2).rounded(.down)
            gap = 0
            trailing = width - leading
        }
    }
}

private struct CardSurface: ViewModifier {
    let muted: Bool
    let radius: CGFloat
    let padding: CGFloat?

    func body(content: Content) -> some View {
        content
            .padding(padding ?? 0)
            .background(muted ? Theme.surfaceMuted : Theme.surface, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(muted ? Theme.hairlineSoft : Theme.hairline, lineWidth: 1)
            }
    }
}

/// The big title at the top of a root screen, with room for a subtitle and a trailing control.
struct ScreenTitle<Trailing: View>: View {
    let title: LocalizedStringKey
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    init(_ title: LocalizedStringKey, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(Theme.Typo.screenTitle)
                    .tracking(Theme.Typo.screenTitleTracking)
                    .foregroundStyle(Theme.text)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.textFaint)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, Theme.Space.screen)
        .padding(.top, 6)
    }
}

extension ScreenTitle where Trailing == EmptyView {
    init(_ title: LocalizedStringKey, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

/// The uppercase label that names a section.
struct SectionLabel: View {
    let key: LocalizedStringKey
    var trailing: AnyView?

    init(_ key: LocalizedStringKey) {
        self.key = key
        self.trailing = nil
    }

    init<T: View>(_ key: LocalizedStringKey, @ViewBuilder trailing: () -> T) {
        self.key = key
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack {
            Text(key)
                .font(Theme.Typo.sectionLabel)
                .tracking(Theme.Typo.sectionLabelTracking)
                .textCase(.uppercase)
                .foregroundStyle(Theme.textFaint)
            if let trailing {
                Spacer(minLength: 8)
                trailing
            }
        }
    }
}

/// A titled block: the section label, then whatever sits under it.
struct LabeledSection<Content: View>: View {
    let label: LocalizedStringKey?
    var badge: AnyView?
    @ViewBuilder var content: Content

    init(_ label: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.badge = nil
        self.content = content()
    }

    init<B: View>(_ label: LocalizedStringKey, @ViewBuilder badge: () -> B, @ViewBuilder content: () -> Content) {
        self.label = label
        self.badge = AnyView(badge())
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.label) {
            if let label {
                if let badge {
                    SectionLabel(label) { badge }
                } else {
                    SectionLabel(label)
                }
            }
            content
        }
    }
}

// MARK: - Rows inside a card

/// A card that holds a stack of rows. Rows separate themselves with `RowDivider`.
struct CardGroup<Content: View>: View {
    var muted = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
        .background(muted ? Theme.surfaceMuted : Theme.surface, in: .rect(cornerRadius: Theme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        }
    }
}

/// The hairline between two rows of a `CardGroup`.
struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.hairlineSoft)
            .frame(height: 1)
    }
}

/// Label on the left, value on the right — the workhorse of every settings-shaped card.
struct ValueRow<Value: View>: View {
    let label: LocalizedStringKey
    var icon: String?
    @ViewBuilder var value: Value

    var body: some View {
        HStack(spacing: 11) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 20)
                    .accessibilityHidden(true)
            }
            Text(label)
                .font(Theme.Typo.row)
                .foregroundStyle(Theme.textMuted)
            Spacer(minLength: 10)
            value
        }
        .padding(.vertical, 13)
    }
}

extension ValueRow where Value == Text {
    init(_ label: LocalizedStringKey, icon: String? = nil, value: String) {
        self.init(label: label, icon: icon) {
            Text(value)
                .font(Theme.Typo.row)
                .foregroundStyle(Theme.text)
        }
    }
}

/// A row that pushes something else: value, then a chevron.
struct DisclosureRow: View {
    let label: LocalizedStringKey
    var icon: String?
    var value: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.textMuted)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                }
                Text(label)
                    .font(Theme.Typo.row)
                    .foregroundStyle(Theme.textMuted)
                Spacer(minLength: 10)
                Text(value ?? "—")
                    .font(Theme.Typo.row)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textGhost)
                    // "Chevron right" says nothing the row's own title and value don't.
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 13)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// A row whose value is picked from a short list — the value itself is the menu button, so the
/// row reads the same as the disclosure rows around it.
struct MenuRow<Value: Hashable>: View {
    let label: LocalizedStringKey
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String

    var body: some View {
        HStack(spacing: 11) {
            Text(label)
                .font(Theme.Typo.row)
                .foregroundStyle(Theme.textMuted)
            Spacer(minLength: 10)
            Menu {
                Picker(label, selection: $selection) {
                    ForEach(options, id: \.self) { option in
                        Text(title(option)).tag(option)
                    }
                }
                .labelsHidden()
            } label: {
                HStack(spacing: 7) {
                    Text(title(selection))
                        .font(Theme.Typo.row)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textGhost)
                }
            }
        }
        .padding(.vertical, 13)
    }
}

/// A row whose value is typed rather than picked.
struct TextFieldRow: View {
    let label: LocalizedStringKey
    var placeholder: LocalizedStringKey?
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var suffix: String?

    var body: some View {
        HStack(spacing: 11) {
            Text(label)
                .font(Theme.Typo.row)
                .foregroundStyle(Theme.textMuted)
            Spacer(minLength: 10)
            TextField(placeholder ?? label, text: $text)
                .font(Theme.Typo.row)
                .foregroundStyle(Theme.text)
                .monospacedDigit()
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 130)
            if let suffix {
                Text(suffix)
                    .font(Theme.Typo.row)
                    .foregroundStyle(Theme.textFaint)
            }
        }
        .padding(.vertical, 13)
    }
}

/// A switch row. The switch itself keeps the system control — it is the one place iOS users read
/// state by muscle memory — recoloured to the accent.
struct SwitchRow: View {
    let label: LocalizedStringKey
    var icon: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 11) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 20)
                    .accessibilityHidden(true)
            }
            Toggle(label, isOn: $isOn)
                .font(Theme.Typo.row)
                .foregroundStyle(Theme.textMuted)
                .tint(Theme.accent)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Progress

/// A hand-drawn bar rather than `ProgressView`, which won't go below its platform minimum height.
struct ThinBar: View {
    let progress: Double
    var height: CGFloat = 3
    var color: Color = Theme.accent
    var trackColor: Color = Theme.track

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(trackColor)
                Capsule()
                    .fill(color)
                    .frame(width: geometry.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: height)
    }
}

/// The ring on a goal's detail screen: the fraction, with the percentage in the middle.
struct ProgressRing: View {
    let progress: Double
    var size: CGFloat = 96
    var lineWidth: CGFloat = 7

    private var clamped: Double { min(max(progress, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(clamped.formatted(.percent.precision(.fractionLength(0))))
                .font(.system(size: size * 0.2, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.text)
        }
        .frame(width: size, height: size)
        .animation(.snappy, value: clamped)
    }
}

// MARK: - Goal identity

/// A goal's emoji in its circle. The circle is neutral on purpose — the scheme is mono, so the
/// emoji is what tells two goals apart.
struct GoalBadge: View {
    let emoji: String?
    var size: CGFloat = 40
    var muted = false

    var body: some View {
        ZStack {
            Circle()
                .fill(muted ? Theme.hairlineSoft : Theme.control)
                .overlay {
                    Circle().strokeBorder(muted ? Color.clear : Theme.textGhost.opacity(0.5), lineWidth: 1)
                }
            if let emoji, !emoji.isEmpty {
                Text(emoji).font(.system(size: size * 0.47))
            } else {
                GoalsMark(size: size * 0.58, tone: .mono, color: Theme.accentText)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Chips and badges

/// A small pill: "Pro", "High", the streak count.
struct AccentPill: View {
    let text: String
    var systemImage: String?
    var filled = true

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 12))
            }
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(filled ? Theme.accentWell : Color.clear, in: .rect(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Theme.accentWellBorder, lineWidth: 1)
        }
        .foregroundStyle(Theme.accentWellText)
    }
}

/// The neutral twin of `AccentPill`, for the values that aren't worth the accent.
struct NeutralPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(Theme.textGhost, lineWidth: 1)
            }
            .foregroundStyle(Theme.textMuted)
    }
}

// MARK: - Segmented control

/// The app's own segmented control: an inset well with the selected segment tinted red. The system
/// one can't be recoloured this way, and it appears on nearly every screen.
struct SegmentStrip<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    var icon: ((Value) -> String)? = nil

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(.snappy(duration: 0.18)) { selection = option }
                } label: {
                    HStack(spacing: 5) {
                        if let icon {
                            Image(systemName: icon(option)).font(.system(size: 13))
                        }
                        Text(title(option))
                            .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(isSelected ? Theme.accentWell : Color.clear, in: .rect(cornerRadius: 8))
                    .foregroundStyle(isSelected ? Theme.accentWellText : Theme.textFaint)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(Theme.well, in: .rect(cornerRadius: Theme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.control)
                .strokeBorder(Theme.hairlineSoft, lineWidth: 1)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

// MARK: - Buttons

/// The one loud button on a screen: solid accent.
struct AccentButtonStyle: ButtonStyle {
    var height: CGFloat = 50

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typo.button)
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Theme.accent, in: .rect(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

/// The quieter one: accent outline, accent text.
struct AccentOutlineButtonStyle: ButtonStyle {
    var height: CGFloat = 46

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typo.buttonSmall)
            .foregroundStyle(Theme.accentText)
            .lineLimit(1)
            // Padding the label first means a `.fixedSize()` button — one that hugs its title
            // instead of filling the row — still keeps its text off the outline.
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(Theme.accent, lineWidth: 1)
            }
            .background(configuration.isPressed ? Theme.accent.opacity(0.12) : Color.clear, in: .rect(cornerRadius: 11))
    }
}

/// Neutral outline, for "Not now" and its friends.
struct NeutralOutlineButtonStyle: ButtonStyle {
    var height: CGFloat = 46

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typo.buttonSmall)
            .foregroundStyle(Theme.textStrong)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(Theme.textGhost, lineWidth: 1)
            }
            .background(configuration.isPressed ? Theme.text.opacity(0.06) : Color.clear, in: .rect(cornerRadius: 11))
    }
}

/// The square icon button in a screen's top-right corner.
struct IconButton: View {
    let systemImage: String
    var accent = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 38, height: 38)
                .foregroundStyle(accent ? Theme.accentText : Theme.textStrong)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.control)
                        .strokeBorder(accent ? Theme.accent : Theme.hairline, lineWidth: 1)
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Empty states

/// The app's own empty state: a ringed glyph, a line, and an explanation.
struct EmptyStateView<Action: View>: View {
    /// `nil` puts the app's own mark in the ring instead of a symbol — for the states that are
    /// about goals in general rather than one particular kind of nothing.
    var systemImage: String?
    let title: LocalizedStringKey
    var message: LocalizedStringKey?
    @ViewBuilder var action: Action

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.surfaceMuted)
                    .overlay { Circle().strokeBorder(Theme.hairline, lineWidth: 1) }
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.accentSpent)
                } else {
                    GoalsMark(size: 34, tone: .mono, color: Theme.accentSpent)
                }
            }
            .frame(width: 76, height: 76)

            Text(title)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)

            if let message {
                Text(message)
                    .font(Theme.Typo.body)
                    .foregroundStyle(Theme.textFaint)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            action
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 36)
    }
}

extension EmptyStateView where Action == EmptyView {
    init(systemImage: String? = nil, title: LocalizedStringKey, message: LocalizedStringKey? = nil) {
        self.init(systemImage: systemImage, title: title, message: message) { EmptyView() }
    }
}

// MARK: - Text helpers

extension View {
    /// Numbers that sit in a column or change in place shouldn't shuffle sideways as they do.
    func tabularNumbers() -> some View {
        monospacedDigit()
    }
}
