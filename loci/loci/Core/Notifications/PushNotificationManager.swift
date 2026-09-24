import Combine
import Foundation
import UIKit
import UserNotifications

@MainActor public final class PushNotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
  public static let shared = PushNotificationManager()

  private let tokenStorageKey = "loci_apns_device_token"

  @Published public private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
  @Published public private(set) var deviceToken: String?
  @Published public private(set) var lastNotificationPayload: [AnyHashable: Any]?

  public override init() {
    super.init()
    self.deviceToken = UserDefaults.standard.string(forKey: tokenStorageKey)
  }

  /// Configure the notification center delegate.
  public func configure() {
    UNUserNotificationCenter.current().delegate = self
    UNUserNotificationCenter.current().setNotificationCategories(NotificationCategory.all)
    Task { await refreshAuthorizationStatus() }
  }

  /// Refresh the current authorization status from UNUserNotificationCenter.
  public func refreshAuthorizationStatus() async {
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    self.authorizationStatus = settings.authorizationStatus
  }

  /// Ask for permission the first time only; afterwards report whether alerts can show.
  @discardableResult public func requestAuthorizationIfNeeded() async -> Bool {
    await refreshAuthorizationStatus()
    switch authorizationStatus {
    case .notDetermined: return await requestAuthorization()
    case .authorized, .provisional, .ephemeral: return true
    default: return false
    }
  }

  /// Request push notification authorization from the user.
  @discardableResult public func requestAuthorization() async -> Bool {
    do {
      let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
      await refreshAuthorizationStatus()
      if granted { UIApplication.shared.registerForRemoteNotifications() }
      return granted
    } catch {
      print("[APNS] Failed to request authorization: \(error)")
      await refreshAuthorizationStatus()
      return false
    }
  }

  /// Called by AppDelegate when APNS successfully registers a device token.
  public func didRegisterForRemoteNotifications(withDeviceToken deviceTokenData: Data) {
    let token = deviceTokenData.map { String(format: "%02.2hhx", $0) }.joined()
    self.deviceToken = token
    UserDefaults.standard.set(token, forKey: tokenStorageKey)
    NotificationCenter.default.post(name: .pushNotificationDeviceTokenDidUpdate, object: token)
    Task { await PushRegistration.shared.registerIfNeeded() }
  }

  /// Called by AppDelegate when APNS registration fails.
  public func didFailToRegisterForRemoteNotifications(withError error: Error) {
    print("[APNS] Failed to register for remote notifications: \(error.localizedDescription)")
  }

  /// Called by AppDelegate when a remote notification is received.
  public func didReceiveRemoteNotification(userInfo: [AnyHashable: Any]) { self.lastNotificationPayload = userInfo }

  // MARK: - UNUserNotificationCenterDelegate

  /// Handle notification while the app is in the foreground.
  public func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let userInfo = notification.request.content.userInfo
    self.lastNotificationPayload = userInfo
    switch PushRoute.presentation(userInfo: userInfo, viewingSessionId: SearchSessionController.shared.viewingSessionId) {
    case .banner:
      completionHandler([.banner, .badge, .sound])
    case .suppress:
      completionHandler([])
    case .suppressAndRefresh(let refresh):
      AppRouter.shared.refreshThread(refresh)
      completionHandler([])
    }
  }

  /// Handle user interaction with a notification (e.g. tap on banner).
  public func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    self.lastNotificationPayload = userInfo
    NotificationCenter.default.post(name: .pushNotificationDidReceiveResponse, object: userInfo)
    switch PushRoute.tap(userInfo: userInfo) {
    case .nothing: break
    case .open(let link): AppRouter.shared.open(link)
    case let .openThread(link, refresh): AppRouter.shared.open(link, refresh: refresh)
    }
    completionHandler()
  }
}

public extension Notification.Name {
  static let pushNotificationDeviceTokenDidUpdate = Notification.Name("PushNotificationDeviceTokenDidUpdate")
  static let pushNotificationDidReceiveResponse = Notification.Name("PushNotificationDidReceiveResponse")
}
