import SwiftUI

public struct LociTextField: View {
    public let title: String
    public let placeholder: String
    public let systemImage: String
    @Binding public var text: String
    public var isSecure: Bool = false
    public var keyboardType: UIKeyboardType = .default
    public var textContentType: UITextContentType? = nil

    @State private var isShowingPassword: Bool = false

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
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundColor(.lociInk.opacity(0.8))

            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundColor(.lociInk.opacity(0.5))
                    .frame(width: 20)

                if isSecure && !isShowingPassword {
                    SecureField(placeholder, text: $text)
                        .textContentType(textContentType)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                        .textContentType(textContentType)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                if isSecure {
                    Button {
                        isShowingPassword.toggle()
                    } label: {
                        Image(systemName: isShowingPassword ? "eye.slash" : "eye")
                            .foregroundColor(.lociInk.opacity(0.4))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.lociCard)
            .cornerRadius(LociTheme.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: LociTheme.cornerRadius)
                    .stroke(Color.lociBorder.opacity(0.6), lineWidth: LociTheme.borderWidth)
            )
        }
    }
}
