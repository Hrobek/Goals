//
//  GoalsMark.swift
//  Goals
//
//  The app's mark: a crosshair whose reticle has been replaced by a check. Two of the four sight
//  marks stay red — aiming, not arrived — and the check sits where the cross would have met.
//
//  Drawn rather than shipped as an image so it takes the theme's colours, stays crisp at every
//  size, and can go monochrome where a tab bar or a widget needs one flat colour.
//

import SwiftUI

struct GoalsMark: View {
    enum Tone {
        /// Grey sight marks with two of them in the accent — the full mark.
        case duotone
        /// Everything in one colour, for tab bars and small glyphs where the red tick would just
        /// read as a rendering artefact.
        case mono
        /// The whole mark in the accent.
        case accent
    }

    var size: CGFloat = 24
    var tone: Tone = .duotone
    /// The check, and the sight marks in `.mono`.
    var color: Color = Theme.text
    /// The resting sight marks in `.duotone`.
    var restingColor: Color = Theme.textGhost

    /// The artwork is drawn on a 180×180 grid, the same one the design file uses, so the stroke
    /// weights carry across unchanged at any size.
    private var scale: CGFloat { size / 180 }

    private var sightColor: Color {
        switch tone {
        case .duotone: restingColor
        case .mono: color
        case .accent: Theme.accent
        }
    }

    private var checkColor: Color {
        tone == .accent ? Theme.accent : color
    }

    /// Mono has no red tick to carry the mark, so the strokes thicken slightly to keep the same
    /// visual weight next to SF Symbols.
    private var sightWidth: CGFloat { (tone == .duotone ? 10 : 14) * scale }
    private var checkWidth: CGFloat { (tone == .duotone ? 12 : 16) * scale }

    var body: some View {
        ZStack {
            SightMarks(liveOnly: false)
                .stroke(sightColor, style: StrokeStyle(lineWidth: sightWidth, lineCap: .round))
            if tone == .duotone {
                SightMarks(liveOnly: true)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: sightWidth, lineCap: .round))
            }
            CheckStroke()
                .stroke(checkColor, style: StrokeStyle(lineWidth: checkWidth, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// What identifies a goal at a glance: its emoji, or the app's own mark when it hasn't been given
/// one. The scheme is mono, so this is the only thing telling two goals apart in a widget row.
struct GoalIdentity: View {
    let emoji: String?
    var size: CGFloat = 14

    var body: some View {
        if let emoji, !emoji.isEmpty {
            Text(emoji).font(.system(size: size))
        } else {
            GoalsMark(size: size + 2, tone: .mono, color: Theme.accentText)
        }
    }
}

// MARK: - Geometry

private struct SightMarks: Shape {
    /// Just the two marks that take the accent (top and right), rather than all four.
    let liveOnly: Bool

    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 180
        let lines: [(CGPoint, CGPoint)] = liveOnly
            ? [(CGPoint(x: 90, y: 12), CGPoint(x: 90, y: 40)),
               (CGPoint(x: 140, y: 90), CGPoint(x: 168, y: 90))]
            : [(CGPoint(x: 90, y: 12), CGPoint(x: 90, y: 40)),
               (CGPoint(x: 90, y: 140), CGPoint(x: 90, y: 168)),
               (CGPoint(x: 12, y: 90), CGPoint(x: 40, y: 90)),
               (CGPoint(x: 140, y: 90), CGPoint(x: 168, y: 90))]

        var path = Path()
        for (start, end) in lines {
            path.move(to: CGPoint(x: start.x * unit, y: start.y * unit))
            path.addLine(to: CGPoint(x: end.x * unit, y: end.y * unit))
        }
        return path
    }
}

private struct CheckStroke: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 180
        var path = Path()
        path.move(to: CGPoint(x: 64 * unit, y: 92 * unit))
        path.addLine(to: CGPoint(x: 84 * unit, y: 112 * unit))
        path.addLine(to: CGPoint(x: 120 * unit, y: 68 * unit))
        return path
    }
}

#Preview {
    HStack(spacing: 24) {
        GoalsMark(size: 64)
        GoalsMark(size: 64, tone: .mono)
        GoalsMark(size: 64, tone: .accent)
    }
    .padding(40)
    .background(Theme.ground)
}
