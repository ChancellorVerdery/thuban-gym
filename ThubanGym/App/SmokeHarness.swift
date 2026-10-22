import AppKit
import Foundation
import ThubanGymCore
import os

/// Visual smoke test driven by `THUBAN_GYM_SMOKE=<output dir>` (see scripts/smoke.sh). The app is launched on a
/// temporary `THUBAN_GYM_HOME`, seeds `SampleData`, walks every section, the registered `SmokeScenes`, Today in dark
/// mode and every Settings pane, writes PNGs (`NN-name.png`) and exits (status 1 on failure). No network, no ssh.
@MainActor
enum SmokeHarness {
    static let variable = "THUBAN_GYM_SMOKE"
    private static let logger = Logger(subsystem: "org.thuban.gym", category: "smoke")
    /// The design canvas's artboard size.
    static let windowSize = NSSize(width: 1440, height: 900)

    static var outputDirectory: URL? {
        guard let raw = ProcessInfo.processInfo.environment[variable]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
    }

    static var isEnabled: Bool { outputDirectory != nil }

    static func startIfEnabled(app: AppModel) {
        guard let directory = outputDirectory else { return }
        Task { await run(app: app, directory: directory) }
    }

    private static func run(app: AppModel, directory: URL) async {
        var status: Int32 = 0
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let window = try await waitForWindow(timeout: 10) { $0.isVisible && $0.title != "Settings" && $0.contentView != nil }
            window.setContentSize(windowSize)
            app.setThemeSelection(ThemeSelection(mode: .light, schemeId: SchemePresets.defaultId, custom: nil))
            await sleep(0.8)

            // 1. Standard walk: every section.
            for (index, section) in AppSection.allCases.enumerated() {
                app.section = section
                await sleep(1.0)
                try capture(window, name: String(format: "%02d-%@", 10 + index, section.rawValue), in: directory)
            }

            // 2. Registered scenes.
            for (index, scene) in SmokeScenes.all.enumerated() {
                await scene.prepare(app)
                await sleep(scene.settle)
                let target: NSWindow
                switch scene.window {
                case .main: target = window
                case .sheet: target = try await waitFor(timeout: 5) { window.attachedSheet }
                case .settings: target = try await waitForWindow(timeout: 5) { $0.title == "Settings" && $0.isVisible }
                }
                try capture(target, name: String(format: "%02d-%@", 30 + index, scene.name), in: directory,
                            backdrop: scene.window == .settings ? NSColor(hex: app.theme.bg) : nil)
                await scene.cleanup(app)
                await sleep(0.5)
            }

            // 3. Dark mode (design: TodayDark).
            app.section = .today
            app.setThemeSelection(ThemeSelection(mode: .dark, schemeId: SchemePresets.defaultId, custom: nil))
            await sleep(1.0)
            try capture(window, name: "70-today-dark", in: directory)
            app.setThemeSelection(ThemeSelection(mode: .light, schemeId: SchemePresets.defaultId, custom: nil))
            await sleep(0.5)

            // 4. Settings, every pane.
            NSApp.activate(ignoringOtherApps: false)
            for (index, pane) in SettingsPane.allCases.enumerated() {
                app.openSettings(pane)
                let settings = try await waitForWindow(timeout: 5) { $0.title == "Settings" && $0.isVisible }
                if index == 0 { settings.setContentSize(NSSize(width: 1100, height: 760)) }
                await sleep(0.9)
                let slug = pane.rawValue.lowercased().map { $0.isLetter ? $0 : "-" }
                try capture(settings, name: String(format: "%02d-settings-%@", 80 + index, String(slug)), in: directory,
                            backdrop: NSColor(hex: app.theme.bg))
            }
        } catch {
            logger.error("smoke failed: \(error.localizedDescription, privacy: .public)")
            fputs("smoke: FAILED: \(error.localizedDescription)\n", stderr)
            status = 1
        }
        print("smoke: done")
        exit(status)
    }

    private static func sleep(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private static func waitForWindow(timeout: Double, _ predicate: (NSWindow) -> Bool) async throws -> NSWindow {
        try await waitFor(timeout: timeout) { NSApp.windows.first(where: predicate) }
    }

    private static func waitFor<T>(timeout: Double, _ probe: () -> T?) async throws -> T {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let value = probe() { return value }
            await sleep(0.1)
        }
        throw ThubanError.store("smoke: window did not appear within \(Int(timeout)) s")
    }

    /// Renders the window's content view (`cacheDisplay`) to `<name>.png` at retina scale (at least 2×, so a 1×
    /// display still gives README-quality pixels). No screen-recording permission needed. The Settings window has no
    /// title bar, and `cacheDisplay` leaves its pane's ScrollView transparent there, so for it `backdrop` (the theme
    /// background) is painted first and every visible scroll document is cached separately and drawn on top.
    private static func capture(_ window: NSWindow, name: String, in directory: URL, backdrop: NSColor? = nil) throws {
        guard let content = window.contentView else { throw ThubanError.store("smoke: window has no content view") }
        let bounds = content.bounds
        let scale = max(window.backingScaleFactor, 2)
        var rep = try bitmap(bounds.size, scale: scale, name: name)
        content.cacheDisplay(in: bounds, to: rep)
        if let backdrop {
            let composed = try bitmap(bounds.size, scale: scale, name: name)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: composed)
            backdrop.setFill()
            bounds.fill()
            rep.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
            for clip in clipViews(in: content) where !clip.isHiddenOrHasHiddenAncestor {
                guard let document = clip.documentView else { continue }
                let visible = clip.documentVisibleRect
                let part = try bitmap(visible.size, scale: scale, name: name)
                document.cacheDisplay(in: visible, to: part)
                var target = document.convert(visible, to: content)
                if content.isFlipped { target.origin.y = bounds.height - target.maxY }
                part.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
            }
            NSGraphicsContext.restoreGraphicsState()
            rep = composed
        }
        guard let png = rep.representation(using: .png, properties: [:]) else { throw ThubanError.store("smoke: PNG encoding failed for \(name)") }
        try png.write(to: directory.appendingPathComponent("\(name).png"))
        print("smoke: \(name)")
    }

    /// An RGBA bitmap of `size` points backed by `size × scale` pixels.
    private static func bitmap(_ size: NSSize, scale: CGFloat, name: String) throws -> NSBitmapImageRep {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int((size.width * scale).rounded()), pixelsHigh: Int((size.height * scale).rounded()),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { throw ThubanError.store("smoke: could not create a bitmap for \(name)") }
        rep.size = size
        return rep
    }

    private static func clipViews(in view: NSView) -> [NSClipView] {
        view.subviews.flatMap { subview in [subview as? NSClipView].compactMap { $0 } + clipViews(in: subview) }
    }
}
