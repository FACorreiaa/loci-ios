import SwiftUI

// MARK: - Design System inspired by Crunchbase and matching the web app
struct DesignSystem {
    
    // MARK: - Colors
    struct Colors {
        // Primary colors matching Crunchbase style
        static let primary = Color(red: 0.08, green: 0.42, blue: 1.0) // #146aff
        static let primaryDark = Color(red: 0.02, green: 0.24, blue: 1.0) // #063cff
        
        // Gradient colors
        static let gradientBlue = Color(red: 0.08, green: 0.42, blue: 1.0)
        static let gradientPurple = Color(red: 0.50, green: 0.35, blue: 0.98) // #8059fa
        
        // Neutral colors
        static let gray900 = Color(red: 0.16, green: 0.16, blue: 0.16) // #282828
        static let gray600 = Color(red: 0.40, green: 0.40, blue: 0.40) // #666
        static let gray500 = Color(red: 0.45, green: 0.45, blue: 0.45) // #737373
        static let gray100 = Color(red: 0.96, green: 0.96, blue: 0.96)
        static let gray50 = Color(red: 0.98, green: 0.98, blue: 0.98)
        
        // Background colors
        static let backgroundPrimary = Color.white
        static let backgroundSecondary = Color(red: 0.96, green: 0.98, blue: 1.0) // blue-50
        static let backgroundPurple = Color(red: 0.98, green: 0.96, blue: 1.0) // purple-50
        
        // Tag colors
        static let tagBlue = Color(red: 0.86, green: 0.93, blue: 1.0) // blue-100
        static let tagBlueText = Color(red: 0.12, green: 0.35, blue: 0.72) // blue-800
        static let tagPurple = Color(red: 0.93, green: 0.86, blue: 1.0) // purple-100
        static let tagPurpleText = Color(red: 0.42, green: 0.16, blue: 0.80) // purple-800
        static let tagAmber = Color(red: 1.0, green: 0.95, blue: 0.86) // amber-100
        static let tagAmberText = Color(red: 0.78, green: 0.45, blue: 0.09) // amber-800
    }
    
    // MARK: - Typography
    struct Typography {
        // Font sizes
        static let displayLarge: CGFloat = 48
        static let displayMedium: CGFloat = 36
        static let headingLarge: CGFloat = 32
        static let headingMedium: CGFloat = 24
        static let headingSmall: CGFloat = 20
        static let bodyLarge: CGFloat = 18
        static let bodyMedium: CGFloat = 16
        static let bodySmall: CGFloat = 14
        static let caption: CGFloat = 12
        
        // Font weights
        static let light: Font.Weight = .light // 300
        static let regular: Font.Weight = .regular // 400
        static let medium: Font.Weight = .medium // 500
        static let bold: Font.Weight = .bold // 700
    }
    
    // MARK: - Spacing
    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        static let xxxl: CGFloat = 64
    }
    
    // MARK: - Corner Radius
    struct CornerRadius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xLarge: CGFloat = 24
    }
    
    // MARK: - Shadows
    struct Shadow {
        static let small = Color.black.opacity(0.08)
        static let medium = Color.black.opacity(0.12)
        static let large = Color.black.opacity(0.16)
    }
}

// MARK: - Custom Gradients
extension LinearGradient {
    static let heroGradient = LinearGradient(
        colors: [
            DesignSystem.Colors.backgroundSecondary,
            DesignSystem.Colors.backgroundPurple,
            DesignSystem.Colors.backgroundPrimary
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    
    static let textGradient = LinearGradient(
        colors: [
            DesignSystem.Colors.gradientBlue,
            DesignSystem.Colors.gradientPurple
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
}