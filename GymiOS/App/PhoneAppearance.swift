import SwiftUI
import ThubanGymCore
import UIKit

/// UIKit bar styling SwiftUI cannot express: the serif large title, bar hairlines and the unselected tab colour.
/// Colours are dynamic providers over the CURRENT theme (`update(_:)` is called whenever it changes), so light / dark
/// switches re-resolve by themselves; a scheme change re-applies them to the bars on screen (`refreshExistingBars`).
enum PhoneAppearance {
    private static var light = ThemeResolver.resolve(.default, systemIsDark: false)
    private static var dark = ThemeResolver.resolve(.default, systemIsDark: true)

    static func update(_ selection: ThemeSelection) {
        var l = selection; l.mode = .light
        var d = selection; d.mode = .dark
        light = ThemeResolver.resolve(l, systemIsDark: false)
        dark = ThemeResolver.resolve(d, systemIsDark: true)
    }

    private static func token(_ pick: @escaping (ResolvedTheme) -> String) -> UIColor {
        UIColor { traits in UIColor(hex: pick(traits.userInterfaceStyle == .dark ? dark : light)) }
    }

    /// Bars that already exist keep the colours they resolved; after a scheme change give them fresh appearances.
    @MainActor
    static func refreshExistingBars() {
        configure()
        let nav = UINavigationBar.appearance()
        let tab = UITabBar.appearance()
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                visit(window) { view in
                    if let bar = view as? UINavigationBar {
                        bar.standardAppearance = nav.standardAppearance
                        bar.compactAppearance = nav.compactAppearance
                        bar.scrollEdgeAppearance = nav.scrollEdgeAppearance
                    } else if let bar = view as? UITabBar {
                        bar.standardAppearance = tab.standardAppearance
                        bar.scrollEdgeAppearance = tab.scrollEdgeAppearance
                    }
                }
            }
        }
    }

    private static func visit(_ view: UIView, _ body: (UIView) -> Void) {
        body(view)
        for sub in view.subviews { visit(sub, body) }
    }

    static func configure() {
        let ink = token(\.ink)
        let line = token(\.line)
        let serifLarge = UIFont.systemFont(ofSize: 34, weight: .semibold).fontDescriptor.withDesign(.serif)
            .map { UIFont(descriptor: $0, size: 34) } ?? .systemFont(ofSize: 34, weight: .semibold)
        let largeTitle = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: serifLarge)
        let title = UIFontMetrics(forTextStyle: .headline).scaledFont(for: .systemFont(ofSize: 17, weight: .semibold))

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = token(\.bg)
        nav.shadowColor = line
        nav.largeTitleTextAttributes = [.font: largeTitle, .foregroundColor: ink, .kern: -0.3]
        nav.titleTextAttributes = [.font: title, .foregroundColor: ink]
        let edge = nav.copy()
        edge.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = edge

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = token(\.panel)
        tab.shadowColor = line
        let item = UITabBarItemAppearance()
        item.normal.iconColor = token(\.inkFaint)
        item.normal.titleTextAttributes = [.foregroundColor: token(\.inkFaint), .font: UIFont.systemFont(ofSize: 11, weight: .medium)]
        item.selected.titleTextAttributes = [.font: UIFont.systemFont(ofSize: 11, weight: .medium)]
        tab.stackedLayoutAppearance = item
        tab.inlineLayoutAppearance = item
        tab.compactInlineLayoutAppearance = item
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}

/// Tab bar images drawn from the design's line icons (templates, so the tab tint colours them).
enum TabIcon {
    private static var cache: [IconName: UIImage] = [:]

    static func image(_ name: IconName) -> UIImage {
        if let cached = cache[name] { return cached }
        let size = CGSize(width: 26, height: 26)
        let image = UIGraphicsImageRenderer(size: size).image { renderer in
            let cg = renderer.cgContext
            if name == .kettlebell {
                // The app mark itself: kettlebell strokes and the filled star.
                AppArt.draw(in: cg, rect: CGRect(origin: .zero, size: size)) { role in
                    switch role {
                    case .panelFill, .bgFill: return nil
                    default: return UIColor.black.cgColor
                    }
                }
            } else {
                let scale = size.width / 24
                var transform = CGAffineTransform(scaleX: scale, y: scale)
                if let path = name.cgPath.copy(using: &transform) {
                    cg.addPath(path)
                    cg.setStrokeColor(UIColor.black.cgColor)
                    cg.setLineWidth(1.75 * scale)
                    cg.setLineCap(.round)
                    cg.setLineJoin(.round)
                    cg.strokePath()
                }
            }
        }.withRenderingMode(.alwaysTemplate)
        cache[name] = image
        return image
    }
}
