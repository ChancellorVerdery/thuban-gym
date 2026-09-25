import AudioToolbox
import Foundation
import UIKit
import UserNotifications

/// The rest timer's 0:00: a local notification (with sound) scheduled for the end of the rest, so it arrives when
/// the phone is locked or in a pocket, and a haptic when the app is on screen. Local notifications only — no push,
/// no Live Activity. Permission is asked the first time a rest starts (never during a smoke run).
@MainActor
final class RestAlerts: NSObject, UNUserNotificationCenterDelegate {
    nonisolated static let identifier = "org.thuban.gym.rest"
    var smoke = false
    private var asked = false

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func schedule(at date: Date, title: String, body: String) {
        guard !smoke else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        let interval = date.timeIntervalSinceNow
        guard interval > 0.5 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(identifier: Self.identifier, content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
        let add = { center.add(request) { error in if let error { AppModel.logger.error("rest notification: \(error.localizedDescription, privacy: .public)") } } }
        if asked {
            add()
        } else {
            asked = true
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in add() }
        }
    }

    func cancel() {
        guard !smoke else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
    }

    /// 0:00 with the app open: a success haptic (the notification's banner is suppressed; its sound plays).
    func restFinishedInForeground() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // The app is in front: no banner over the rest screen, just the sound.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(notification.request.identifier == RestAlerts.identifier ? [.sound] : [.banner, .sound])
    }
}
