import AuthenticationServices
import SwiftUI

public struct LoginScreen: View {
  @State private var viewModel: LoginViewModel
  @Namespace private var animationNamespace
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// Where a finger is over the 3D mascot (BRD-001).
  @State private var mascotPointer: CGPoint?

  public init(onAuthenticated: @escaping () -> Void = {}) { _viewModel = State(initialValue: LoginViewModel(onAuthenticated: onAuthenticated)) }

  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 24) {
          headerView
          modeSwitcher
          feedbackMessages

          if viewModel.isSignup {
            SignUpView(viewModel: viewModel).transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
          } else {
            SignInView(viewModel: viewModel).transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .leading)))
          }

          oauthDivider
          appleSignInButton
          googleSignInButton
        }.padding(.horizontal, 24).padding(.bottom, 32)
      }.background(Color.lociPaper.ignoresSafeArea())
        // A failed sign-in is felt and spoken, not only shown above the form.
        .sensoryFeedback(trigger: viewModel.errorMessage) { _, message in message == nil ? nil : .error }
        .onChange(of: viewModel.errorMessage) { _, message in
          if let message { AccessibilityNotification.Announcement(message).post() }
        }
        .sheet(isPresented: $viewModel.showForgotPassword) {
          ForgotPasswordSheet { viewModel.showForgotPassword = false }
        }
        .sheet(item: $viewModel.pendingMFA) { _ in
          MFACodeSheet(
            isLoading: viewModel.isLoading,
            errorMessage: viewModel.mfaErrorMessage,
            onSubmit: { code, recoveryCode in viewModel.handleMFASubmit(code: code, recoveryCode: recoveryCode) },
            onCancel: { viewModel.cancelMFA() }
          )
        }
    }
  }

  // MARK: - Subviews

  @ViewBuilder private var headerView: some View {
    VStack(spacing: 12) {
      // The 3D mascot above a smaller lockup (BRD-001).
      Mascot3DView(pointer: mascotPointer).frame(height: 168).padding(.top, 16)
        .mascotFollows($mascotPointer)
      lockup.frame(height: 88)

      Text("Plan a trip in one sentence, walk it stop by stop.").font(.lociBody(15)).foregroundStyle(Color.lociMutedInk)
        .multilineTextAlignment(.center)
    }
  }

  /// The lockup carries the name and "Explore your way"; its letters are
  /// drawn, so VoiceOver gets them from the label.
  private var lockup: some View {
    Image("LociLockup").resizable().scaledToFit()
      .accessibilityLabel("Loci. Explore your way.")
      .accessibilityAddTraits(.isHeader)
  }

  /// Opacity-only when Reduce Motion is on; the transitions above drop their slide to match.
  private var modeAnimation: Animation { reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.8) }

  @ViewBuilder private var modeSwitcher: some View {
    HStack(spacing: 0) {
      Button {
        withAnimation(modeAnimation) {
          viewModel.isSignup = false
          viewModel.clearMessages()
        }
      } label: {
        Text("Sign in").font(.lociBody(15).weight(.semibold)).foregroundStyle(viewModel.isSignup ? Color.lociMutedInk : Color.lociInk).frame(
          maxWidth: .infinity
        ).frame(minHeight: LociTheme.minTapTarget).background(
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
      }.accessibilityAddTraits(viewModel.isSignup ? [] : .isSelected)

      Button {
        withAnimation(modeAnimation) {
          viewModel.isSignup = true
          viewModel.clearMessages()
        }
      } label: {
        Text("Create account").font(.lociBody(15).weight(.semibold)).foregroundStyle(viewModel.isSignup ? Color.lociInk : Color.lociMutedInk).frame(
          maxWidth: .infinity
        ).frame(minHeight: LociTheme.minTapTarget).background(
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
      }.accessibilityAddTraits(viewModel.isSignup ? .isSelected : [])
    }.padding(4).background(Color.lociMuted.opacity(0.5)).clipShape(.rect(cornerRadius: LociTheme.cornerRadius + 2))
  }

  @ViewBuilder private var feedbackMessages: some View {
    if let errorMessage = viewModel.errorMessage {
      HStack(spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.lociDestructive).accessibilityHidden(true)
        Text(errorMessage).font(.lociCaption(13)).foregroundStyle(Color.lociDestructive)
        Spacer()
      }.padding(12).background(Color.lociDestructive.opacity(0.08)).clipShape(.rect(cornerRadius: LociTheme.cornerRadius))
    }

    if let successMessage = viewModel.successMessage {
      HStack(spacing: 8) {
        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.lociForest).accessibilityHidden(true)
        Text(successMessage).font(.lociCaption(13)).foregroundStyle(Color.lociForest)
        Spacer()
      }.padding(12).background(Color.lociForest.opacity(0.08)).clipShape(.rect(cornerRadius: LociTheme.cornerRadius))
    }
  }

  @ViewBuilder private var oauthDivider: some View {
    HStack(spacing: 16) {
      Rectangle().fill(Color.lociBorder).frame(height: 1)
      Text("or").font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk)
      Rectangle().fill(Color.lociBorder).frame(height: 1)
    }.padding(.vertical, 4)
  }

  /// The system button, not a lookalike: App Review holds Sign in with Apple
  /// to Apple's own artwork. The request itself is built in
  /// AppleSignInService, so this only starts it.
  @ViewBuilder private var appleSignInButton: some View {
    AppleSignInLabel(style: colorScheme == .dark ? .white : .black).frame(height: 50).clipShape(.rect(cornerRadius: LociTheme.cornerRadius))
      .overlay {
        Button {
          viewModel.performAppleSignIn()
        } label: {
          Color.clear.contentShape(Rectangle())
        }.accessibilityLabel("Sign in with Apple")
      }.disabled(viewModel.isLoading).opacity(viewModel.isLoading ? 0.5 : 1)
  }

  @ViewBuilder private var googleSignInButton: some View {
    Button {
      viewModel.performGoogleSignIn()
    } label: {
      HStack(spacing: 12) {
        Image(systemName: "g.circle.fill").font(.title3.weight(.medium)).foregroundStyle(Color.lociCoral)
        Text("Continue with Google").font(.lociHeadline().weight(.semibold)).foregroundStyle(Color.lociInk)
      }.frame(maxWidth: .infinity).frame(minHeight: 50).background(Color.lociCard).clipShape(.rect(cornerRadius: LociTheme.cornerRadius)).overlay {
        RoundedRectangle(cornerRadius: LociTheme.cornerRadius).stroke(Color.lociBorder, lineWidth: LociTheme.borderWidth)
      }
    }.disabled(viewModel.isLoading).opacity(viewModel.isLoading ? 0.5 : 1)
  }
}

/// Apple's button artwork with no action of its own. SwiftUI's
/// SignInWithAppleButton insists on owning the request and its completion,
/// which would split the flow between the view and AppleSignInService.
private struct AppleSignInLabel: UIViewRepresentable {
  let style: ASAuthorizationAppleIDButton.Style

  func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
    let button = ASAuthorizationAppleIDButton(type: .continue, style: style)
    button.cornerRadius = LociTheme.cornerRadius
    button.isUserInteractionEnabled = false
    button.isAccessibilityElement = false
    return button
  }

  func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {}
}
