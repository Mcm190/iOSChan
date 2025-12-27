//
//  iOSchanApp.swift
//  iOSchan
//
//  Created by MCM on 20/12/2025.
//

import SwiftUI
import UserNotifications
import BackgroundTasks
import UIKit

final class LegacyAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        application.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
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
        // Set notification delegate and request authorization if needed
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
                .onChange(of: scenePhase) { newPhase in
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
            UserDefaults.standard.set(Date(), forKey: "lastBGTaskScheduledAt")
            print("[BGTask] Scheduled refresh at \(Date())")
        } catch {
            print("BGTask submit error: \(error)")
            UserDefaults.standard.set(Date(), forKey: "lastBGTaskScheduleErrorAt")
        }
    }

    private static func handleAppRefresh(task: BGAppRefreshTask) {
        UserDefaults.standard.set(Date(), forKey: "lastBGTaskRanAt")
        print("[BGTask] Running refresh at \(Date())")
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        YouPostsManager.shared.checkForUpdates {
            task.setTaskCompleted(success: true)
            iOSchanApp.scheduleAppRefresh()
        }
    }
}

