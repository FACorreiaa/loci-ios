import Foundation

public struct AppConfig: Sendable {
    public static let shared = AppConfig()

    public let googleClientID: String
    public let googleReversedClientID: String
    public let postHogProjectToken: String
    public let postHogHost: String
    public let mapboxAPIKey: String
    public let connectBaseURL: String

    public init(bundle: Bundle = .main) {
        self.googleClientID = (bundle.object(forInfoDictionaryKey: "GoogleOAuthClientID") as? String)
            ?? "1062609475304-00i5dpghpvgrbjalksnklg8cddgih8b3.apps.googleusercontent.com"
        self.googleReversedClientID = (bundle.object(forInfoDictionaryKey: "GoogleOAuthReversedClientID") as? String)
            ?? "com.googleusercontent.apps.1062609475304-00i5dpghpvgrbjalksnklg8cddgih8b3"
        self.postHogProjectToken = (bundle.object(forInfoDictionaryKey: "PostHogProjectToken") as? String)
            ?? "phc_xtQKkiev2PEpGZhrLFAYR5cfPLVPuXTx9wXnMF99XmJE"
        self.postHogHost = (bundle.object(forInfoDictionaryKey: "PostHogHost") as? String)
            ?? "https://eu.i.posthog.com"
        self.mapboxAPIKey = (bundle.object(forInfoDictionaryKey: "MapboxAPIKey") as? String) ?? ""
        self.connectBaseURL = (bundle.object(forInfoDictionaryKey: "ConnectBaseURL") as? String)
            ?? "http://localhost:8000"
    }
}
