import Foundation
import LociConnectProto
import SwiftUI

/// What the person is looking at, for the assistant.
///
/// `screen` is an open vocabulary the server reads as a hint. Every id is
/// re-checked against the caller before the server reads it, so a wrong one
/// costs a hint and nothing else. Only the kinds the server resolves are sent:
/// trip, place and list. `city` is the place the screen is about, if it has one.
nonisolated struct AskLociScreen: Equatable, Sendable {
  var screen: String
  var city: String?
  var trips: [String] = []
  var places: [String] = []
  var lists: [String] = []

  var entities: [Loci_Assistant_ContextEntity] {
    func entities(_ ids: [String], _ type: Loci_Assistant_ContextEntityType) -> [Loci_Assistant_ContextEntity] {
      // Only a stored id means anything: a place from a fresh answer has a name-keyed one.
      ids.filter { UUID(uuidString: $0) != nil }.map { id in
        var entity = Loci_Assistant_ContextEntity()
        entity.type = type
        entity.id = id
        return entity
      }
    }
    return entities(trips, .trip) + entities(places, .poi) + entities(lists, .list)
  }
}

/// The screens now on show, newest last. Falls back to the selected tab, since
/// most tab roots need nothing more than their name.
@MainActor
final class AppContextStore {
  static let shared = AppContextStore()

  private var visible: [(token: UUID, screen: AskLociScreen)] = []

  func show(_ screen: AskLociScreen, token: UUID) {
    if let index = visible.firstIndex(where: { $0.token == token }) {
      visible[index].screen = screen
    } else {
      visible.append((token, screen))
    }
  }

  func hide(token: UUID) {
    visible.removeAll { $0.token == token }
  }

  func current(tab: AppRouter.Tab) -> AskLociScreen {
    visible.last?.screen ?? AskLociScreen(screen: Self.name(of: tab))
  }

  private static func name(of tab: AppRouter.Tab) -> String {
    switch tab {
    case .discover: "discover"
    case .calendar: "calendar"
    case .assistant: "chat"
    case .saved: "saved"
    case .profile: "profile"
    }
  }
}

private struct AskLociContextModifier: ViewModifier {
  let screen: AskLociScreen
  @State private var token = UUID()

  func body(content: Content) -> some View {
    content
      .onAppear { AppContextStore.shared.show(screen, token: token) }
      .onDisappear { AppContextStore.shared.hide(token: token) }
      .onChange(of: screen) { _, new in AppContextStore.shared.show(new, token: token) }
  }
}

extension View {
  /// Tells the assistant this screen is what the person is looking at.
  func askLociContext(_ screen: AskLociScreen) -> some View {
    modifier(AskLociContextModifier(screen: screen))
  }
}
