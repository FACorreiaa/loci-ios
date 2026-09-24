import Foundation
import LociConnectProto
import Observation

/// Tells the account where this iPhone can be reached: web's
/// `lib/push/push-client.ts`, with an APNs token in place of a browser
/// subscription. Once registered, the server pushes "your search finished"
/// itself, even to a killed app, and the local notification steps aside.
///
/// A token is only worth registering against the host it belongs to: App
/// Store and TestFlight builds hold production tokens, a build signed with a
/// development profile holds a sandbox one, and Apple drops a token sent to
/// the other host without an error. The build configuration decides.
@Observable @MainActor final class PushRegistration {
  static let shared = PushRegistration()

  /// "<userId>|<token>" of the last successful registration, so a launch
  /// with the same token and account does not post again.
  private static let registeredKey = "loci_apns_registered"

  private let user = Loci_User_UserServiceClient(client: ConnectTransport.shared.protocolClient)
  private var registered: String? {
    didSet { isRegistered = registered != nil }
  }

  /// True once the server holds this token for the signed-in account.
  private(set) var isRegistered = false

  init() {
    registered = UserDefaults.standard.string(forKey: Self.registeredKey)
    isRegistered = registered != nil
  }

  /// The bundle id is the APNs topic the server sends to.
  nonisolated static var topic: String { Bundle.main.bundleIdentifier ?? "" }

  /// Debug builds are signed with a development profile (`aps-environment`
  /// development in loci.entitlements), every other configuration is production.
  nonisolated static var environment: String {
    #if DEBUG
      "sandbox"
    #else
      "production"
    #endif
  }

  /// The registration for a token, as a pure function so a test can read it.
  nonisolated static func request(
    token: String, topic: String = PushRegistration.topic, environment: String = PushRegistration.environment
  ) -> Loci_User_RegisterPushDeviceRequest {
    var request = Loci_User_RegisterPushDeviceRequest()
    request.platform = .apns
    request.endpoint = token
    request.apnsTopic = topic
    request.apnsEnvironment = environment
    return request
  }

  /// Register the current token for the current account, if both exist and
  /// this pair has not been registered already. Failure is silent: the local
  /// notification path still works, and the next launch tries again.
  func registerIfNeeded() async {
    guard let token = PushNotificationManager.shared.deviceToken, !token.isEmpty,
      let userId = AuthSessionManager.shared.currentUserID
    else { return }
    let stamp = "\(userId)|\(token)"
    if registered == stamp { return }
    do {
      _ = try await rpc("Could not register for notifications.", Self.request(token: token)) {
        await self.user.registerPushDevice(request: $0, headers: [:])
      }
      UserDefaults.standard.set(stamp, forKey: Self.registeredKey)
      registered = stamp
    } catch {
      registered = nil
      UserDefaults.standard.removeObject(forKey: Self.registeredKey)
    }
  }

  /// Forget this token on the server, before the session that could ask is
  /// gone. Web does the same in `AuthContext` ahead of logout.
  func unregister() async {
    defer {
      registered = nil
      UserDefaults.standard.removeObject(forKey: Self.registeredKey)
    }
    guard let token = PushNotificationManager.shared.deviceToken, !token.isEmpty, registered != nil else { return }
    var request = Loci_User_UnregisterPushDeviceRequest()
    request.endpoint = token
    _ = try? await rpc("", request) { await self.user.unregisterPushDevice(request: $0, headers: [:]) }
  }
}
