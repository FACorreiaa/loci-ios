import SwiftUI

/// The second-factor step of sign-in. The caller owns the request, so it owns
/// `isLoading` and `errorMessage` too; the sheet only collects the code.
public struct MFACodeSheet: View {
  public let isLoading: Bool
  public let errorMessage: String?
  public let onSubmit: (String, String?) -> Void
  public let onCancel: () -> Void

  @State private var code: String = ""
  @State private var recoveryCode: String = ""
  @State private var useRecoveryCode: Bool = false

  public init(isLoading: Bool, errorMessage: String?, onSubmit: @escaping (String, String?) -> Void, onCancel: @escaping () -> Void) {
    self.isLoading = isLoading
    self.errorMessage = errorMessage
    self.onSubmit = onSubmit
    self.onCancel = onCancel
  }

  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 24) {
          VStack(spacing: 8) {
            Image(systemName: "lock.shield.fill").font(.system(size: 48)).foregroundStyle(Color.lociCoral).padding(.top, 16)
              .accessibilityHidden(true)

            Text("Two-Factor Authentication").font(.title2.weight(.bold)).foregroundStyle(Color.lociInk)

            Text("Enter the verification code from your authenticator app to complete sign in.").font(.subheadline).foregroundStyle(
              Color.lociInk.opacity(0.7)
            ).multilineTextAlignment(.center).padding(.horizontal, 16)
          }

          if let errorMessage {
            HStack(spacing: 8) {
              Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.lociDestructive)
              Text(errorMessage).font(.footnote).foregroundStyle(Color.lociDestructive)
              Spacer()
            }.padding(12).background(Color.lociDestructive.opacity(0.08)).clipShape(.rect(cornerRadius: LociTheme.cornerRadius))
          }

          if !useRecoveryCode {
            LociTextField(title: "6-Digit Code", placeholder: "123456", systemImage: "key.fill", text: $code, keyboardType: .numberPad)
          } else {
            LociTextField(title: "Recovery Code", placeholder: "Enter backup recovery code", systemImage: "shield.lefthalf.filled", text: $recoveryCode)
          }

          Button {
            withAnimation { useRecoveryCode.toggle() }
          } label: {
            Text(useRecoveryCode ? "Use Authenticator Code instead" : "Use a backup recovery code").font(.footnote.weight(.medium)).foregroundStyle(
              Color.lociCoral
            ).frame(minHeight: LociTheme.minTapTarget)
          }

          LociButton(title: "Verify", style: .primary, isLoading: isLoading) {
            if useRecoveryCode { onSubmit("", recoveryCode) } else { onSubmit(code, nil) }
          }.disabled(!useRecoveryCode && code.count < 6)
        }.padding(20)
      }.scrollBounceBehavior(.basedOnSize).background(Color.lociPaper.ignoresSafeArea()).toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
      }
    }
  }
}
