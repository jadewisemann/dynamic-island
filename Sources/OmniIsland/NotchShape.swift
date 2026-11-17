import SwiftUI

/// The island outline: flat top edge flush with the screen, small concave
/// "shoulders" at the top corners (like the hardware notch), and rounded
/// bottom corners. Both radii are animatable so the shape morphs smoothly
/// between the hidden notch and the expanded island.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let top = max(0, min(topRadius, w / 4, h / 2))
        let bottom = max(0, min(bottomRadius, (w - 2 * top) / 2, h - top))

        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Left shoulder: curves inward from the top edge.
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control: CGPoint(x: rect.minX + top, y: rect.minY)
        )
        // Left side down to the bottom-left corner.
        p.addLine(to: CGPoint(x: rect.minX + top, y: rect.minY + h - bottom))
        p.addArc(
            tangent1End: CGPoint(x: rect.minX + top, y: rect.minY + h),
            tangent2End: CGPoint(x: rect.minX + top + bottom, y: rect.minY + h),
            radius: bottom
        )
        // Bottom edge.
        p.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.minY + h))
        p.addArc(
            tangent1End: CGPoint(x: rect.maxX - top, y: rect.minY + h),
            tangent2End: CGPoint(x: rect.maxX - top, y: rect.minY + h - bottom),
            radius: bottom
        )
        // Right side up to the right shoulder.
        p.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - top, y: rect.minY)
        )
        p.closeSubpath()
        return p
    }
}

extension Color {
    /// Accepts #RGB, #RRGGBB and #RRGGBBAA. Falls back to `fallback`.
    init(hex: String, fallback: Color = .black) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else {
            self = fallback
            return
        }
        let r, g, b, a: Double
        if s.count == 8 {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        } else {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
