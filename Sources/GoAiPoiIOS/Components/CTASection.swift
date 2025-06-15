import SwiftUI

struct CTASection: View {
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            VStack(spacing: DesignSystem.Spacing.md) {
                Text("Ready to explore?")
                    .font(.system(size: DesignSystem.Typography.headingLarge, weight: DesignSystem.Typography.bold))
                    .foregroundColor(DesignSystem.Colors.gray900)
                
                Text("Join thousands of travelers who trust Loci to discover their perfect adventure.")
                    .font(.system(size: DesignSystem.Typography.bodyLarge, weight: DesignSystem.Typography.regular))
                    .foregroundColor(DesignSystem.Colors.gray600)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Button(action: {
                    // Handle start exploring action
                }) {
                    HStack {
                        Text("Start Exploring")
                            .font(.system(size: DesignSystem.Typography.bodyMedium, weight: DesignSystem.Typography.medium))
                            .foregroundColor(.white)
                        
                        Image(systemName: "arrow.right")
                            .font(.system(size: DesignSystem.Typography.bodyMedium, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(DesignSystem.Spacing.md)
                    .background(
                        LinearGradient(
                            colors: [DesignSystem.Colors.primary, DesignSystem.Colors.primaryDark],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                    .shadow(color: DesignSystem.Colors.primary.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                
                Button(action: {
                    // Handle learn more action
                }) {
                    Text("Learn More")
                        .font(.system(size: DesignSystem.Typography.bodyMedium, weight: DesignSystem.Typography.medium))
                        .foregroundColor(DesignSystem.Colors.primary)
                        .frame(maxWidth: .infinity)
                        .padding(DesignSystem.Spacing.md)
                        .background(DesignSystem.Colors.backgroundPrimary)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                                .stroke(DesignSystem.Colors.primary, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
        }
        .padding(DesignSystem.Spacing.xl)
        .background(
            LinearGradient(
                colors: [
                    DesignSystem.Colors.backgroundSecondary,
                    DesignSystem.Colors.backgroundPurple
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xLarge))
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.xl)
    }
}

#Preview {
    CTASection()
        .background(DesignSystem.Colors.backgroundPrimary)
}