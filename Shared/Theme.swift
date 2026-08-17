//
//  Theme.swift
//  Goals
//
//  The single source of truth for the app's look: the white / grey / black / red ramp, the
//  surfaces built from it, and the metrics every screen shares. Purely presentational — nothing
//  here knows anything about goals, check-ins or purchases.
//
//  The scheme is deliberately mono: a goal is identified by its emoji, never by a hue, so the one
//  saturated colour on screen always means "this is progress" or "this is the action".
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Ramp

/// The raw ladder both themes are cut from. Dark reads it from the black end, light from the white
/// end, which is why the two schemes below share so many stops.
enum Ramp {
    // Neutrals
    static let white = Color(hex: "#F2F2F3")
    static let grey100 = Color(hex: "#E2E2E5")
    static let grey200 = Color(hex: "#D6D6D9")
    static let grey300 = Color(hex: "#C9C9CC")
    static let grey400 = Color(hex: "#B0B0B4")
    static let grey500 = Color(hex: "#9A9A9E")
    static let grey600 = Color(hex: "#6E6E73")
    static let grey700 = Color(hex: "#4A4A4E")
    static let grey800 = Color(hex: "#2C2C2F")
    static let grey900 = Color(hex: "#1A1A1C")
    static let black = Color(hex: "#101011")

    // Reds
    static let red050 = Color(hex: "#FFE9E7")
    static let red100 = Color(hex: "#FFCFCA")
    static let red200 = Color(hex: "#FFADA4")
    static let red300 = Color(hex: "#FF7F72")
    static let red400 = Color(hex: "#E8483A")
    static let red500 = Color(hex: "#C03225")
    static let red600 = Color(hex: "#8F2419")
    static let red700 = Color(hex: "#5E1810")
    static let red800 = Color(hex: "#3A0F0A")
}

// MARK: - Theme

enum Theme {

    // MARK: Surfaces

    /// The page ground everything sits on.
    static let ground = adaptive(dark: "#101011", light: "#ECECEE")
    /// A raised card.
    static let surface = adaptive(dark: "#1A1A1C", light: "#F7F7F8")
    /// A card whose content is finished or out of play — one step back towards the ground.
    static let surfaceMuted = adaptive(dark: "#151516", light: "#F0F0F2")
    /// The inset well a segmented control or chip strip sits in.
    static let well = adaptive(dark: "#161617", light: "#E4E4E7")
    /// A filled control that isn't the primary action (quick-add chips, weekday pills).
    static let control = adaptive(dark: "#232325", light: "#E2E2E5")

    // MARK: Lines

    /// The hairline around a card.
    static let hairline = adaptive(dark: "#2C2C2F", light: "#DCDCDF")
    /// The lighter rule between rows inside a card.
    static let hairlineSoft = adaptive(dark: "#232325", light: "#E2E2E5")

    // MARK: Text

    static let text = adaptive(dark: "#F2F2F3", light: "#1A1A1C")
    /// Values and secondary emphasis — still readable, one step down.
    static let textStrong = adaptive(dark: "#C9C9CC", light: "#4A4A4E")
    /// Labels beside a value, subtitles.
    static let textMuted = adaptive(dark: "#9A9A9E", light: "#6E6E73")
    /// Captions, footnotes, the small print.
    static let textFaint = adaptive(dark: "#6E6E73", light: "#6E6E73")
    /// Decoration that shouldn't compete: empty chevrons, unfilled circles, grid labels.
    static let textGhost = adaptive(dark: "#4A4A4E", light: "#B0B0B4")

    // MARK: Accent

