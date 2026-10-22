import LociConnectProto
import SwiftUI

/// Someone's followers, or who they follow (web: the profile's counts). The
/// server answers PermissionDenied for a private account the caller may not see.
struct FollowListView: View {
  let userID: String
  let name: String
  let followers: Bool

  @State private var rows: [FollowRow]?
  @State private var nextPageToken = ""
  @State private var failure: String?

  var body: some View {
    List {
      Section {
        if let failure {
          Text(failure).font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
        } else if let rows {
          if rows.isEmpty {
            Text(followers ? "No followers yet." : "Not following anyone yet.").font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
          }
          ForEach(Binding(get: { self.rows ?? [] }, set: { self.rows = $0 })) { $row in
            FollowRowView(row: $row, via: "list")
              .onAppear { if row.id == rows.last?.id { Task { await loadMore() } } }
          }
        } else {
          ProgressView().frame(maxWidth: .infinity)
        }
      }
      .listRowBackground(Color.lociCard)
    }
    .settingsStyle(followers ? "\(name)'s followers" : "\(name) follows")
    .refreshable { await load() }
    .task { await load() }
  }

  private func page(_ token: String) async throws -> Loci_Social_ListFollowsResponse {
    followers ? try await SocialAPI.followers(userID: userID, pageToken: token) : try await SocialAPI.following(userID: userID, pageToken: token)
  }

  private func load() async {
    do {
      let first = try await page("")
      rows = first.entries.map(FollowRow.init)
      nextPageToken = first.nextPageToken
      failure = nil
    } catch {
      guard !error.isCancellation else { return }
      failure = error.userMessage
    }
  }

  private func loadMore() async {
    guard !nextPageToken.isEmpty else { return }
    let token = nextPageToken
    nextPageToken = ""
    do {
      let next = try await page(token)
      let known = Set((rows ?? []).map(\.id))
      rows = (rows ?? []) + next.entries.map(FollowRow.init).filter { !known.contains($0.id) }
      nextPageToken = next.nextPageToken
    } catch {
      nextPageToken = token
    }
  }
}
