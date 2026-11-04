import CoreGraphics

enum Teardrop {
    /// A square with three fully rounded corners and one sharp one (the tip) at the origin. y down.
    static func path(size s: CGFloat, tipRadius r: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let big = s / 2
        path.move(to: CGPoint(x: r, y: 0))
        path.addArc(tangent1End: CGPoint(x: s, y: 0), tangent2End: CGPoint(x: s, y: s), radius: big)
        path.addArc(tangent1End: CGPoint(x: s, y: s), tangent2End: CGPoint(x: 0, y: s), radius: big)
        path.addArc(tangent1End: CGPoint(x: 0, y: s), tangent2End: CGPoint(x: 0, y: 0), radius: big)
        path.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: s, y: 0), radius: r)
        path.closeSubpath()
        return path
    }

    static func star(radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<8 {
            let r = i % 2 == 0 ? radius : radius * 0.4
            let a = CGFloat(i) * .pi / 4 - .pi / 2
            let p = CGPoint(x: cos(a) * r, y: sin(a) * r)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

