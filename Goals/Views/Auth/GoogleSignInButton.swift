//
//  GoogleSignInButton.swift
//  Goals
//

import SwiftUI

/// Sign-in button following Google's identity branding guidelines: their own four-colour "G",
/// unmodified, on the sanctioned light/dark surfaces with the required contrast, and one of the
/// approved labels.
struct GoogleSignInButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let action: () -> Void

    private var background: Color {
        colorScheme == .dark ? Color(red: 0.075, green: 0.075, blue: 0.078) : .white
    }

    private var border: Color {
        colorScheme == .dark ? Color(red: 0.557, green: 0.569, blue: 0.561) : Color(red: 0.455, green: 0.463, blue: 0.459)
    }

    private var label: Color {
        colorScheme == .dark ? Color(red: 0.890, green: 0.890, blue: 0.890) : Color(red: 0.122, green: 0.122, blue: 0.122)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                GoogleLogo()
                    .frame(width: 20, height: 20)
                Text("auth.continueWithGoogle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(label)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(background, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

/// The Google "G", drawn from the official artwork's paths. Colours and proportions are fixed —
/// the guidelines don't allow recolouring or distorting the mark.
private struct GoogleLogo: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 48
            let transform = CGAffineTransform(scaleX: scale, y: scale)

            for segment in Self.segments {
                var path = segment.path
                path = path.applying(transform)
                context.fill(path, with: .color(segment.color))
            }
        }
        .accessibilityHidden(true)
    }

    private struct Segment {
        let path: Path
        let color: Color
    }

    private static var segments: [Segment] {
        [
            Segment(path: blue, color: Color(red: 0.259, green: 0.522, blue: 0.957)),
            Segment(path: green, color: Color(red: 0.204, green: 0.659, blue: 0.325)),
            Segment(path: yellow, color: Color(red: 0.984, green: 0.737, blue: 0.020)),
            Segment(path: red, color: Color(red: 0.918, green: 0.263, blue: 0.208))
        ]
    }

    private static var blue: Path {
        var path = Path()
        path.move(to: CGPoint(x: 45.12, y: 24.5))
        path.addCurve(to: CGPoint(x: 44.72, y: 20), control1: CGPoint(x: 45.12, y: 22.94), control2: CGPoint(x: 44.98, y: 21.44))
        path.addLine(to: CGPoint(x: 24, y: 20))
        path.addLine(to: CGPoint(x: 24, y: 28.51))
        path.addLine(to: CGPoint(x: 35.84, y: 28.51))
        path.addCurve(to: CGPoint(x: 31.45, y: 35.15), control1: CGPoint(x: 35.33, y: 31.26), control2: CGPoint(x: 33.78, y: 33.59))
        path.addLine(to: CGPoint(x: 31.45, y: 40.67))
        path.addLine(to: CGPoint(x: 38.56, y: 40.67))
        path.addCurve(to: CGPoint(x: 45.12, y: 24.5), control1: CGPoint(x: 42.72, y: 36.84), control2: CGPoint(x: 45.12, y: 31.2))
        path.closeSubpath()
        return path
    }

    private static var green: Path {
        var path = Path()
        path.move(to: CGPoint(x: 24, y: 46))
        path.addCurve(to: CGPoint(x: 38.56, y: 40.67), control1: CGPoint(x: 29.94, y: 46), control2: CGPoint(x: 34.92, y: 44.03))
        path.addLine(to: CGPoint(x: 31.45, y: 35.15))
        path.addCurve(to: CGPoint(x: 24, y: 37.25), control1: CGPoint(x: 29.48, y: 36.47), control2: CGPoint(x: 26.96, y: 37.25))
        path.addCurve(to: CGPoint(x: 11.69, y: 28.18), control1: CGPoint(x: 18.27, y: 37.25), control2: CGPoint(x: 13.42, y: 33.38))
        path.addLine(to: CGPoint(x: 4.34, y: 28.18))
        path.addLine(to: CGPoint(x: 4.34, y: 33.88))
        path.addCurve(to: CGPoint(x: 24, y: 46), control1: CGPoint(x: 7.96, y: 41.07), control2: CGPoint(x: 15.4, y: 46))
        path.closeSubpath()
        return path
    }

    private static var yellow: Path {
        var path = Path()
        path.move(to: CGPoint(x: 11.69, y: 28.18))
        path.addCurve(to: CGPoint(x: 11, y: 24), control1: CGPoint(x: 11.25, y: 26.86), control2: CGPoint(x: 11, y: 25.45))
        path.addCurve(to: CGPoint(x: 11.69, y: 19.82), control1: CGPoint(x: 11, y: 22.55), control2: CGPoint(x: 11.25, y: 21.14))
        path.addLine(to: CGPoint(x: 11.69, y: 14.12))
        path.addLine(to: CGPoint(x: 4.34, y: 14.12))
        path.addCurve(to: CGPoint(x: 2, y: 24), control1: CGPoint(x: 2.85, y: 17.09), control2: CGPoint(x: 2, y: 20.45))
        path.addCurve(to: CGPoint(x: 4.34, y: 33.88), control1: CGPoint(x: 2, y: 27.55), control2: CGPoint(x: 2.85, y: 30.91))
        path.addLine(to: CGPoint(x: 11.69, y: 28.18))
        path.closeSubpath()
        return path
    }

    private static var red: Path {
        var path = Path()
        path.move(to: CGPoint(x: 24, y: 10.75))
        path.addCurve(to: CGPoint(x: 32.41, y: 14.04), control1: CGPoint(x: 27.23, y: 10.75), control2: CGPoint(x: 30.13, y: 11.86))
        path.addLine(to: CGPoint(x: 38.72, y: 7.73))
        path.addCurve(to: CGPoint(x: 24, y: 2), control1: CGPoint(x: 34.91, y: 4.18), control2: CGPoint(x: 29.93, y: 2))
        path.addCurve(to: CGPoint(x: 4.34, y: 14.12), control1: CGPoint(x: 15.4, y: 2), control2: CGPoint(x: 7.96, y: 6.93))
        path.addLine(to: CGPoint(x: 11.69, y: 19.82))
        path.addCurve(to: CGPoint(x: 24, y: 10.75), control1: CGPoint(x: 13.42, y: 14.62), control2: CGPoint(x: 18.27, y: 10.75))
        path.closeSubpath()
        return path
    }
}

#Preview {
    VStack(spacing: 16) {
        GoogleSignInButton {}
        GoogleSignInButton {}
            .environment(\.colorScheme, .dark)
    }
    .padding()
}
