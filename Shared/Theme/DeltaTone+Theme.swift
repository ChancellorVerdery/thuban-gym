import SwiftUI
import ThubanGymCore

extension ResolvedTheme {
    /// Text colour for a change: `pos` for a gain, `neg` for a loss, dim ink when it rounds to zero.
    func toneTextColor(_ tone: DeltaTone) -> Color {
        switch tone {
        case .pos: return posTextColor
        case .neg: return negTextColor
        case .neutral: return inkDimColor
        }
    }
}
