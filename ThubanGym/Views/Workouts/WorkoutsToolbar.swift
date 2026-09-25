import SwiftUI
import ThubanGymCore

/// Workouts's actions on the right of the section bar (use `ToolbarButton` / `ToolbarDivider` / `SegmentedPicker`
/// with `segmentHeight: SegmentedPickerHeight.toolbar`). OWNER: same as WorkoutsView.
///
/// TODO: the design's toolbar for Workouts (see ARCHITECTURE.md → Section toolbars).
struct WorkoutsToolbar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        EmptyView()
    }
}
