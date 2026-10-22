import LociConnectProto
import SwiftUI

/// Public by default: anyone can follow you. Private: people ask, and only the
/// ones you approve see your trips, achievements and follow lists (web:
/// PrivacySetting). Going public again approves everyone waiting.
struct AccountPrivacyToggle: View {
  @State private var settings: Loci_Social_SocialSettings?
  @State private var isSaving = false
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Toggle("Private account", isOn: binding).disabled(settings == nil || isSaving)
      Text(
        "People ask to follow you, and only those you approve see your trips, achievements and who you follow. "
          + "Your name and photo stay visible. Turning this off approves everyone waiting."
      )
      .font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
    }
    .errorAlert($error)
    .task {
      do { settings = try await SocialAPI.socialSettings() } catch { if !error.isCancellation { self.error = error.userMessage } }
    }
  }

  private var binding: Binding<Bool> {
    Binding(
      get: { settings?.isPrivate ?? false },
      set: { on in
        guard let previous = settings else { return }
        settings?.isPrivate = on
        isSaving = true
        Task {
          defer { isSaving = false }
          do { settings = try await SocialAPI.setPrivate(on) } catch {
            settings = previous
            self.error = error.userMessage
          }
        }
      }
    )
  }
}
