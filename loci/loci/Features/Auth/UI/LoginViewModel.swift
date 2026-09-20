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
      do {
        _ = try await authService.register(
          email: email.trimmingCharacters(in: .whitespaces),
          username: username.trimmingCharacters(in: .whitespaces),
          password: password
        )
        self.isLoading = false
        self.isSignup = false
        self.successMessage = "Account created successfully! Please sign in."
        self.password = ""
        self.confirmPassword = ""
      } catch {
        self.isLoading = false
        self.errorMessage = error.localizedDescription
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

  public func performGoogleSignIn() {
    clearMessages()
    isLoading = true
    Task {
      do {
        _ = try await GoogleAuthService.shared.signInWithGoogle()
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
