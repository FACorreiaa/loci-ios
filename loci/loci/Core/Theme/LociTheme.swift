import SwiftUI

public enum LociTheme {
    // MARK: - Spacing & Corner Radius
    public static let cornerRadius: CGFloat = 12.8
    public static let cornerRadiusHero: CGFloat = 14.4
    public static let borderWidth: CGFloat = 1.0
    public static let defaultPadding: CGFloat = 16.0

    // MARK: - Motion
    public static let defaultSpring = Animation.spring(response: 0.35, dampingFraction: 0.86)
}

public extension Color {
    // MARK: - Brand Core Colors
    static let lociCoral = Color("AccentColor") // Primary brand coral (#FA7862)
    static let lociPaper = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.063, green: 0.102, blue: 0.086, alpha: 1.0) // #101A16
            : UIColor(red: 0.992, green: 0.961, blue: 0.918, alpha: 1.0) // #FDF5EA
    })
    static let lociInk = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.929, green: 0.910, blue: 0.863, alpha: 1.0) // #EDE8DC
            : UIColor(red: 0.196, green: 0.231, blue: 0.259, alpha: 1.0) // #323B42
    })
    static let lociForest = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.659, green: 0.722, blue: 0.588, alpha: 1.0) // #A8B896
            : UIColor(red: 0.129, green: 0.302, blue: 0.235, alpha: 1.0) // #214D3C
    })
    static let lociSage = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.220, green: 0.282, blue: 0.251, alpha: 1.0) // #384840
            : UIColor(red: 0.847, green: 0.878, blue: 0.816, alpha: 1.0) // #D8E0D0
    })
    static let lociCard = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.086, green: 0.125, blue: 0.098, alpha: 1.0) // #162019
            : UIColor(red: 0.992, green: 0.984, blue: 0.969, alpha: 1.0) // #FDFBF7
    })
    static let lociBorder = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.220, green: 0.282, blue: 0.251, alpha: 1.0) // #384840
            : UIColor(red: 0.812, green: 0.773, blue: 0.710, alpha: 1.0) // #CFC5B5
    })
    static let lociMuted = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.122, green: 0.161, blue: 0.137, alpha: 1.0)
            : UIColor(red: 0.910, green: 0.886, blue: 0.839, alpha: 1.0) // #E8E2D6
    })
}
