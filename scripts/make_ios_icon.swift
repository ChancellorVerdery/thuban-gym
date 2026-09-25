// Renders GymiOS/Resources/Assets.xcassets/AppIcon.appiconset: ONE 1024 × 1024 universal iOS icon — the app's mark
// (AppArt, Brass) on the dark plate, full bleed (iOS masks the corners itself). Same art and colours as
// make_app_icon.swift (the Mac icon). Usage: scripts/make_ios_icon.sh.
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
func hex(_ s: String) -> CGColor {
    var v: UInt64 = 0; Scanner(string: String(s.dropFirst())).scanHexInt64(&v)
    return CGColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}
let bg = hex("#090b11"), panel = hex("#0e1219"), accent = hex("#e0b15c"), signal = hex("#74d6c4")

let px = 1024
// Opaque RGB (no alpha channel: iOS app icons must not have one).
let cg = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                   space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
cg.translateBy(x: 0, y: CGFloat(px)); cg.scaleBy(x: 1, y: -1)
let full = CGRect(x: 0, y: 0, width: px, height: px)
cg.setFillColor(bg); cg.fill(full)
let mark = CGFloat(px) * 0.60
AppArt.draw(in: cg, rect: CGRect(x: full.midX - mark / 2, y: full.midY - mark / 2, width: mark, height: mark)) { role in
    switch role {
    case .accentStroke, .accentFill: return accent
    case .signalStroke, .signalFill: return signal
    case .panelFill: return panel
    case .bgFill: return bg
    }
}
let rep = NSBitmapImageRep(cgImage: cg.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("AppIcon-1024.png"))
let contents: [String: Any] = [
    "images": [["filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"]],
    "info": ["author": "xcode", "version": 1],
]
try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent("Contents.json"))
print("wrote the iOS icon to \(out.path)")
