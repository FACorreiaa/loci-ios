import SwiftUI

public struct SignInView: View {
  @ObservedObject public var viewModel: LoginViewModel

  public init(viewModel: LoginViewModel) { self.viewModel = viewModel }

  public var body: some View {
    VStack(spacing: 16) {
      LociTextField(
        title: "Email",
        placeholder: "you@example.com",
        systemImage: "envelope.fill",
        text: $viewModel.email,
        keyboardType: .emailAddress,
        textContentType: .emailAddress
      )

      VStack(alignment: .trailing, spacing: 6) {
        LociTextField(
          title: "Password",
          placeholder: "••••••••",
          systemImage: "lock.fill",
          text: $viewModel.password,
          isSecure: true,
          textContentType: .password
        )

        Button {
          viewModel.showForgotPassword = true
        } label: {
          Text("Forgot Password?").font(.caption.weight(.medium)).foregroundColor(.lociCoral)
        }
      }

      LociButton(title: "Sign In", style: .primary, isLoading: viewModel.isLoading) { viewModel.performAction() }.padding(.top, 8)
    }
  }
}
