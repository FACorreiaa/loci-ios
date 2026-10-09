import LociConnectProto
import SwiftUI

public struct CalendarConnectionsView: View {
  @State private var appleOn: Bool = AppleCalendar.shared.isAuthorized
  @State private var googleLabel: String?
  @State private var calendlyLabel: String?
  @State private var googleID: String?
  @State private var calendlyID: String?
  @State private var message: String?
  @State private var busy = false
  @Environment(\.openURL) private var openURL

  public var body: some View {
    List {
      Section {
        // Calendar access can't be revoked from inside the app; once it's on,
        // the row sends the user to Loci's page in Settings instead.
        row(
          title: "Apple Calendar",
          subtitle: appleOn ? "This iPhone" : "Events on this iPhone",
          connected: appleOn,
          connectedAction: "Manage in Settings"
        ) {
          if appleOn {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
          } else {
            Task { await connectApple() }
          }
        }
        row(title: "Google Calendar", subtitle: googleLabel ?? "Read events and add Loci trips", connected: googleLabel != nil) {
          Task { await toggle(.google) }
        }
        row(title: "Calendly", subtitle: calendlyLabel ?? "Show booked meetings", connected: calendlyLabel != nil) {
          Task { await toggle(.calendly) }
        }
      }
      TripCalendarFeedSection()
      if let message {
        Section { Text(message).font(.footnote).foregroundStyle(Color.lociInk.opacity(0.7)) }
      }
    }.navigationTitle("Calendars").scrollContentBackground(.hidden).background { Color.lociPaper.ignoresSafeArea() }
      .task { await refresh() }
  }

  private func row(
    title: String,
    subtitle: String,
    connected: Bool,
    connectedAction: String = "Disconnect",
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(title).foregroundStyle(Color.lociInk)
          Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        if connected {
          Text(connectedAction).foregroundStyle(.secondary)
        } else {
          Text("Connect").foregroundStyle(Color.lociCoral)
        }
      }
    }.disabled(busy)
  }

  private func refresh() async {
    do {
      let conns = try await CalendarConnectService.shared.listConnections()
      googleLabel = conns.first(where: { $0.provider == .google })?.accountLabel
      googleID = conns.first(where: { $0.provider == .google })?.id
      calendlyLabel = conns.first(where: { $0.provider == .calendly })?.accountLabel
      calendlyID = conns.first(where: { $0.provider == .calendly })?.id
    } catch {
      message = error.localizedDescription
    }
  }

  private func connectApple() async {
    do {
      appleOn = try await AppleCalendar.shared.requestAccess()
      message = appleOn ? "Apple Calendar is connected." : "Calendar access was not granted."
    } catch {
      message = error.localizedDescription
    }
  }

  private func toggle(_ provider: Loci_Calendar_CalendarProvider) async {
    busy = true
    defer { busy = false }
    do {
      if provider == .google, let id = googleID {
        try await CalendarConnectService.shared.disconnect(id: id)
      } else if provider == .calendly, let id = calendlyID {
        try await CalendarConnectService.shared.disconnect(id: id)
      } else {
        try await CalendarConnectService.shared.connect(provider)
      }
      await refresh()
    } catch {
      if (error as? APIError) == .cancelled { return }
      message = error.localizedDescription
    }
  }
}
