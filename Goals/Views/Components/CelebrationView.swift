//
//  CelebrationView.swift
//  Goals
//
//  The one moment the app is allowed to make a fuss: a goal finished, or a streak reaching a
//  round number. A dimmed backdrop, a short burst of confetti, a card with the number in it —
//  then it gets out of the way on its own.
//

import Foundation
import SwiftUI

/// What just happened that's worth celebrating. `Equatable` so a `.onChange` can drive it and a
/// re-fire with the same value is a no-op.
enum GoalCelebration: Equatable {
    /// A goal reached its target (or its last milestone was ticked).
    /// `days` is how long it took from creation, `streak` the run going at that moment.
    case completed(days: Int?, streak: Int)
    /// A streak crossed one of the milestone lengths below.
    case streak(days: Int)

    /// The streak lengths that get their own celebration — dense enough early that the first wins
    /// land, sparse enough later that it never turns into nagging.
    static let streakMilestones = [7, 30, 100, 200, 365]

    /// The largest milestone the streak passed moving from `old` to `new`, or nil if it cleared none.
    static func streakMilestone(crossing old: Int, to new: Int) -> Int? {
        guard new > old else { return nil }
        return streakMilestones.last { $0 > old && $0 <= new }
    }

    /// Whether this is the "finished the goal" celebration rather than a streak milestone — the
    /// moment worth following up with a review prompt.
    var isCompletion: Bool {
        switch self {
        case .completed: true
        case .streak: false
        }
    }

    /// The celebration a check-in just earned, given the goal's completion and streak state
    /// captured *before* it ran. A finish beats a streak milestone when both land at once.
    static func afterCheckIn(goal: Goal, wasCompleted: Bool, previousStreak: Int, now: Date = .now) -> GoalCelebration? {
        let streak = StreakCalculator.currentStreak(for: goal)
        if !wasCompleted, goal.isCompleted {
            let days = Calendar.current.dateComponents(
                [.day], from: Calendar.current.startOfDay(for: goal.startDate), to: now
            ).day ?? 0
            return .completed(days: days, streak: streak)
        }
        if let milestone = streakMilestone(crossing: previousStreak, to: streak) {
            return .streak(days: milestone)
        }
        return nil
    }
}

struct GoalCelebrationView: View {
    let celebration: GoalCelebration
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    /// Long enough to read the number, short enough that it never feels like it's in the way.
    private static let autoDismissAfter: Duration = .seconds(3.8)

