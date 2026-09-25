import SwiftUI
import ThubanGymCore

/// Plan's actions on the right of the section bar (use `ToolbarButton` / `ToolbarDivider` / `SegmentedPicker`
/// with `segmentHeight: SegmentedPickerHeight.toolbar`). OWNER: same as PlanView.
///
/// TODO: the design's toolbar for Plan (see ARCHITECTURE.md → Section toolbars).
struct PlanToolbar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        EmptyView()
    }
}
