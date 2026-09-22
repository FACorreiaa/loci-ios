import AuthenticationServices
import Connect
import Foundation
import LociConnectProto
import UIKit

@MainActor public final class CalendarConnectService: NSObject, ASWebAuthenticationPresentationContextProviding {
  public static let shared = CalendarConnectService()

  private let client: Loci_Calendar_CalendarServiceClient
  private var webAuthSession: ASWebAuthenticationSession?

  public init(client: Loci_Calendar_CalendarServiceClient? = nil) {
    self.client = client ?? Loci_Calendar_CalendarServiceClient(client: ConnectTransport.shared.protocolClient)
  }

  public func listConnections() async throws -> [Loci_Calendar_CalendarConnection] {
    let headers: Connect.Headers = [:]
    let res = await client.listCalendarConnections(request: Loci_Calendar_ListCalendarConnectionsRequest(), headers: headers)
    if let err = res.error { throw APIError.custom(err.message ?? "Could not load calendars.") }
    return res.message?.connections ?? []
  }

  public func connect(_ provider: Loci_Calendar_CalendarProvider) async throws {
    let path = provider == .calendly ? "calendly" : "google-calendar"
    let headers: Connect.Headers = [:]

    var start = Loci_Calendar_StartCalendarConnectRequest()
    start.provider = provider
    start.redirectUri = OAuthWebAuth.nativeRedirectURI(provider: path)
    let startRes = await client.startCalendarConnect(request: start, headers: headers)
    if let err = startRes.error { throw APIError.custom(err.message ?? "That calendar isn't available right now.") }
    guard let message = startRes.message, let authURL = URL(string: message.authURL) else { throw APIError.invalidResponse }

    let callbackURL: URL
    do {
      callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: OAuthWebAuth.callbackScheme) { callbackURL, error in
          if let error {
            continuation.resume(throwing: OAuthWebAuth.isCancellation(error) ? APIError.cancelled : error)
          } else if let callbackURL {
            continuation.resume(returning: callbackURL)
          } else {
            continuation.resume(throwing: APIError.invalidResponse)
          }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        self.webAuthSession = session
        session.start()
      }
    } catch let error as APIError {
      throw error
    } catch {
      if OAuthWebAuth.isCancellation(error) { throw APIError.cancelled }
      throw APIError.custom("Calendar connect didn't finish. Please try again.")
    }

    guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else { throw APIError.invalidResponse }
    let items = components.queryItems ?? []
    if let oauthError = items.first(where: { $0.name == "error" })?.value, !oauthError.isEmpty {
      throw APIError.custom("Calendar connect was declined.")
    }
    let code = items.first(where: { $0.name == "code" })?.value ?? ""
    let state = items.first(where: { $0.name == "state" })?.value ?? message.state
    guard !code.isEmpty else { throw APIError.invalidResponse }

    var complete = Loci_Calendar_CompleteCalendarConnectRequest()
    complete.provider = provider
    complete.code = code
    complete.state = state
    let done = await client.completeCalendarConnect(request: complete, headers: headers)
    if let err = done.error { throw APIError.custom(err.message ?? "Calendar connect didn't finish. Please try again.") }
  }

  public func disconnect(id: String) async throws {
    let headers: Connect.Headers = [:]
    var req = Loci_Calendar_DisconnectCalendarRequest()
    req.connectionID = id
    let res = await client.disconnectCalendar(request: req, headers: headers)
    if let err = res.error { throw APIError.custom(err.message ?? "Could not disconnect.") }
  }

  public nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    MainActor.assumeIsolated {
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      if let window = OAuthWebAuth.presentationWindow(from: scenes) { return window }
      if let scene = scenes.first {
        let window = UIWindow(windowScene: scene)
        window.makeKeyAndVisible()
        return window
      }
      return ASPresentationAnchor()
    }
  }
}
