import SwiftUI

public struct LociTextField: View {
  public let title: String
  public let placeholder: String
  public let systemImage: String
  @Binding public var text: String
  public var isSecure: Bool = false
  public var keyboardType: UIKeyboardType = .default
  public var textContentType: UITextContentType?

  @State private var isShowingPassword: Bool = false
  @FocusState private var isFocused: Bool

  public init(
    title: String,
    placeholder: String,
    systemImage: String,
    text: Binding<String>,
    isSecure: Bool = false,
    keyboardType: UIKeyboardType = .default,
    textContentType: UITextContentType? = nil
  ) {
    self.title = title
    self.placeholder = placeholder
    self.systemImage = systemImage
    self._text = text
    self.isSecure = isSecure
    self.keyboardType = keyboardType
    self.textContentType = textContentType
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      // The field carries the title as its label, so VoiceOver doesn't read it twice.
      Text(title).font(.caption.weight(.medium)).foregroundStyle(Color.lociMutedInk).accessibilityHidden(true)

      HStack(spacing: 12) {
        Image(systemName: systemImage).foregroundStyle(Color.lociMutedInk).frame(width: 20).accessibilityHidden(true)

        if isSecure && !isShowingPassword {
          SecureField(placeholder, text: $text).textContentType(textContentType).autocorrectionDisabled().textInputAutocapitalization(.never)
            .focused($isFocused).accessibilityLabel(title)
        } else {
          TextField(placeholder, text: $text).keyboardType(keyboardType).textContentType(textContentType).autocorrectionDisabled()
            .textInputAutocapitalization(.never).focused($isFocused).accessibilityLabel(title)
        }

        if isSecure {
          Button(isShowingPassword ? "Hide password" : "Show password", systemImage: isShowingPassword ? "eye.slash" : "eye") {
            // The swap replaces the field, which drops focus; hand it to the new one.
            let refocus = isFocused
            isShowingPassword.toggle()
            if refocus { Task { isFocused = true } }
          }
          .labelStyle(.iconOnly).foregroundStyle(Color.lociMutedInk)
          // A 44pt target that lays out at icon size, so the field keeps its height.
          .frame(width: LociTheme.minTapTarget, height: LociTheme.minTapTarget).contentShape(.rect).padding(-11)
        }
      }.padding(.horizontal, 14).padding(.vertical, 12).background(Color.lociCard).clipShape(.rect(cornerRadius: LociTheme.cornerRadius)).overlay {
        RoundedRectangle(cornerRadius: LociTheme.cornerRadius).stroke(Color.lociBorder, lineWidth: LociTheme.borderWidth)
      }
    }
  }
}
