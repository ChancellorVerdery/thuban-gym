import Foundation
import ThubanGymCore

/// Extra smoke screens for Plan (the standard walk captures the cycle view as 11-plan). OWNER: Engineer B.
extension SmokeScenes {
    static var plan: [SmokeScene] {
        [
            // The weekly editor (the cycle stays saved, shown "not active").
            SmokeScene(name: "plan-weekly") { app in
                app.section = .plan
                app.setPlanType(.weekly)
            } cleanup: { app in
                app.setPlanType(.cycle)
            },
            // An edited cycle: Upper inserted as slot 3 (the pointer stays on Pull), one extra on Saturday.
            SmokeScene(name: "plan-cycle-edited") { app in
                app.section = .plan
                if let upper = app.workouts.first(where: { $0.name == "Upper" }) { app.insertCycleSlot(upper.id, at: 2) }
                if let fly = app.data.exercises.first(where: { $0.name == "Leg Curl" }) { app.addExtra(exerciseId: fly.id, date: app.today.adding(days: 2)) }
            } cleanup: { app in
                app.removeCycleSlot(at: 2)
                if let fly = app.data.exercises.first(where: { $0.name == "Leg Curl" }) { app.removeExtra(exerciseId: fly.id, date: app.today.adding(days: 2)) }
            },
            // The cycle view in dark mode.
            SmokeScene(name: "plan-dark") { app in
                app.section = .plan
                app.setAppearanceMode(.dark)
            } cleanup: { app in
                app.setAppearanceMode(.light)
            },
        ]
    }
}
