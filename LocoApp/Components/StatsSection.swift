import SwiftUI

struct StatsSection: View {
    let data: StatsData
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            // Badge
            Text(data.badgeText)
                .font(.system(size: DesignSystem.Typography.bodySmall, weight: DesignSystem.Typography.medium))
                .foregroundColor(DesignSystem.Colors.primary)
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.xs)
                .background(DesignSystem.Colors.tagBlue)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
            
            // Stats grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: DesignSystem.Spacing.lg) {
                ForEach(data.items.indices, id: \.self) { index in
                    let item = data.items[index]
                    StatItemView(item: item)
                }
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.xl)
    }
}

struct StatItemView: View {
    let item: StatItem
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xs) {
            Text(item.value)
                .font(.system(size: DesignSystem.Typography.headingMedium, weight: DesignSystem.Typography.bold))
                .foregroundColor(DesignSystem.Colors.gray900)
            
            Text(item.label)
                .font(.system(size: DesignSystem.Typography.bodySmall, weight: DesignSystem.Typography.regular))
                .foregroundColor(DesignSystem.Colors.gray600)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }
}

#Preview {
    StatsSection(data: StatsData.sample)
        .background(DesignSystem.Colors.backgroundPrimary)
}