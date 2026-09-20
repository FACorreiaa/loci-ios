import SwiftUI

public struct ProfileView: View {
    @State private var isSigningOut: Bool = false
    public var onSignOut: () -> Void = {}

    public init(onSignOut: @escaping () -> Void = {}) {
        self.onSignOut = onSignOut
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        Image("LociMascot")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 56, height: 56)
                            .background(Color.lociSage.opacity(0.3))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(AuthSessionManager.shared.currentUsername ?? "Traveler")
                                .font(.headline.weight(.bold))
                                .foregroundColor(.lociInk)
                            Text("Loci Explorer")
                                .font(.subheadline)
                                .foregroundColor(.lociCoral)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.lociCard)

                Section("Preferences") {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("Notifications", systemImage: "bell.badge")
                    }

                    NavigationLink {
                        Text("Offline data caching options.")
                            .padding()
                    } label: {
                        Label("Offline Storage", systemImage: "arrow.down.circle")
                    }
                }
                .listRowBackground(Color.lociCard)

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0 (Beta)")
                            .foregroundColor(.secondary)
                    }
                    Link(destination: URL(string: "https://loci.travel")!) {
                        HStack {
                            Text("Loci Web")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .listRowBackground(Color.lociCard)

                Section {
                    Button(role: .destructive) {
                        signOut()
                    } label: {
                        HStack {
                            Spacer()
                            if isSigningOut {
                                ProgressView()
                            } else {
                                Text("Sign Out")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                }
                .listRowBackground(Color.lociCard)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.lociPaper.ignoresSafeArea())
            .navigationTitle("Profile")
        }
    }

    private func signOut() {
        isSigningOut = true
        Task {
            await AuthService.shared.logout()
            await MainActor.run {
                isSigningOut = false
                onSignOut()
            }
        }
    }
}
