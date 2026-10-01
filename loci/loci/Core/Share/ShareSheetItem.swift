import Foundation
import Observation

/// What a ShareLink hands over: the text at once, the link once the server
/// minted one. Minting happens when the screen appears, not on tap, so the
/// system sheet never waits on the network; a failed mint leaves the text.
@MainActor @Observable final class ShareSheetItem {
  typealias Mint = @Sendable (ShareTarget) async throws -> URL

  let target: ShareTarget
  private(set) var url: URL?
  private(set) var attempted = false
  private let mint: Mint

  init(target: ShareTarget, mint: @escaping Mint = { try await ShareAPI.createLink(target: $0, userID: await AuthSessionManager.shared.currentUserID) }) {
    self.target = target
    self.mint = mint
  }

  /// The title and the link, or today's text while there is no link.
  var text: String {
    guard let url else { return target.fallbackText }
    return "\(target.title)\n\(url.absoluteString)"
  }

  func prepare() async {
    guard !attempted, target.canLink else { return }
    attempted = true
    let target = target
    let mint = mint
    guard let minted = try? await mint(target) else { return }
    url = minted
    Analytics.capture(.shareLinkCreated, ["content_type": target.analyticsName])
  }
}
