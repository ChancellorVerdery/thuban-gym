import Foundation

// Slot-precise editing of the cycle for the Plan screen's "Cycle order" editor. Unlike `setCycle(_:)` (which finds
// the pointer's workout by id, so it cannot tell two "Rest" slots apart), these track the pointer by SLOT: the
// pointer stays on the same slot whatever moves around it ("Drag to reorder. The pointer stays on Pull."). None of
// them records a completion, and none of them changes overrides or extras.

extension GymData {
    /// Moves the slot at `from` so it ends up at index `to` (both 0-based, in the current cycle; `to` is clamped).
    /// The pointer follows its slot.
    public mutating func moveCycleSlot(from: Int, to: Int) {
        guard plan.cycle.indices.contains(from) else { return }
        let target = max(0, min(to, plan.cycle.count - 1))
        guard target != from else { return }
        let pointer = plan.normalizedPosition
        let id = plan.cycle.remove(at: from)
        plan.cycle.insert(id, at: target)
        var order = Array(0..<plan.cycle.count)
        let moved = order.remove(at: from)
        order.insert(moved, at: target)
        plan.position = order.firstIndex(of: pointer) ?? 0
    }

    /// Inserts a workout into the cycle at `index` (default: the end). The pointer stays on the slot it was on.
    public mutating func insertCycleSlot(_ workoutId: String, at index: Int? = nil) {
        let pointer = plan.normalizedPosition
        let wasEmpty = plan.cycle.isEmpty
        let at = max(0, min(index ?? plan.cycle.count, plan.cycle.count))
        plan.cycle.insert(workoutId, at: at)
        plan.position = wasEmpty ? 0 : (at <= pointer ? pointer + 1 : pointer)
    }

    /// Removes the slot at `index`. Removing a slot before the pointer keeps the pointer on its workout; removing the
    /// pointer's own slot hands "next up" to the slot that followed it (wrapping to the start).
    public mutating func removeCycleSlot(at index: Int) {
        guard plan.cycle.indices.contains(index) else { return }
        let pointer = plan.normalizedPosition
        plan.cycle.remove(at: index)
        guard !plan.cycle.isEmpty else {
            plan.position = 0
            return
        }
        let next = index < pointer ? pointer - 1 : pointer
        plan.position = next % plan.cycle.count
    }
}
