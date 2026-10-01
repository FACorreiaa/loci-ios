import SwiftUI

/// "Let friends find you": verify your number by SMS so people who have it in
/// their contacts can find you. Contact matching only ever matches verified
/// numbers, so without this nobody can find you that way.
struct PhoneVerifySheet: View {
  @Environment(\.dismiss) private var dismiss
  var onVerified: (String) -> Void = { _ in }

  enum Step { case number, code }

  @State private var step = Step.number
  @State private var number = ""
  @State private var code = ""
  @State private var isWorking = false
  @State private var error: String?

  var body: some View {
    NavigationStack {
      Form {
        switch step {
        case .number:
          Section {
            TextField("+351 912 345 678", text: $number)
              .keyboardType(.phonePad).textContentType(.telephoneNumber)
          } header: {
            Text("Your mobile number")
          } footer: {
            Text("Start with + and your country code. We text you a code once. Friends never see your number; it only lets their contacts find you.")
          }
          Section {
            Button("Send code") { send() }.disabled(PhoneNumber.e164(number) == nil || isWorking)
          }
        case .code:
          Section {
            TextField("6-digit code", text: $code)
              .keyboardType(.numberPad).textContentType(.oneTimeCode)
          } header: {
            Text("Code sent to \(PhoneNumber.e164(number) ?? number)")
          }
          Section {
            Button("Verify") { verify() }.disabled(code.count < 4 || isWorking)
            Button("Change number") { step = .number; code = "" }.tint(.lociMutedInk)
          }
        }
        if isWorking { Section { ProgressView() } }
      }
      .scrollContentBackground(.hidden)
      .background(Color.lociPaper.ignoresSafeArea())
      .navigationTitle("Let friends find you").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
      .errorAlert($error)
    }
  }

  private func send() {
    guard let phone = PhoneNumber.e164(number) else { return }
    isWorking = true
    Task {
      defer { isWorking = false }
      do {
        try await ProgressAPI.sendPhoneCode(to: phone)
        step = .code
      } catch { self.error = error.userMessage }
    }
  }

  private func verify() {
    guard let phone = PhoneNumber.e164(number) else { return }
    isWorking = true
    Task {
      defer { isWorking = false }
      do {
        try await ProgressAPI.attachPhone(phone, code: code.trimmingCharacters(in: .whitespaces))
        onVerified(phone)
        dismiss()
      } catch { self.error = error.userMessage }
    }
  }
}

nonisolated enum PhoneNumber {
  /// "+351 912-345 678" → "+351912345678"; nil unless it is a plausible E.164
  /// number (a leading +, then 8 to 15 digits). The server checks it again.
  static func e164(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("+") else { return nil }
    let digits = trimmed.dropFirst().filter(\.isNumber)
    guard (8...15).contains(digits.count), digits.first != "0" else { return nil }
    return "+" + digits
  }
}
