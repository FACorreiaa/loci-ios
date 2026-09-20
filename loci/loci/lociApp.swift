//
//  lociApp.swift
//  loci
//
//  Created by Fernando Correia Chill on 18/09/2026.
//

import SwiftData
import SwiftUI

@main struct lociApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @State private var isAuthenticated: Bool = false
  @State private var isCheckingAuth: Bool = true

  var sharedModelContainer: ModelContainer = {
    let schema = Schema([Item.self])
    let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

    do { return try ModelContainer(for: schema, configurations: [modelConfiguration]) } catch {
      fatalError("Could not create ModelContainer: \(error)")
    }
  }()

  var body: some Scene {
    WindowGroup {
      Group {
        if isCheckingAuth {
          ZStack {
            Color.lociPaper.ignoresSafeArea()
            ProgressView()
          }
        } else if isAuthenticated {
          MainTabView(onSignOut: { withAnimation { isAuthenticated = false } })
        } else {
          LoginScreen(onAuthenticated: { withAnimation { isAuthenticated = true } })
        }
      }.task {
        let restored = await AuthSessionManager.shared.restoreSessionIfNeeded()
        withAnimation {
          isAuthenticated = restored
          isCheckingAuth = false
        }
      }.onReceive(NotificationCenter.default.publisher(for: .authSessionDidAuthenticate)) { _ in
        withAnimation {
          isAuthenticated = true
          isCheckingAuth = false
        }
      }.onReceive(NotificationCenter.default.publisher(for: .authSessionDidInvalidate)) { _ in
        withAnimation {
          isAuthenticated = false
          isCheckingAuth = false
        }
      }.onOpenURL { url in NotificationCenter.default.post(name: NSNotification.Name("LociOpenURLNotification"), object: url) }
    }.modelContainer(sharedModelContainer)
  }
}