    /// The one saturated colour: fills, progress, the primary button.
    static let accent = adaptive(dark: "#E8483A", light: "#C03225")
    /// Accent text and icons small enough that the fill colour would go muddy.
    static let accentText = adaptive(dark: "#FFADA4", light: "#C03225")
    /// A slightly brighter accent for hairline-width marks (thin bars, small glyphs).
    static let accentBright = adaptive(dark: "#FF7F72", light: "#C03225")
    /// The tinted ground behind a selected segment, a streak pill, a Pro badge.
    static let accentWell = adaptive(dark: "#3A0F0A", light: "#FFE9E7")
    /// The border that goes with `accentWell`.
    static let accentWellBorder = adaptive(dark: "#8F2419", light: "#FFADA4")
    /// Text on `accentWell`.
    static let accentWellText = adaptive(dark: "#FFADA4", light: "#8F2419")
    /// Progress already banked on a finished goal — present, but no longer shouting.
    static let accentSpent = adaptive(dark: "#8F2419", light: "#8F2419")
    /// What sits on top of a solid accent fill.
    static let onAccent = Color(hex: "#F2F2F3")

    // MARK: Tracks

    /// The unfilled part of a progress bar.
    static let track = adaptive(dark: "#2C2C2F", light: "#E2E2E5")
    /// An activity square for a scheduled-but-not-done day.
    static let cellScheduled = adaptive(dark: "#2C2C2F", light: "#DCDCDF")
    /// An activity square for a day the goal isn't scheduled for.
    static let cellBlocked = adaptive(dark: "#151516", light: "#E9E9EC")

    // MARK: Metrics

    enum Radius {
        static let control: CGFloat = 11
        static let card: CGFloat = 14
        static let panel: CGFloat = 16
        static let sheet: CGFloat = 22
        static let pill: CGFloat = 99
    }

    enum Space {
        /// The gutter every screen's content sits inside.
        static let screen: CGFloat = 20
        /// Between stacked cards.
        static let card: CGFloat = 10
        /// Between a section label and the card under it.
        static let label: CGFloat = 10
        /// Between one section and the next.
        static let section: CGFloat = 22
    }

    /// How much room the floating tab bar needs at the bottom of a scrolling screen.
    static let tabBarClearance: CGFloat = 96

    // MARK: Shadows

    static let cardShadowRadius: CGFloat = 0

    // MARK: - Fonts
    //
    // Inter in the mock, SF here: the app ships no custom face and SF is the better neighbour to
    // iOS's own controls. The sizes, weights and tracking are carried across as-is — the mock's
    // 500 weight becomes `.medium`, its -0.03em tracking becomes a point value at each size.

    enum Typo {
        /// The big screen title ("Today", "Goals"). 32/medium, tight.
        static let screenTitle = Font.system(size: 32, weight: .medium)
        static let screenTitleTracking: CGFloat = -0.9

        /// A goal's own name on its detail screen.
        static let pageTitle = Font.system(size: 22, weight: .medium)
        static let pageTitleTracking: CGFloat = -0.4

        /// The headline number on a summary card.
        static let statLarge = Font.system(size: 34, weight: .medium).monospacedDigit()
        static let statMedium = Font.system(size: 30, weight: .medium).monospacedDigit()
        static let statSmall = Font.system(size: 20, weight: .medium).monospacedDigit()

        /// A card's title, a row's name.
        static let rowTitle = Font.system(size: 15.5, weight: .medium)
        /// A form row's label / value.
        static let row = Font.system(size: 15)
        static let rowEmphasis = Font.system(size: 15, weight: .medium)
        /// Body copy inside a card.
        static let body = Font.system(size: 13.5)
        /// The caption under a progress bar.
        static let caption = Font.system(size: 12)
        static let captionEmphasis = Font.system(size: 12, weight: .medium)
        /// Footnotes and the small print.
        static let footnote = Font.system(size: 11.5)
        /// The uppercase label above a section.
        static let sectionLabel = Font.system(size: 11, weight: .regular)
        static let sectionLabelTracking: CGFloat = 1.0
        /// Tab bar labels.
        static let tab = Font.system(size: 10, weight: .medium)
        /// Buttons.
        static let button = Font.system(size: 16, weight: .medium)
        static let buttonSmall = Font.system(size: 14, weight: .medium)
    }

    // MARK: - Plumbing

    /// A colour that reads the ramp from whichever end the current appearance calls for.
    private static func adaptive(dark: String, light: String) -> Color {
        #if canImport(UIKit)
        Color(UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
        #else
        Color(hex: light)
        #endif
    }
}
