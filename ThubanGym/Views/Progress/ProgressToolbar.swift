import SwiftUI
import ThubanGymCore

/// Progress's actions on the right of the section bar (use `ToolbarButton` / `ToolbarDivider` / `SegmentedPicker`
/// with `segmentHeight: SegmentedPickerHeight.toolbar`). OWNER: same as ProgressScreen.
///
/// TODO: the design's toolbar for Progress (see ARCHITECTURE.md → Section toolbars).
struct ProgressToolbar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        EmptyView()
    }
}
