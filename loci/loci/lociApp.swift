//
//  lociApp.swift
//  loci
//
//  Created by Fernando Correia Chill on 18/09/2026.
//

import GoogleSignIn
import SwiftUI

@main struct lociApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @State private var isAuthenticated: Bool = false
  @State private var isCheckingAuth: Bool = true
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      Group {
        if let preview = DesignPreview.requested {
          preview.body
        } else if isCheckingAuth {
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
      }.onOpenURL { url in
        // The Google SDK's redirect (the reversed client ID scheme) is its own;
        // everything else is a Loci deep link.
        if GIDSignIn.sharedInstance.handle(url) { return }
        AppRouter.shared.open(url)
      }
        .onChange(of: scenePhase) { _, phase in
          switch phase {
          case .background: SearchSessionController.shared.sceneDidEnterBackground()
          case .active: SearchSessionController.shared.sceneDidBecomeActive()
          default: break
          }
        }
    }
  }
}
