import SwiftUI
import UserNotifications
import BackgroundTasks
import UIKit

final class LegacyAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        if #available(iOS 13.0, *) {
        } else {
            application.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
        }
        return true
    }

    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        let before = YouPostsManager.shared.totalUnread
        YouPostsManager.shared.checkForUpdates {
            DispatchQueue.main.async {
                let after = YouPostsManager.shared.totalUnread
                let result: UIBackgroundFetchResult = (after > before) ? .newData : .noData
                completionHandler(result)
            }
        }
    }
}

@main
struct iOSchanApp: App {
    @UIApplicationDelegateAdaptor(LegacyAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    private static let refreshTaskIdentifier = "com.mcm.ioschan.youRefresh"

    init() {
        UNUserNotificationCenter.current().delegate = NotificationCenterDelegate.shared
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
            }
        }

        BGTaskScheduler.shared.register(forTaskWithIdentifier: iOSchanApp.refreshTaskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            iOSchanApp.handleAppRefresh(task: refreshTask)
        }

        iOSchanApp.scheduleAppRefresh()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    switch newPhase {
                    case .active:
                        YouPostsManager.shared.checkForUpdates()
                    case .background:
                        iOSchanApp.scheduleAppRefresh()
                    default:
                        break
                    }
                }
        }
    }

    private static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: iOSchanApp.refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("BGTask submit error: \(error)")
        }
    }

    private static func handleAppRefresh(task: BGAppRefreshTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        YouPostsManager.shared.checkForUpdates {
            task.setTaskCompleted(success: true)
            iOSchanApp.scheduleAppRefresh()
        }
    }
}
