import SwiftUI

struct MobileAppAnnouncement: View {
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            // Icon
            ZStack {
                Circle()
                    .fill(LinearGradient.textGradient)
                    .frame(width: 80, height: 80)
                
                Image(systemName: "iphone")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(.white)
            }
            
            // Content
            VStack(spacing: DesignSystem.Spacing.md) {
                Text("Get the Mobile App")
                    .font(.system(size: DesignSystem.Typography.headingMedium, weight: DesignSystem.Typography.bold))
                    .foregroundColor(DesignSystem.Colors.gray900)
                
                Text("Take Loci with you wherever you go. Download our mobile app for the complete travel experience.")
                    .font(.system(size: DesignSystem.Typography.bodyMedium, weight: DesignSystem.Typography.regular))
                    .foregroundColor(DesignSystem.Colors.gray600)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            
            // Download buttons
            VStack(spacing: DesignSystem.Spacing.sm) {
                Button(action: {
                    // Handle App Store download
                }) {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: DesignSystem.Typography.headingSmall, weight: .medium))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Download on the")
                                .font(.system(size: DesignSystem.Typography.caption, weight: DesignSystem.Typography.regular))
                            Text("App Store")
                                .font(.system(size: DesignSystem.Typography.bodyMedium, weight: DesignSystem.Typography.bold))
                        }
                        
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .padding(DesignSystem.Spacing.md)
                    .background(DesignSystem.Colors.gray900)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                }
                
                Button(action: {
                    // Handle Google Play download
                }) {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Image(systemName: "play.fill")
                            .font(.system(size: DesignSystem.Typography.headingSmall, weight: .medium))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Get it on")
                                .font(.system(size: DesignSystem.Typography.caption, weight: DesignSystem.Typography.regular))
                            Text("Google Play")
                                .font(.system(size: DesignSystem.Typography.bodyMedium, weight: DesignSystem.Typography.bold))
                        }
                        
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .padding(DesignSystem.Spacing.md)
                    .background(DesignSystem.Colors.gray900)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.xl)
        }
        .padding(DesignSystem.Spacing.xl)
        .background(DesignSystem.Colors.gray50)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xLarge))
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.xl)
    }
}

#Preview {
    MobileAppAnnouncement()
        .background(DesignSystem.Colors.backgroundPrimary)
}