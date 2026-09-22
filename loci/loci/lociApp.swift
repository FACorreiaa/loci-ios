//
//  lociApp.swift
//  loci
//
//  Created by Fernando Correia Chill on 18/09/2026.
//

import SwiftUI

@main struct lociApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @State private var isAuthenticated: Bool = false
  @State private var isCheckingAuth: Bool = true

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
      }.onOpenURL { url in AppRouter.shared.open(url) }
    }
  }
}