    var body: some View {
        ZStack {
            Color.black.opacity(appeared ? 0.5 : 0)
                .contentShape(.rect)
                .onTapGesture { onDismiss() }

            if !reduceMotion {
                ConfettiLayer(intensity: intensity)
                    .allowsHitTesting(false)
            }

            card
                .scaleEffect(appeared ? 1 : 0.86)
                .opacity(appeared ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .sensoryFeedback(.success, trigger: appeared)
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) { appeared = true }
            Task {
                try? await Task.sleep(for: Self.autoDismissAfter)
                onDismiss()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(spokenLabel))
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(named: Text("a11y.celebration.dismiss")) { onDismiss() }
    }

    private var card: some View {
        VStack(spacing: 14) {
            glyph
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(Theme.Typo.body)
                    .foregroundStyle(Theme.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 28)
        .frame(maxWidth: 300)
        .background(Theme.surface, in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
        .padding(.horizontal, 40)
    }

    @ViewBuilder
    private var glyph: some View {
        switch celebration {
        case .completed:
            GoalsMark(size: 44, tone: .mono, color: Theme.accent)
        case .streak:
            Image(systemName: "flame.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accent)
        }
    }

    private var intensity: Double {
        switch celebration {
        case .completed: 1
        case .streak(let days): days >= 100 ? 0.9 : 0.6
        }
    }

    // MARK: - Copy

    private var daysPhrase: (Int) -> String {
        { GoalUnit.days.countPhrase($0) ?? "\($0)" }
    }

    private var title: String {
        switch celebration {
        case .completed:
            return String(localized: "celebration.completed.title", defaultValue: "Done!", bundle: AppLanguage.currentBundle)
        case .streak(let days):
            return String(localized: "celebration.streak.title \(daysPhrase(days))", bundle: AppLanguage.currentBundle)
        }
    }

    private var detail: String? {
        switch celebration {
        case .completed(let days, let streak):
            var parts: [String] = []
            if let days, days > 0 {
                parts.append(String(localized: "celebration.completed.detail \(daysPhrase(days))", bundle: AppLanguage.currentBundle))
            }
            if streak > 1 {
                parts.append(String(localized: "celebration.streak.chip \(daysPhrase(streak))", bundle: AppLanguage.currentBundle))
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .streak(let days):
            guard let next = GoalCelebration.streakMilestones.first(where: { $0 > days }) else {
                // Past the last milestone the app celebrates — nothing left to count down to.
                return String(localized: "celebration.streak.max", defaultValue: "Keep it going.", bundle: AppLanguage.currentBundle)
            }
            return String(localized: "celebration.streak.remaining \(daysPhrase(next - days))", bundle: AppLanguage.currentBundle)
        }
    }

    private var spokenLabel: String {
        [title, detail].compactMap { $0 }.joined(separator: ". ")
    }
}

// MARK: - Confetti

/// A one-off confetti burst. Purely time-driven off `TimelineView`, so there's no animation state
/// to keep in sync; once the particles have fallen past their lifetime the canvas draws nothing.
private struct ConfettiLayer: View {
    private static let palette: [Color] = [
        Color(red: 0.95, green: 0.30, blue: 0.25),
        Color(red: 1.00, green: 0.72, blue: 0.20),
        Color(red: 0.40, green: 0.78, blue: 0.42),
        Color(red: 0.36, green: 0.60, blue: 0.96),
        Color(red: 0.80, green: 0.45, blue: 0.92),
        Color(red: 0.20, green: 0.80, blue: 0.80)
    ]
    private static let lifetime: Double = 2.8
    private static let gravity: Double = 1200

    /// Built once at init so there's no state to seed on appear.
    private let pieces: [Piece]
    @State private var start = Date()

    /// `intensity` 0…1 scales how many pieces are thrown.
    init(intensity: Double) {
        let count = Int(70 * max(0.25, min(1, intensity)))
        pieces = (0..<count).map { _ in Piece.random(palette: Self.palette) }
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSince(start)
                Canvas { context, _ in
                    guard t < Self.lifetime + 0.3 else { return }
                    let size = geo.size
                    for piece in pieces {
                        let tt = t - piece.delay
                        guard tt > 0, tt < Self.lifetime else { continue }

                        let x = size.width * piece.originX + piece.vx * tt
                        let y = size.height * 0.32 + piece.vy * tt + 0.5 * Self.gravity * tt * tt
                        guard y < size.height + 40 else { continue }

                        let fade = 1 - max(0, (tt - 1.5) / 1.3)
                        var layer = context
                        layer.translateBy(x: x, y: y)
                        layer.rotate(by: .radians(piece.spin * tt))
                        layer.opacity = max(0, min(1, fade))

                        let rect = CGRect(x: -piece.size / 2, y: -piece.size / 2,
                                          width: piece.size, height: piece.size * (piece.isRect ? 1.6 : 1))
                        let path: Path = piece.isRect
                            ? Path(roundedRect: rect, cornerRadius: 1)
                            : Path(ellipseIn: rect)
                        layer.fill(path, with: .color(piece.color))
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { start = Date() }
    }

    private struct Piece {
        let originX: CGFloat
        let vx: Double
        let vy: Double
        let spin: Double
        let size: CGFloat
        let color: Color
        let isRect: Bool
        let delay: Double

        static func random(palette: [Color]) -> Piece {
            let angle = Double.random(in: (.pi * 0.20)...(.pi * 0.80)) // fan upward
            let speed = Double.random(in: 380...820)
            return Piece(
                originX: .random(in: 0.20...0.80),
                vx: cos(angle) * speed * (Bool.random() ? 1 : -1),
                vy: -sin(angle) * speed,
                spin: Double.random(in: -7...7),
                size: .random(in: 6...11),
                color: palette.randomElement() ?? .red,
                isRect: Bool.random(),
                delay: Double.random(in: 0...0.30)
            )
        }
    }
}

#Preview("Completed") {
    GoalCelebrationView(celebration: .completed(days: 47, streak: 12)) {}
        .screenGround()
}

#Preview("Streak") {
    GoalCelebrationView(celebration: .streak(days: 30)) {}
        .screenGround()
}
