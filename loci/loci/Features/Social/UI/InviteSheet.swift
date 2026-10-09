import LociConnectProto
import SwiftUI

/// Your invite link as a QR code to show in person, and a link to send.
/// Opening it is consent on both sides, so it befriends in one step.
///
/// Sending goes through the system share sheet only: Messages, WhatsApp,
/// Facebook and Messenger appear there when installed, and the person's own
/// apps send the invite. Loci picks no friends and sends no texts. The code
/// never expires, so there is no "new link".
struct InviteSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var invite: Loci_Social_Invite?
  @State private var loadFailed = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 20) {
          if let invite, let url = URL(string: invite.url) {
            if let image = QRCode.image(for: invite.url) {
              Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                .frame(width: 220, height: 220).padding(12)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel("QR code for your invite link")
            }
            Text("Anyone who opens your link becomes your friend on Loci.")
              .font(.lociCaption(15)).multilineTextAlignment(.center).foregroundStyle(Color.lociMutedInk)
            // The message and the link are separate items, so the link is not
            // repeated in the text.
            ShareLink(item: url, message: Text(Self.message(for: invite))) {
              Label("Invite", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.lociCoralFill).controlSize(.large)
          } else if loadFailed {
            ContentUnavailableView {
              Label("Could not load your invite", systemImage: "link.badge.plus")
            } description: {
              Text("Check your connection and try again.")
            } actions: {
              Button("Try again") { Task { await load() } }
                .buttonStyle(.borderedProminent).tint(.lociCoralFill)
            }
          } else {
            ProgressView()
          }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
      }
      // Centred while it fits; scrolls at large text sizes instead of clipping.
      .defaultScrollAnchor(.center, for: .alignment)
      .scrollBounceBehavior(.basedOnSize)
      .background(Color.lociPaper.ignoresSafeArea())
      .navigationTitle("Invite a friend").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
      .task { await load() }
    }
  }

  /// A failure shows a retry in place of the QR code, not an endless spinner.
  private func load() async {
    loadFailed = false
    do { invite = try await SocialAPI.myInvite() } catch { loadFailed = true }
  }

  /// The server's wording; a fixed line if an older server sent none.
  static func message(for invite: Loci_Social_Invite) -> String {
    invite.shareText.isEmpty ? "I'm using Loci to plan places that fit. Join me:" : invite.shareText
  }
}
