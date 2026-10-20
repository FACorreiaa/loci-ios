import UIKit
import UserNotifications

public final class AppDelegate: NSObject, UIApplicationDelegate {
  public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil)
    -> Bool
  {
    Analytics.start()
    PushNotificationManager.shared.configure()
    SearchSessionController.registerBackgroundTask()
    TripPrefetch.register()
    // iOS relaunches the app in the background to report a stay. The
    // location delegate has to exist before any scene does, or the stay is
    // dropped; with logging off, this switches off monitoring left running.
    if VisitLogger.isEnabled || launchOptions?[.location] != nil {
      Task { await VisitLogger.shared.refresh() }
    }
    return true
  }

  public func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    PushNotificationManager.shared.didRegisterForRemoteNotifications(withDeviceToken: deviceToken)
  }

  public func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    PushNotificationManager.shared.didFailToRegisterForRemoteNotifications(withError: error)
  }

  public func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    PushNotificationManager.shared.didReceiveRemoteNotification(userInfo: userInfo)
    completionHandler(.newData)
  }
}
