import LociConnectProto
import SwiftUI

/// Your invite link as a QR code to show in person, and a link to send.
/// Opening it is consent on both sides, so it befriends in one step.
struct InviteSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var invite: Loci_Social_Invite?
  @State private var error: String?
  @State private var isRotating = false

  var body: some View {
    NavigationStack {
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
          ShareLink(item: url, message: Text("Travel with me on Loci")) {
            Label("Send invite link", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent).tint(.lociCoral).controlSize(.large)
          Button("Make a new link", systemImage: "arrow.clockwise") { rotate() }
            .disabled(isRotating).font(.lociCaption()).tint(.lociMutedInk)
        } else {
          ProgressView()
        }
      }
      .padding(24)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color.lociPaper.ignoresSafeArea())
      .navigationTitle("Invite a friend").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
      .errorAlert($error)
      .task {
        do { invite = try await SocialAPI.myInvite() } catch { self.error = error.userMessage }
      }
    }
  }

  /// The old link stops working.
  private func rotate() {
    isRotating = true
    Task {
      defer { isRotating = false }
      do { invite = try await SocialAPI.rotateInvite() } catch { self.error = error.userMessage }
    }
  }
}
