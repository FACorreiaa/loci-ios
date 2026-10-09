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
      ScrollView {
        VStack(spacing: 24) {
          VStack(spacing: 8) {
            Image(systemName: "envelope.badge.shield.half.filled").font(.system(size: 48)).foregroundStyle(Color.lociCoral).padding(.top, 16)
              .accessibilityHidden(true)

            Text("Reset Password").font(.title2.weight(.bold)).foregroundStyle(Color.lociInk)

            Text("Enter your email address and we will send you instructions to reset your password.").font(.subheadline).foregroundStyle(
              Color.lociInk.opacity(0.7)
            ).multilineTextAlignment(.center).padding(.horizontal, 16)
          }

          if let successMessage {
            Text(successMessage).font(.subheadline).foregroundStyle(.green).padding().frame(maxWidth: .infinity).background(Color.green.opacity(0.1))
              .clipShape(.rect(cornerRadius: LociTheme.cornerRadius))
          }

          if let errorMessage {
            Text(errorMessage).font(.subheadline).foregroundStyle(.red).padding().frame(maxWidth: .infinity).background(Color.red.opacity(0.1))
              .clipShape(.rect(cornerRadius: LociTheme.cornerRadius))
          }

          LociTextField(
            title: "Email",
            placeholder: "you@example.com",
            systemImage: "envelope.fill",
            text: $email,
            keyboardType: .emailAddress,
            textContentType: .emailAddress
          )

          LociButton(title: "Send Reset Link", style: .primary, isLoading: isLoading) { submit() }.disabled(
            email.trimmingCharacters(in: .whitespaces).isEmpty
          )
        }.padding(20)
      }.scrollBounceBehavior(.basedOnSize).background(Color.lociPaper.ignoresSafeArea()).toolbar {
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
        isLoading = false
        successMessage = "Check your email for instructions to reset your password."
      } catch {
        isLoading = false
        errorMessage = error.localizedDescription
      }
    }
  }
}
