import SwiftUI

struct HeroSection: View {
    let data: HeroData
    @State private var searchText = ""
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            // Title with gradient text
            VStack(spacing: DesignSystem.Spacing.md) {
                HStack {
                    Text(data.title)
                        .font(.system(size: DesignSystem.Typography.displayLarge, weight: DesignSystem.Typography.bold))
                        .foregroundColor(DesignSystem.Colors.gray900)
                    +
                    Text(" \(data.highlightedWord)")
                        .font(.system(size: DesignSystem.Typography.displayLarge, weight: DesignSystem.Typography.bold))
                        .foregroundStyle(LinearGradient.textGradient)
                }
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                
                Text(data.subtitle)
                    .font(.system(size: DesignSystem.Typography.bodyLarge, weight: DesignSystem.Typography.regular))
                    .foregroundColor(DesignSystem.Colors.gray600)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .padding(.horizontal, DesignSystem.Spacing.md)
            }
            
            // Search bar
            VStack(spacing: DesignSystem.Spacing.md) {
                searchBar
                searchSuggestions
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.top, DesignSystem.Spacing.xxxl)
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(DesignSystem.Colors.gray500)
                .font(.system(size: DesignSystem.Typography.bodyMedium))
            
            TextField(data.placeholder, text: $searchText)
                .font(.system(size: DesignSystem.Typography.bodyMedium, weight: DesignSystem.Typography.regular))
                .foregroundColor(DesignSystem.Colors.gray900)
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.backgroundPrimary)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .stroke(DesignSystem.Colors.gray100, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        .shadow(color: DesignSystem.Shadow.small, radius: 4, x: 0, y: 2)
    }
    
    private var searchSuggestions: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: DesignSystem.Spacing.sm) {
            ForEach(data.suggestions.indices, id: \.self) { index in
                let suggestion = data.suggestions[index]
                
                Button(action: {
                    searchText = suggestion.text
                }) {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: suggestion.icon)
                            .font(.system(size: DesignSystem.Typography.bodySmall))
                            .foregroundColor(DesignSystem.Colors.gray500)
                        
                        Text(suggestion.text)
                            .font(.system(size: DesignSystem.Typography.bodySmall, weight: DesignSystem.Typography.regular))
                            .foregroundColor(DesignSystem.Colors.gray600)
                            .lineLimit(1)
                        
                        Spacer()
                    }
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .padding(.vertical, DesignSystem.Spacing.xs)
                    .background(DesignSystem.Colors.gray50)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

#Preview {
    HeroSection(data: HeroData.sample)
        .background(LinearGradient.heroGradient)
}