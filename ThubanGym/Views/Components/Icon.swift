import SwiftUI

/// The design canvas's line icons (24×24, 1.75 stroke, round caps), drawn natively from their SVG path data in the
/// current foreground style. Add an icon by adding a case and its `d` strings — never ship an image asset for one.
enum IconName: String, CaseIterable {
    /// Today tab (a dumbbell).
    case today
    /// Plan tab (two arrows chasing: the cycle).
    case plan
    /// Workouts tab (a bulleted list).
    case workouts
    /// Progress tab (axes with a rising line).
    case progress
    /// Settings (the Thuban drop).
    case settings
    case skip
    case swap
    case plus
    case check
    case close
    case trash
    case dragHandle
    case play
    case history
    case moon
    case file
    case download

    var paths: [String] {
        switch self {
        case .today: return ["M6.5 7.5v9", "M17.5 7.5v9", "M3.5 10v4", "M20.5 10v4", "M6.5 12h11"]
        case .plan: return ["M4.5 11V9.5a3 3 0 0 1 3-3h11", "M15.5 3.5l3 3-3 3", "M19.5 13v1.5a3 3 0 0 1-3 3h-11", "M8.5 20.5l-3-3 3-3"]
        case .workouts: return ["M8.5 6.5h11", "M8.5 12h11", "M8.5 17.5h11", "M4.5 6.5h.01", "M4.5 12h.01", "M4.5 17.5h.01"]
        case .progress: return ["M4 4v16h16", "M7.5 14.5l3.5-4 3 2.5 5-6"]
        case .settings: return ["M12 3.5s6 6.2 6 10.5a6 6 0 0 1-12 0c0-4.3 6-10.5 6-10.5z"]
        case .skip: return ["M5.5 6l8 6-8 6z", "M17.5 6v12"]
        case .swap: return ["M4.5 8.5h14", "M15 5l3.5 3.5L15 12", "M19.5 15.5h-14", "M9 12l-3.5 3.5L9 19"]
        case .plus: return ["M12 5v14", "M5 12h14"]
        case .check: return ["M5 12.5l4.5 4.5L19 7.5"]
        case .close: return ["M6.5 6.5l11 11", "M17.5 6.5l-11 11"]
        case .trash: return ["M4.5 7h15", "M9.5 7V4.5h5V7", "M6.5 7l1 12.5a1.5 1.5 0 0 0 1.5 1.5h6a1.5 1.5 0 0 0 1.5-1.5l1-12.5", "M10 11v6", "M14 11v6"]
        case .dragHandle: return ["M9 6h.01", "M15 6h.01", "M9 12h.01", "M15 12h.01", "M9 18h.01", "M15 18h.01"]
        case .play: return ["M7.5 5.5l11 6.5-11 6.5z"]
        case .history: return ["M3.5 12a8.5 8.5 0 1 0 2.5-6", "M3.5 4v4.5H8", "M12 7.5V12l3 2"]
        case .moon: return ["M19.5 14.5A8 8 0 0 1 9.5 4.5a8 8 0 1 0 10 10z"]
        case .file: return ["M14 3.5H6.5A1.5 1.5 0 0 0 5 5v14a1.5 1.5 0 0 0 1.5 1.5h11A1.5 1.5 0 0 0 19 19V8.5z", "M14 3.5v5h5", "M9 13h6", "M9 16.5h4"]
        case .download: return ["M12 4v11", "M7.5 10.5L12 15l4.5-4.5", "M4.5 16.5v2a1.5 1.5 0 0 0 1.5 1.5h12a1.5 1.5 0 0 0 1.5-1.5v-2"]
        }
    }

    /// Parsed once for every icon.
    fileprivate static let parsed: [IconName: CGPath] = Dictionary(uniqueKeysWithValues: allCases.map { icon in
        let path = CGMutablePath()
        for d in icon.paths { SVGPathData.append(d, to: path) }
        return (icon, path as CGPath)
    })

    fileprivate var cgPath: CGPath { IconName.parsed[self] ?? CGMutablePath() }
}

/// A line icon at `size` points, stroked in the current foreground style.
struct Icon: View {
    var name: IconName
    var size: CGFloat = 16

    init(_ name: IconName, size: CGFloat = 16) {
        self.name = name
        self.size = size
    }

    var body: some View {
        let path = name.cgPath
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 24
            let shape = Path(path).applying(CGAffineTransform(scaleX: scale, y: scale))
            context.stroke(shape, with: .foreground, style: StrokeStyle(lineWidth: 1.75 * scale, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Minimal stroke glyphs (chevrons, search, dot, reset …) kept from the Thuban family for small affordances.
struct Glyph: View {
    enum Kind { case plus, close, check, chevronDown, chevronRight, chevronLeft, search, dot, reset }
    var kind: Kind
    var size: CGFloat = 16

    init(_ kind: Kind, size: CGFloat = 16) {
        self.kind = kind
        self.size = size
    }

    var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width / 24
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            var path = Path()
            switch kind {
            case .plus:
                path.move(to: p(12, 5)); path.addLine(to: p(12, 19))
                path.move(to: p(5, 12)); path.addLine(to: p(19, 12))
            case .close:
                path.move(to: p(6, 6)); path.addLine(to: p(18, 18))
                path.move(to: p(18, 6)); path.addLine(to: p(6, 18))
            case .check:
                path.move(to: p(5, 12.5)); path.addLine(to: p(10, 17.5)); path.addLine(to: p(19, 7))
            case .chevronDown:
                path.move(to: p(6, 9.5)); path.addLine(to: p(12, 15.5)); path.addLine(to: p(18, 9.5))
            case .chevronRight:
                path.move(to: p(9.5, 6)); path.addLine(to: p(15.5, 12)); path.addLine(to: p(9.5, 18))
            case .chevronLeft:
                path.move(to: p(14.5, 6)); path.addLine(to: p(8.5, 12)); path.addLine(to: p(14.5, 18))
            case .search:
                path.addEllipse(in: CGRect(x: 4 * s, y: 4 * s, width: 11 * s, height: 11 * s))
                path.move(to: p(13.5, 13.5)); path.addLine(to: p(20, 20))
            case .dot:
                path.addEllipse(in: CGRect(x: 8 * s, y: 8 * s, width: 8 * s, height: 8 * s))
            case .reset:
                path.addArc(center: p(12, 12.5), radius: 7 * s, startAngle: .degrees(-150), endAngle: .degrees(120), clockwise: false)
                path.move(to: p(3.4, 4.5)); path.addLine(to: p(5.9, 9)); path.addLine(to: p(10.4, 7.2))
            }
            if kind == .dot {
                context.fill(path, with: .foreground)
            } else {
                context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 1.75 * s, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
