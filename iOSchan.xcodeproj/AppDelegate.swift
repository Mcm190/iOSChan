//  AppDelegate.swift
//  iOSchan


import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
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
