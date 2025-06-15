import SwiftUI

// MARK: - Data Models for Landing Page
struct HeroData {
    let title: String
    let highlightedWord: String
    let subtitle: String
    let placeholder: String
    let suggestions: [SearchSuggestion]
}

struct SearchSuggestion {
    let icon: String // SF Symbol name
    let text: String
}

struct StatsData {
    let badgeText: String
    let items: [StatItem]
}

struct StatItem {
    let value: String
    let label: String
}

struct ContentItem {
    let emoji: String
    let title: String
    let description: String
    let tag: String
    let tagStyle: TagStyle
}

enum TagStyle {
    case blue
    case purple
    case amber
    
    var backgroundColor: Color {
        switch self {
        case .blue: return DesignSystem.Colors.tagBlue
        case .purple: return DesignSystem.Colors.tagPurple
        case .amber: return DesignSystem.Colors.tagAmber
        }
    }
    
    var textColor: Color {
        switch self {
        case .blue: return DesignSystem.Colors.tagBlueText
        case .purple: return DesignSystem.Colors.tagPurpleText
        case .amber: return DesignSystem.Colors.tagAmberText
        }
    }
}

// MARK: - Sample Data
extension HeroData {
    static let sample = HeroData(
        title: "Discover your next adventure,",
        highlightedWord: "smarter",
        subtitle: "Tired of generic city guides? Loci creates hyper-personalized travel plans based on your unique interests and real-time context.",
        placeholder: "Where to? e.g., 'art museums in Paris'",
        suggestions: [
            SearchSuggestion(icon: "building.columns", text: "Historical sites in Rome"),
            SearchSuggestion(icon: "fork.knife", text: "Best ramen in Tokyo"),
            SearchSuggestion(icon: "sparkles", text: "Hidden gems in Lisbon"),
            SearchSuggestion(icon: "map", text: "3-hour art walk in Florence")
        ]
    )
}

extension StatsData {
    static let sample = StatsData(
        badgeText: "This month on Loci",
        items: [
            StatItem(value: "69,420", label: "Users registered"),
            StatItem(value: "12,109", label: "Personalized Itineraries Created"),
            StatItem(value: "41,004", label: "Unique Points of Interest")
        ]
    )
}

extension ContentItem {
    static let sampleData: [ContentItem] = [
        ContentItem(
            emoji: "🗺️",
            title: "New in Paris: Hidden Gems",
            description: "Our AI has uncovered 15 new unique spots in Le Marais, from artisan shops to quiet courtyards.",
            tag: "New Itinerary",
            tagStyle: .blue
        ),
        ContentItem(
            emoji: "🤖",
            title: "AI-Curated: A Foodie's Weekend in Lisbon",
            description: "From classic Pastéis de Nata to modern seafood, let our AI guide your taste buds through Lisbon's best.",
            tag: "AI-Powered",
            tagStyle: .purple
        ),
        ContentItem(
            emoji: "⭐️",
            title: "User Favorite: The Ancient Rome Route",
            description: "Explore the Colosseum, Forum, and Palatine Hill with a personalized route optimized for a 4-hour window.",
            tag: "Top Rated",
            tagStyle: .amber
        )
    ]
}