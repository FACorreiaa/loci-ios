import LociConnectProto
import SwiftUI

#if canImport(FacebookLogin)
  import FacebookLogin
#endif

/// Friends from Facebook. Facebook only tells Loci about friends who also
/// connected Facebook to Loci, so this finds people already here; anyone else
/// is reached with the invite link.
///
/// Shown only when the build carries the Facebook SDK and a `FacebookAppID`
/// (`FacebookConnect.isAvailable`). Uses Limited Login: no tracking prompt,
/// and the token is verified by the server (CustomAuthService.LinkFacebook).
struct FacebookFriendsView: View {
  @State private var matches: [Match] = []
  @State private var phase = Phase.idle
  @State private var error: String?

  enum Phase { case idle, working, matched }

  struct Match: Identifiable {
    var id: String { user.id }
    let user: Loci_Social_PublicUser
    var relationship: Relationship
  }

  var body: some View {
    List {
      Section {
        Button("Connect Facebook", systemImage: "person.2.badge.key") { connect() }
          .disabled(phase == .working)
      } footer: {
        Text("Loci sees only your friends who also connected Facebook to Loci. Nothing is posted to Facebook.")
      }
      .listRowBackground(Color.lociCard)

      if phase == .working {
        Section { ProgressView() }.listRowBackground(Color.lociCard)
      } else if phase == .matched {
        Section(matches.isEmpty ? "None of your Facebook friends are on Loci yet" : "On Loci") {
          ForEach($matches) { $match in
            PersonRow(user: match.user) { RelationshipButton(user: match.user, relationship: $match.relationship) }
          }
        }
        .listRowBackground(Color.lociCard)
      }
    }
    .settingsStyle("From Facebook")
    .errorAlert($error)
  }

  private func connect() {
    phase = .working
    Task {
      do {
        let (token, nonce) = try await FacebookConnect.logIn()
        var request = Loci_CustomAuth_LinkFacebookRequest()
        request.idToken = token
        request.nonce = nonce
        _ = try await rpc("Could not connect Facebook.", request) { await ProgressAPI.auth.linkFacebook(request: $0, headers: [:]) }
        await match()
      } catch FacebookConnect.Failure.cancelled {
        phase = .idle
      } catch {
        phase = .idle
        self.error = error.userMessage
      }
    }
  }

  private func match() async {
    do {
      let found = try await SocialAPI.facebookFriends()
      matches = found.map { Match(user: $0.user, relationship: Relationship($0.relationship)) }
      phase = .matched
    } catch {
      self.error = error.userMessage
      phase = .idle
    }
  }
}

/// The Facebook SDK seam. Without the SDK in the build this is unavailable
/// and the Friends page leaves the Facebook row out.
enum FacebookConnect {
  enum Failure: Error { case cancelled, unavailable, noToken }

  static var isAvailable: Bool {
    #if canImport(FacebookLogin)
      return Bundle.main.object(forInfoDictionaryKey: "FacebookAppID") is String
    #else
      return false
    #endif
  }

  /// Limited Login with the friends permission; returns the OIDC token and
  /// the nonce it was asked for.
  @MainActor static func logIn() async throws -> (token: String, nonce: String) {
    #if canImport(FacebookLogin)
      // FacebookAutoInitEnabled is off (Info.plist) so the SDK does nothing
      // until someone asks to connect Facebook.
      ApplicationDelegate.shared.initializeSDK()
      let nonce = UUID().uuidString + UUID().uuidString
      guard let configuration = LoginConfiguration(permissions: ["public_profile", "user_friends"], tracking: .limited, nonce: nonce) else {
        throw Failure.unavailable
      }
      return try await withCheckedThrowingContinuation { continuation in
        LoginManager().logIn(configuration: configuration) { result in
          switch result {
          case .cancelled:
            continuation.resume(throwing: Failure.cancelled)
          case .failed(let error):
            continuation.resume(throwing: error)
          case .success:
            if let token = AuthenticationToken.current?.tokenString {
              continuation.resume(returning: (token, nonce))
            } else {
              continuation.resume(throwing: Failure.noToken)
            }
          }
        }
      }
    #else
      throw Failure.unavailable
    #endif
  }
}
