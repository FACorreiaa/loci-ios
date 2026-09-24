import Foundation

public nonisolated struct AppConfig: Sendable {
  public static let shared = AppConfig()

  public enum Environment: String, Sendable {
    case local
    case testflight
    case production
  }

  public let environment: Environment
  public let googleClientID: String
  public let googleReversedClientID: String
  public let postHogProjectToken: String
  public let postHogHost: String
  public let mapboxAPIKey: String
  public let connectBaseURL: String
  /// Empty until the app is on the App Store; the Rate row hides while it is.
  public let appStoreID: String

  /// The App Store's write-a-review page, once there is an ID.
  public var writeReviewURL: URL? {
    appStoreID.isEmpty ? nil : URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")
  }

  public init(bundle: Bundle = .main) {
    self.googleClientID =
      (bundle.object(forInfoDictionaryKey: "GoogleOAuthClientID") as? String)
      ?? "1062609475304-00i5dpghpvgrbjalksnklg8cddgih8b3.apps.googleusercontent.com"
    self.googleReversedClientID =
      (bundle.object(forInfoDictionaryKey: "GoogleOAuthReversedClientID") as? String)
      ?? "com.googleusercontent.apps.1062609475304-00i5dpghpvgrbjalksnklg8cddgih8b3"
    self.postHogProjectToken =
      (bundle.object(forInfoDictionaryKey: "PostHogProjectToken") as? String) ?? "phc_xtQKkiev2PEpGZhrLFAYR5cfPLVPuXTx9wXnMF99XmJE"
    self.postHogHost = (bundle.object(forInfoDictionaryKey: "PostHogHost") as? String) ?? "https://eu.i.posthog.com"
    self.mapboxAPIKey = (bundle.object(forInfoDictionaryKey: "MapboxAPIKey") as? String) ?? ""
    self.appStoreID =
      (bundle.object(forInfoDictionaryKey: "AppStoreID") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    let bundleURL = (bundle.object(forInfoDictionaryKey: "ConnectBaseURL") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

    let validURL: String? = {
      guard let url = bundleURL, !url.isEmpty, !url.hasPrefix("$(") else { return nil }
      return url
    }()

    #if DEBUG
      self.environment = .local
      self.connectBaseURL = validURL ?? "http://localhost:8000"
    #else
      let isBeta = (bundle.bundleIdentifier?.contains(".beta") == true)
      self.environment = isBeta ? .testflight : .production
      self.connectBaseURL = validURL ?? "https://api.lociai.fyi"
    #endif
  }
}
