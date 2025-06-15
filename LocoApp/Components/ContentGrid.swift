import SwiftUI

struct ContentGrid: View {
    let items: [ContentItem]
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            ForEach(items.indices, id: \.self) { index in
                ContentCard(item: items[index])
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.xl)
    }
}

struct ContentCard: View {
    let item: ContentItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            // Header with emoji and tag
            HStack {
                Text(item.emoji)
                    .font(.system(size: DesignSystem.Typography.displayMedium))
                
                Spacer()
                
                Text(item.tag)
                    .font(.system(size: DesignSystem.Typography.caption, weight: DesignSystem.Typography.medium))
                    .foregroundColor(item.tagStyle.textColor)
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .padding(.vertical, DesignSystem.Spacing.xs)
                    .background(item.tagStyle.backgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
            }
            
            // Content
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text(item.title)
                    .font(.system(size: DesignSystem.Typography.headingSmall, weight: DesignSystem.Typography.bold))
                    .foregroundColor(DesignSystem.Colors.gray900)
                    .lineLimit(2)
                
                Text(item.description)
                    .font(.system(size: DesignSystem.Typography.bodyMedium, weight: DesignSystem.Typography.regular))
                    .foregroundColor(DesignSystem.Colors.gray600)
                    .lineLimit(3)
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
        .shadow(color: DesignSystem.Shadow.small, radius: 8, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                .stroke(DesignSystem.Colors.gray100, lineWidth: 1)
        )
    }
}

#Preview {
    ContentGrid(items: ContentItem.sampleData)
        .background(DesignSystem.Colors.gray50)
}