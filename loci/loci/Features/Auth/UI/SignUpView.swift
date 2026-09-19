import SwiftUI

public struct SignUpView: View {
    @ObservedObject public var viewModel: LoginViewModel

    public init(viewModel: LoginViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 16) {
            LociTextField(
                title: "Username",
                placeholder: "traveler",
                systemImage: "person.fill",
                text: $viewModel.username,
                textContentType: .username
            )

            LociTextField(
                title: "Email",
                placeholder: "you@example.com",
                systemImage: "envelope.fill",
                text: $viewModel.email,
                keyboardType: .emailAddress,
                textContentType: .emailAddress
            )

            LociTextField(
                title: "Password",
                placeholder: "At least 8 characters",
                systemImage: "lock.fill",
                text: $viewModel.password,
                isSecure: true,
                textContentType: .newPassword
            )

            LociTextField(
                title: "Confirm Password",
                placeholder: "Repeat your password",
                systemImage: "lock.shield.fill",
                text: $viewModel.confirmPassword,
                isSecure: true,
                textContentType: .newPassword
            )

            LociButton(
                title: "Create Account",
                style: .primary,
                isLoading: viewModel.isLoading
            ) {
                viewModel.performAction()
            }
            .padding(.top, 8)
        }
    }
}
