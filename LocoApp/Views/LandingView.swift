import SwiftUI

struct LandingView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero Section with gradient background
                HeroSection(data: HeroData.sample)
                    .background(LinearGradient.heroGradient)
                
                // Stats Section
                StatsSection(data: StatsData.sample)
                    .background(DesignSystem.Colors.backgroundPrimary)
                
                // Content Grid
                ContentGrid(items: ContentItem.sampleData)
                    .background(DesignSystem.Colors.gray50)
                
                // Mobile App Announcement
                MobileAppAnnouncement()
                    .background(DesignSystem.Colors.backgroundPrimary)
                
                // CTA Section
                CTASection()
                    .background(DesignSystem.Colors.backgroundPrimary)
                
                // Footer spacer
                Spacer(minLength: DesignSystem.Spacing.xl)
            }
        }
        .background(DesignSystem.Colors.backgroundPrimary)
        .ignoresSafeArea(edges: .top)
    }
}

#Preview {
    LandingView()
}