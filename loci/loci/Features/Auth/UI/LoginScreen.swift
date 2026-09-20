import SwiftUI

public struct LoginScreen: View {
  @StateObject private var viewModel: LoginViewModel
  @Namespace private var animationNamespace

  public init(onAuthenticated: @escaping () -> Void = {}) { _viewModel = StateObject(wrappedValue: LoginViewModel(onAuthenticated: onAuthenticated)) }

  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 24) {
          headerView
          modeSwitcher
          feedbackMessages

          if viewModel.isSignup {
            SignUpView(viewModel: viewModel).transition(.opacity.combined(with: .move(edge: .trailing)))
          } else {
            SignInView(viewModel: viewModel).transition(.opacity.combined(with: .move(edge: .leading)))
          }

          oauthDivider
          googleSignInButton
        }.padding(.horizontal, 24).padding(.bottom, 32)
      }.background(Color.lociPaper.ignoresSafeArea()).sheet(isPresented: $viewModel.showForgotPassword) {
        ForgotPasswordSheet { viewModel.showForgotPassword = false }
      }.sheet(isPresented: $viewModel.showMFAModal) {
        if let token = viewModel.pendingMFAToken {
          MFACodeSheet(
            mfaToken: token,
            onSubmit: { code, recoveryCode in viewModel.handleMFASubmit(code: code, recoveryCode: recoveryCode) },
            onCancel: {
              viewModel.showMFAModal = false
              viewModel.pendingMFAToken = nil
            }
          )
        }
      }
    }
  }

  // MARK: - Subviews

  @ViewBuilder private var headerView: some View {
    VStack(spacing: 12) {
      Image("LociMascot").resizable().scaledToFit().frame(width: 96, height: 96).padding(.top, 16)

      Text("Loci").font(.system(size: 32, weight: .bold, design: .serif)).foregroundColor(.lociInk)

      Text("Your Intelligent Travel Companion").font(.subheadline).foregroundColor(.lociInk.opacity(0.7))
    }
  }

  @ViewBuilder private var modeSwitcher: some View {
    HStack(spacing: 0) {
      Button {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
          viewModel.isSignup = false
          viewModel.clearMessages()
        }
      } label: {
        Text("Sign In").font(.subheadline.weight(.semibold)).foregroundColor(viewModel.isSignup ? .lociInk.opacity(0.5) : .lociInk).frame(
          maxWidth: .infinity
        ).padding(.vertical, 10).background(
          ZStack {
            if !viewModel.isSignup {
              RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous).fill(Color.lociCard).shadow(
                color: .black.opacity(0.06),
                radius: 4,
                x: 0,
                y: 2
              ).matchedGeometryEffect(id: "TabBackground", in: animationNamespace)
            }
          }
        )
      }

      Button {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
          viewModel.isSignup = true
          viewModel.clearMessages()
        }
      } label: {
        Text("Create Account").font(.subheadline.weight(.semibold)).foregroundColor(viewModel.isSignup ? .lociInk : .lociInk.opacity(0.5)).frame(
          maxWidth: .infinity
        ).padding(.vertical, 10).background(
          ZStack {
            if viewModel.isSignup {
              RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous).fill(Color.lociCard).shadow(
                color: .black.opacity(0.06),
                radius: 4,
                x: 0,
                y: 2
              ).matchedGeometryEffect(id: "TabBackground", in: animationNamespace)
            }
          }
        )
      }
    }.padding(4).background(Color.lociMuted.opacity(0.5)).cornerRadius(LociTheme.cornerRadius + 2)
  }

  @ViewBuilder private var feedbackMessages: some View {
    if let errorMessage = viewModel.errorMessage {
      HStack(spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
        Text(errorMessage).font(.footnote).foregroundColor(.red)
        Spacer()
      }.padding(12).background(Color.red.opacity(0.08)).cornerRadius(LociTheme.cornerRadius)
    }

    if let successMessage = viewModel.successMessage {
      HStack(spacing: 8) {
        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        Text(successMessage).font(.footnote).foregroundColor(.green)
        Spacer()
      }.padding(12).background(Color.green.opacity(0.08)).cornerRadius(LociTheme.cornerRadius)
    }
  }

  @ViewBuilder private var oauthDivider: some View {
    HStack(spacing: 16) {
      Rectangle().fill(Color.lociBorder.opacity(0.8)).frame(height: 1)
      Text("or").font(.footnote).foregroundColor(.lociInk.opacity(0.6))
      Rectangle().fill(Color.lociBorder.opacity(0.8)).frame(height: 1)
    }.padding(.vertical, 4)
  }

  @ViewBuilder private var googleSignInButton: some View {
    Button {
      viewModel.performGoogleSignIn()
    } label: {
      HStack(spacing: 12) {
        Image(systemName: "g.circle.fill").font(.system(size: 20, weight: .medium)).foregroundColor(.lociCoral)
        Text("Continue with Google").font(.body.weight(.semibold)).foregroundColor(.lociInk)
      }.frame(maxWidth: .infinity).frame(height: 50).background(Color.lociCard).cornerRadius(LociTheme.cornerRadius).overlay(
        RoundedRectangle(cornerRadius: LociTheme.cornerRadius).stroke(Color.lociBorder.opacity(0.8), lineWidth: LociTheme.borderWidth)
      )
    }.disabled(viewModel.isLoading)
  }
}
