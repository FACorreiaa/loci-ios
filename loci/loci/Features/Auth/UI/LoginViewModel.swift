import Combine
import LociConnectProto
import SwiftUI

@MainActor public final class LoginViewModel: ObservableObject {
  @Published public var email = ""
  @Published public var password = ""
  @Published public var username = ""
  @Published public var confirmPassword = ""
  @Published public var isSignup = false

  @Published public var isLoading = false
  @Published public var errorMessage: String?
  @Published public var successMessage: String?

  @Published public var showForgotPassword = false
  @Published public var showMFAModal = false
  @Published public var pendingMFAToken: String?

  private let authService: AuthService
  public var onAuthenticated: () -> Void

  public init(authService: AuthService? = nil, onAuthenticated: @escaping () -> Void = {}) {
    self.authService = authService ?? .shared
    self.onAuthenticated = onAuthenticated
  }

  public func clearMessages() {
    errorMessage = nil
    successMessage = nil
  }

  public func performAction() {
    clearMessages()
    if isSignup { performSignup() } else { performLogin() }
  }

  public func performLogin() {
    guard !email.isEmpty, !password.isEmpty else {
      errorMessage = "Please enter both email and password."
      return
    }

    isLoading = true
    Task {
      do {
        let response = try await authService.login(email: email.trimmingCharacters(in: .whitespaces), password: password)
        if response.mfaRequired {
          self.pendingMFAToken = response.mfaToken
          self.showMFAModal = true
          self.isLoading = false
        } else {
          self.isLoading = false
          self.onAuthenticated()
        }
      } catch {
        self.isLoading = false
        self.errorMessage = error.localizedDescription
      }
    }
  }

  public func performSignup() {
    guard !email.isEmpty, !username.isEmpty, !password.isEmpty else {
      errorMessage = "Please fill out all fields."
      return
    }
    guard password == confirmPassword else {
      errorMessage = "Passwords do not match."
      return
    }

    isLoading = true
    Task {
      let email = email.trimmingCharacters(in: .whitespaces)
      do {
        _ = try await authService.register(
          email: email,
          username: username.trimmingCharacters(in: .whitespaces),
          password: password
        )
        Analytics.capture(.signupCompleted, ["method": "password"])
      } catch {
        self.isLoading = false
        self.errorMessage = error.localizedDescription
        return
      }

      // Register issues no tokens. Asking a new user to type the same password
      // again is where a first trip was being lost (web: SignUp.tsx does the same).
      // A brand-new account has no second factor, so there is no MFA branch here.
      do {
        _ = try await authService.login(email: email, password: password)
        self.isLoading = false
        self.onAuthenticated()
      } catch {
        // The account exists; only the automatic sign-in failed.
        self.isLoading = false
        self.isSignup = false
        self.successMessage = "Account created. Sign in to continue."
        self.password = ""
        self.confirmPassword = ""
      }
    }
  }

  public func handleMFASubmit(code: String, recoveryCode: String?) {
    guard let token = pendingMFAToken else { return }
    isLoading = true
    Task {
      do {
        _ = try await authService.verifyMFA(mfaToken: token, code: code, recoveryCode: recoveryCode)
        self.showMFAModal = false
        self.pendingMFAToken = nil
        self.isLoading = false
        self.onAuthenticated()
      } catch {
        self.isLoading = false
        self.errorMessage = error.localizedDescription
      }
    }
  }

  public func performGoogleSignIn() { performNativeSignIn { try await GoogleAuthService.shared.signInWithGoogle() } }

  public func performAppleSignIn() { performNativeSignIn { try await AppleSignInService.shared.signInWithApple() } }

  private func performNativeSignIn(_ signIn: @escaping () async throws -> Loci_CustomAuth_OAuthCallbackResponse) {
    clearMessages()
    isLoading = true
    Task {
      do {
        _ = try await signIn()
        self.isLoading = false
        self.onAuthenticated()
      } catch {
        self.isLoading = false
        if (error as? APIError) == .cancelled { return }
        self.errorMessage = error.localizedDescription
      }
    }
  }
}
