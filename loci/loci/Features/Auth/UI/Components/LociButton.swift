import SwiftUI

public struct LociButton: View {
    public enum Style {
        case primary
        case secondary
        case destructive
    }

    public let title: String
    public let style: Style
    public let isLoading: Bool
    public let action: () -> Void

    public init(
        title: String,
        style: Style = .primary,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: textColor))
                        .scaleEffect(0.9)
                }
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(textColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(backgroundColor)
            .cornerRadius(LociTheme.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: LociTheme.cornerRadius)
                    .stroke(borderColor, lineWidth: LociTheme.borderWidth)
            )
        }
        .disabled(isLoading)
    }

    private var textColor: Color {
        switch style {
        case .primary:
            return .white
        case .secondary:
            return .lociInk
        case .destructive:
            return .white
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary:
            return .lociCoral
        case .secondary:
            return .lociCard
        case .destructive:
            return Color.red.opacity(0.85)
        }
    }

    private var borderColor: Color {
        switch style {
        case .primary:
            return Color.clear
        case .secondary:
            return .lociBorder
        case .destructive:
            return Color.clear
        }
    }
}
