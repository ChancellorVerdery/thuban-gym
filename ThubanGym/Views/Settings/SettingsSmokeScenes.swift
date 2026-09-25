import Foundation
import ThubanGymCore

/// Extra Settings smoke screens (every pane is already captured by the standard walk). OWNER: Engineer C.
/// Example: an import preview — set `app.importPhase = .preview(…)` built from `AtlasImporter.convert` of a sample
/// document, capture with `window: .settings`, reset to `.idle` in `cleanup`.
extension SmokeScenes {
    static var settings: [SmokeScene] {
        []
    }
}
