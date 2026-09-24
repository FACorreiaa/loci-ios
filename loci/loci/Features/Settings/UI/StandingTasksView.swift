import LociConnectProto
import Observation
import SwiftProtobuf
import SwiftUI

/// The caller's standing tasks (WatchService.ListWatches / DeleteWatch).
@MainActor @Observable final class StandingTasksStore {
  private(set) var watches: [Loci_Chat_Watch]?
  var error: String?

  private let service: StandingTaskService

  init(service: StandingTaskService = ConnectStandingTaskService(), watches: [Loci_Chat_Watch]? = nil) {
    self.service = service
    self.watches = watches
  }

  func load() async {
    do throws(WatchError) {
      watches = try await service.list(sessionId: nil)
    } catch {
      if watches == nil { watches = [] }
      self.error = error.errorDescription
    }
  }

  /// Stop one. Already gone on the server counts as done.
  func delete(_ watch: Loci_Chat_Watch) async {
    do throws(WatchError) {
      try await service.delete(id: watch.id)
      watches?.removeAll { $0.id == watch.id }
    } catch .notFound {
      watches?.removeAll { $0.id == watch.id }
    } catch {
      self.error = error.errorDescription
    }
  }
}

/// Settings › Standing tasks: what Loci is keeping an eye on, and a way to stop each one.
struct StandingTasksView: View {
  @State var store = StandingTasksStore()

  var body: some View {
    List {
      if let watches = store.watches {
        if watches.isEmpty {
          ContentUnavailableView {
            Label("No standing tasks", systemImage: "clock.arrow.circlepath")
          } description: {
            Text("In a conversation, ask Loci something like “every morning at 8, tell me if it'll rain in Lisbon”.")
          }
          .listRowBackground(Color.clear)
        } else {
          Section {
            ForEach(watches, id: \.id) { watch in
              StandingTaskRow(watch: watch)
                .swipeActions {
                  Button("Stop", role: .destructive) { Task { await store.delete(watch) } }
                }
            }
          } footer: {
            Text("Swipe left to stop one. Up to 10 at a time.")
          }
          .listRowBackground(Color.lociCard)
        }
      } else {
        ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
      }
    }
    .settingsStyle("Standing tasks")
    .refreshable { await store.load() }
    .errorAlert($store.error)
    .task { if store.watches == nil { await store.load() } }
  }
}

private struct StandingTaskRow: View {
  let watch: Loci_Chat_Watch

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(watch.title).font(.lociHeadline(16)).foregroundStyle(Color.lociInk)
      Label(watch.scheduleHuman, systemImage: "clock").font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk)
      if !watch.spec.isEmpty {
        Text(watch.spec).font(.lociBody(14)).foregroundStyle(Color.lociInk).lineLimit(2)
      }
      if watch.hasNextRunAt, watch.enabled {
        Text("Next run \(watch.nextRunAt.date, format: .relative(presentation: .named))").lociCoordStyle(10)
      } else if !watch.enabled {
        Text("Paused").lociCoordStyle(10)
      }
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
  }
}
