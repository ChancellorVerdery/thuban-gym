import SwiftUI
import ThubanGymCore

/// Today's actions on the right of the section bar (use `ToolbarButton` / `ToolbarDivider` / `SegmentedPicker`
/// with `segmentHeight: SegmentedPickerHeight.toolbar`). OWNER: same as TodayView.
///
/// TODO: the design's toolbar for Today (see ARCHITECTURE.md → Section toolbars).
struct TodayToolbar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        EmptyView()
    }
}
