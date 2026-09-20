import SwiftUI

public struct ForgotPasswordSheet: View {
  public let onDismiss: () -> Void

  @State private var email: String = ""
  @State private var isLoading: Bool = false
  @State private var successMessage: String?
  @State private var errorMessage: String?

  public init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }

  public var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        VStack(spacing: 8) {
          Image(systemName: "envelope.badge.shield.half.filled").font(.system(size: 48)).foregroundColor(.lociCoral).padding(.top, 16)

          Text("Reset Password").font(.title2.weight(.bold)).foregroundColor(.lociInk)

          Text("Enter your email address and we will send you instructions to reset your password.").font(.subheadline).foregroundColor(
            .lociInk.opacity(0.7)
          ).multilineTextAlignment(.center).padding(.horizontal, 16)
        }

        if let successMessage {
          Text(successMessage).font(.subheadline).foregroundColor(.green).padding().frame(maxWidth: .infinity).background(Color.green.opacity(0.1))
            .cornerRadius(LociTheme.cornerRadius)
        }

        if let errorMessage {
          Text(errorMessage).font(.subheadline).foregroundColor(.red).padding().frame(maxWidth: .infinity).background(Color.red.opacity(0.1))
            .cornerRadius(LociTheme.cornerRadius)
        }

        LociTextField(
          title: "Email",
          placeholder: "you@example.com",
          systemImage: "envelope.fill",
          text: $email,
          keyboardType: .emailAddress,
          textContentType: .emailAddress
        )

        Spacer()

        LociButton(title: "Send Reset Link", style: .primary, isLoading: isLoading) { submit() }.disabled(
          email.trimmingCharacters(in: .whitespaces).isEmpty
        )
      }.padding(20).background(Color.lociPaper.ignoresSafeArea()).toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Close", action: onDismiss) }
      }
    }
  }

  private func submit() {
    isLoading = true
    errorMessage = nil
    successMessage = nil

    Task {
      do {
        try await AuthService.shared.forgotPassword(email: email.trimmingCharacters(in: .whitespaces))
        await MainActor.run {
          isLoading = false
          successMessage = "Check your email for instructions to reset your password."
        }
      } catch {
        await MainActor.run {
          isLoading = false
          errorMessage = error.localizedDescription
        }
      }
    }
  }
}
