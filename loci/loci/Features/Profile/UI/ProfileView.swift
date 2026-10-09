import SwiftUI

public struct ProfileView: View {
  @State private var isSigningOut: Bool = false
  @State private var linked: AppLink?
  private let router = AppRouter.shared
  public var onSignOut: () -> Void = {}

  public init(onSignOut: @escaping () -> Void = {}) { self.onSignOut = onSignOut }

  public var body: some View {
    NavigationStack {
      List {
        Section {
          HStack(spacing: 16) {
            Image(decorative: "LociMascot").resizable().scaledToFit().frame(width: 56, height: 56).background(Color.lociSage.opacity(0.3)).clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
              Text(AuthSessionManager.shared.currentUsername ?? "Traveler").font(.headline.weight(.bold)).foregroundStyle(Color.lociInk)
              ProgressSummaryLine()
            }
          }.padding(.vertical, 8)
        }.listRowBackground(Color.lociCard)

        YouSection()

        Section {
          NavigationLink(value: AppRoute.settings) {
            Label("Settings", systemImage: "gearshape")
          }
        }.listRowBackground(Color.lociCard)

        Section("About") {
          HStack {
            Text("Version")
            Spacer()
            Text(Self.versionText).foregroundStyle(.secondary)
          }
          ExternalLinkRow(title: "Loci Web", destination: URL(string: "https://lociai.fyi")!)
          // Hidden until the app has an App Store ID (Info.plist `AppStoreID`).
          if let reviewURL = AppConfig.shared.writeReviewURL {
            ExternalLinkRow(title: "Rate Loci on the App Store", destination: reviewURL)
          }
        }.listRowBackground(Color.lociCard)

        Section {
          Button(role: .destructive) {
            signOut()
          } label: {
            HStack {
              Spacer()
              if isSigningOut {
                ProgressView().accessibilityLabel("Signing out")
              } else {
                Text("Sign Out").fontWeight(.semibold)
              }
              Spacer()
            }
          }
          .disabled(isSigningOut)
        }.listRowBackground(Color.lociCard)
      }.listStyle(.insetGrouped).scrollContentBackground(.hidden).background(Color.lociPaper.ignoresSafeArea()).navigationTitle("Profile")
        .appRouteDestinations()
        .navigationDestination(item: $linked) { AppLinkDestination(link: $0) }
        .onAppear(perform: openPending)
        .onChange(of: router.pendingLink) { openPending() }
    }
  }

  /// `/recents`, `/contribute` and the social links land here (`AppRouter.tab(for:)`).
  private func openPending() {
    if let link = router.takeLink(for: .profile) { linked = link }
  }

  private func signOut() {
    isSigningOut = true
    Task {
      await AuthService.shared.logout()
      isSigningOut = false
      onSignOut()
    }
  }

  /// "1.2 (34)", from the bundle so it never drifts from the build.
  private static var versionText: String {
    let info = Bundle.main.infoDictionary
    let version = info?["CFBundleShortVersionString"] as? String ?? "—"
    guard let build = info?["CFBundleVersion"] as? String else { return version }
    return "\(version) (\(build))"
  }
}

/// A row that leaves the app: title, then the outward arrow.
struct ExternalLinkRow: View {
  let title: String
  let destination: URL

  var body: some View {
    Link(destination: destination) {
      HStack {
        Text(title)
        Spacer()
        Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
      }
    }
  }
}
