import SwiftUI

public struct MFACodeSheet: View {
  public let mfaToken: String
  public let onSubmit: (String, String?) -> Void
  public let onCancel: () -> Void

  @State private var code: String = ""
  @State private var recoveryCode: String = ""
  @State private var useRecoveryCode: Bool = false
  @State private var isLoading: Bool = false

  public init(mfaToken: String, onSubmit: @escaping (String, String?) -> Void, onCancel: @escaping () -> Void) {
    self.mfaToken = mfaToken
    self.onSubmit = onSubmit
    self.onCancel = onCancel
  }

  public var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        VStack(spacing: 8) {
          Image(systemName: "lock.shield.fill").font(.system(size: 48)).foregroundColor(.lociCoral).padding(.top, 16)

          Text("Two-Factor Authentication").font(.title2.weight(.bold)).foregroundColor(.lociInk)

          Text("Enter the verification code from your authenticator app to complete sign in.").font(.subheadline).foregroundColor(
            .lociInk.opacity(0.7)
          ).multilineTextAlignment(.center).padding(.horizontal, 16)
        }

        if !useRecoveryCode {
          LociTextField(title: "6-Digit Code", placeholder: "123456", systemImage: "key.fill", text: $code, keyboardType: .numberPad)
        } else {
          LociTextField(title: "Recovery Code", placeholder: "Enter backup recovery code", systemImage: "shield.lefthalf.filled", text: $recoveryCode)
        }

        Button {
          withAnimation { useRecoveryCode.toggle() }
        } label: {
          Text(useRecoveryCode ? "Use Authenticator Code instead" : "Use a backup recovery code").font(.footnote.weight(.medium)).foregroundColor(
            .lociCoral
          )
        }

        Spacer()

        LociButton(title: "Verify", style: .primary, isLoading: isLoading) {
          isLoading = true
          if useRecoveryCode { onSubmit("", recoveryCode) } else { onSubmit(code, nil) }
        }.disabled(!useRecoveryCode && code.count < 6)
      }.padding(20).background(Color.lociPaper.ignoresSafeArea()).toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
      }
    }
  }
}
