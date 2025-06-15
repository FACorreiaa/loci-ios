# Loci iOS App

A SwiftUI iOS application that mirrors the landing page design of the Loci web application, following Crunchbase's design patterns.

## Features

- **Modern SwiftUI Architecture**: Built with the latest SwiftUI patterns and iOS 17+ features
- **Design System**: Comprehensive design system inspired by Crunchbase's professional aesthetic
- **Responsive Design**: Optimized for both iPhone and iPad
- **Component-Based Architecture**: Modular, reusable components for maintainable code

## Design Philosophy

### Color Scheme
- Primary Blue: `#146aff` (matching Crunchbase)
- Gradient colors from blue to purple
- Professional neutral grays
- Accessibility-compliant contrast ratios

### Typography
- System fonts with multiple weights (300, 400, 500, 700)
- Responsive font sizes
- Consistent spacing and hierarchy

### Layout Patterns
- 8px grid-based spacing system
- Card-based UI with rounded corners
- Consistent padding and margins
- Responsive breakpoints

## Project Structure

```
LocoApp/
├── LocoApp.swift              # Main app entry point
├── Views/
│   └── LandingView.swift      # Main landing page view
├── Components/
│   ├── HeroSection.swift      # Hero section with search
│   ├── StatsSection.swift     # Statistics display
│   ├── ContentGrid.swift      # Content cards grid
│   ├── MobileAppAnnouncement.swift  # App download section
│   └── CTASection.swift       # Call-to-action section
├── Models/
│   └── LandingData.swift      # Data models and sample data
├── Utils/
│   └── DesignSystem.swift     # Design system constants
└── Assets.xcassets/           # App icons and colors
```

## Key Components

### Hero Section
- Gradient text treatment for "smarter"
- Interactive search bar with placeholder text
- Search suggestions with SF Symbols icons
- Responsive layout for different screen sizes

### Stats Section
- Badge-style header
- Grid layout for statistics
- Large numbers with descriptive labels
- Clean, minimal presentation

### Content Grid
- Card-based layout
- Emoji icons for visual interest
- Color-coded tags (blue, purple, amber)
- Consistent spacing and shadows

### Mobile App Announcement
- Gradient icon background
- App Store and Google Play download buttons
- Professional button styling

### CTA Section
- Gradient background
- Primary and secondary button styles
- Clear hierarchy and spacing

## Design System

The app uses a comprehensive design system (`DesignSystem.swift`) that includes:

- **Colors**: Primary, secondary, neutral, and semantic colors
- **Typography**: Font sizes and weights with semantic names
- **Spacing**: Consistent spacing scale (4px - 64px)
- **Corner Radius**: Standardized border radius values
- **Shadows**: Consistent shadow styling

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+

## Getting Started

1. Open `LocoApp.xcodeproj` in Xcode
2. Select your target device or simulator
3. Build and run the project (⌘+R)

## Preview Support

All components include SwiftUI preview support for rapid development and testing.

## Future Enhancements

- Navigation to additional screens
- API integration with the Go backend
- User authentication
- Personalized content
- Interactive map integration
- Offline support# loci-ios
