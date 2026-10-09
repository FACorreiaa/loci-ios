import LociConnectProto
import SwiftProtobuf
import SwiftUI

/// Something from Saved that can go on a post.
struct BoardAttachmentChoice: Identifiable, Equatable {
  let kind: Loci_Boards_V1_AttachmentKind
  let ref: String
  let title: String
  let city: String
  var id: String { "\(kind.rawValue):\(ref)" }
}

nonisolated extension BoardsModel {
  /// A favourite can be attached when it is a real POI: hotels and restaurants
  /// live elsewhere, and older rows keep a display name instead of an id.
  static func attachable(_ item: Loci_Favorites_V1_FavoriteItem) -> Bool {
    item.contentType != .hotel && item.contentType != .restaurant && item.contentType != .itinerary
      && UUID(uuidString: item.itemID.trimmingCharacters(in: .whitespaces)) != nil
  }
}

/// Post to a board (web: /boards/:slug/submit): a title, and any of a link,
/// some text and a Loci item from Saved.
struct ComposePostSheet: View {
  let boardSlug: String
  let boardName: String
  let service: BoardsService
  let onPosted: (Loci_Boards_V1_Post) -> Void

  @State private var title = ""
  @State private var link = ""
  @State private var text = ""
  @State private var attachment: BoardAttachmentChoice?
  @State private var choices: [BoardAttachmentChoice] = []
  @State private var loadingChoices = false
  @State private var sending = false
  @State private var error: String?
  @Environment(\.dismiss) private var dismiss

  private var trimmedLink: String { link.trimmingCharacters(in: .whitespaces) }
  private var linkOK: Bool { trimmedLink.isEmpty || BoardsModel.isLink(trimmedLink) }
  private var canPost: Bool { title.trimmingCharacters(in: .whitespaces).count >= 3 && linkOK && !sending }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Three days in Porto without a car", text: $title, axis: .vertical).lineLimit(1...3).onChange(of: title) { _, v in
            if v.count > 200 { title = String(v.prefix(200)) }
          }
        } header: {
          Text("Title")
        }
        Section {
          TextField("https://", text: $link).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
        } header: {
          Text("Link (optional)")
        } footer: {
          if !linkOK { Text("Use a full http:// or https:// address.").foregroundStyle(Color.lociDestructive) }
        }
        Section("Text (optional)") {
          TextField("What happened, what you'd tell a friend", text: $text, axis: .vertical).lineLimit(4...12).onChange(of: text) { _, v in
            if v.count > 10_000 { text = String(v.prefix(10_000)) }
          }
        }
        Section {
          if let attachment {
            HStack {
              Label(
                attachment.title,
                systemImage: attachment.kind == .itinerary ? "point.topleft.down.to.point.bottomright.curvepath" : "mappin.and.ellipse"
              )
              Spacer()
              Button("Remove", role: .destructive) { self.attachment = nil }.font(.lociCaption(13))
            }
          } else if loadingChoices {
            ProgressView()
          } else if choices.isEmpty {
            Text("Nothing to attach yet. Save an itinerary or a place first.").foregroundStyle(Color.lociMutedInk)
          } else {
            Menu {
              ForEach(choices) { choice in Button(choice.city.isEmpty ? choice.title : "\(choice.title) · \(choice.city)") { attachment = choice } }
            } label: {
              Label("Attach something from Saved", systemImage: "paperclip")
            }
          }
        } header: {
          Text("Loci item (optional)")
        }
      }.navigationTitle("Post to \(boardName)").navigationBarTitleDisplayMode(.inline).toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) { Button("Post") { Task { await post() } }.disabled(!canPost) }
      }.task { await loadChoices() }.errorAlert($error)
    }
  }

  private func post() async {
    sending = true
    defer { sending = false }
    var request = Loci_Boards_V1_CreatePostRequest()
    request.boardSlug = boardSlug
    request.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    request.url = trimmedLink
    request.body = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let attachment {
      var input = Loci_Boards_V1_AttachmentInput()
      input.kind = attachment.kind
      input.ref = attachment.ref
      request.attachment = input
    }
    do {
      let post = try await service.createPost(request)
      onPosted(post)
      dismiss()
    } catch { self.error = error.userMessage }
  }

  /// Account itineraries and POI favourites. A failure only empties the menu:
  /// attaching is optional.
  private func loadChoices() async {
    loadingChoices = true
    defer { loadingChoices = false }
    var itineraries = Loci_Itinerary_GetUserItinerariesRequest()
    itineraries.pagination.page = 1
    itineraries.pagination.pageSize = 100
    var favorites = Loci_Favorites_V1_GetFavoritesRequest()
    favorites.userID = AuthSessionManager.shared.currentUserID ?? "me"
    favorites.limit = 1000
    let sentItineraries = itineraries
    let sentFavorites = favorites
    async let saved = try? rpc("", sentItineraries) { await SavedAPI.itineraries.getUserItineraries(request: $0, headers: [:]) }
    async let places = try? rpc("", sentFavorites) { await SavedAPI.favorites.getFavorites(request: $0, headers: [:]) }
    let routeChoices =
      (await saved)?.itineraries.map {
        BoardAttachmentChoice(kind: .itinerary, ref: $0.id, title: $0.title.isEmpty ? "Untitled" : $0.title, city: "")
      } ?? []
    let placeChoices =
      (await places)?.favorites.filter(BoardsModel.attachable).map {
        BoardAttachmentChoice(kind: .poi, ref: $0.itemID.trimmingCharacters(in: .whitespaces), title: $0.itemName, city: $0.cityName)
      } ?? []
    choices = routeChoices + placeChoices
  }
}

/// Open a board (web: /boards/new). The address follows the name until edited.
struct CreateBoardSheet: View {
  let service: BoardsService
  let onCreated: (Loci_Boards_V1_Board) -> Void

  @State private var name = ""
  @State private var slug = ""
  @State private var slugEdited = false
  @State private var about = ""
  @State private var sending = false
  @State private var error: String?
  @Environment(\.dismiss) private var dismiss

  private var address: String { slugEdited ? slug : BoardsModel.slugify(name) }
  private var canCreate: Bool { name.trimmingCharacters(in: .whitespaces).count >= 3 && BoardsModel.isValidSlug(address) && !sending }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Lisbon on a budget", text: $name).onChange(of: name) { _, v in if v.count > 60 { name = String(v.prefix(60)) } }
        } header: {
          Text("Name")
        } footer: {
          Text("One topic travellers on Loci will want to talk about: a city, a kind of trip, a way of travelling.")
        }
        Section {
          TextField(
            "lisbon-on-a-budget",
            text: Binding(
              get: { address },
              set: {
                slugEdited = true
                slug = String($0.lowercased().prefix(32))
              }
            )
          ).textInputAutocapitalization(.never).autocorrectionDisabled()
        } header: {
          Text("Address")
        } footer: {
          if !address.isEmpty, !BoardsModel.isValidSlug(address) {
            Text("3–32 lowercase letters, numbers or dashes.").foregroundStyle(Color.lociDestructive)
          } else {
            Text("/boards/\(address)")
          }
        }
        Section("What it's for (optional)") {
          TextField("What it's for", text: $about, prompt: Text("A sentence or two"), axis: .vertical).lineLimit(2...5).onChange(of: about) { _, v in
            if v.count > 500 { about = String(v.prefix(500)) }
          }
        }
      }.navigationTitle("Open a board").navigationBarTitleDisplayMode(.inline).toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Open") {
            Task {
              sending = true
              defer { sending = false }
              do {
                let board = try await service.createBoard(
                  slug: address,
                  name: name.trimmingCharacters(in: .whitespaces),
                  description: about.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                onCreated(board)
                dismiss()
              } catch { self.error = error.userMessage }
            }
          }.disabled(!canCreate)
        }
      }.errorAlert($error)
    }
  }
}

/// Admin: everyone muted or banned, and a way to lift it (web: /boards/admin).
struct SanctionsView: View {
  let service: BoardsService
  @State private var sanctions: [Loci_Boards_V1_Sanction] = []
  @State private var showPast = false
  @State private var loaded = false
  @State private var error: String?

  private func isActive(_ s: Loci_Boards_V1_Sanction) -> Bool { !s.hasLiftedAt && (!s.hasExpiresAt || s.expiresAt.date > Date()) }

  private var shown: [Loci_Boards_V1_Sanction] { sanctions.filter { showPast || isActive($0) } }

  var body: some View {
    List {
      Section {
        Toggle("Show lifted and expired", isOn: $showPast)
      } footer: {
        Text("Mute or ban someone from a post's or comment's menu.")
      }
      if loaded, shown.isEmpty { Text("Nobody is muted or banned.").foregroundStyle(Color.lociMutedInk) }
      ForEach(shown, id: \.id) { s in
        HStack(spacing: 10) {
          UserAvatar(user: s.user, size: 32)
          VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
              Text(s.user.displayName.isEmpty ? (s.user.username.isEmpty ? s.user.id : s.user.username) : s.user.displayName).font(.lociHeadline(15))
              Text(s.kind == .ban ? "ban" : "mute").font(.lociCaption(11)).padding(.horizontal, 6).padding(.vertical, 1).background(
                (s.kind == .ban ? Color.lociDestructive : Color.lociMuted).opacity(0.2),
                in: Capsule()
              )
            }
            Text(detail(s)).font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
          }
          Spacer()
          if isActive(s) {
            Button("Lift") {
              Task {
                do {
                  try await service.liftSanction(id: s.id)
                  await load()
                } catch { self.error = error.userMessage }
              }
            }.buttonStyle(.bordered)
          }
        }
      }
    }.navigationTitle("Moderation").navigationBarTitleDisplayMode(.inline).refreshable { await load() }.task { await load() }.errorAlert($error)
  }

  private func detail(_ s: Loci_Boards_V1_Sanction) -> String {
    var parts = ["Since \(s.createdAt.date.formatted(date: .abbreviated, time: .omitted))"]
    if s.hasLiftedAt {
      parts.append("lifted \(s.liftedAt.date.formatted(date: .abbreviated, time: .omitted))")
    } else if s.hasExpiresAt {
      parts.append("until \(s.expiresAt.date.formatted(date: .abbreviated, time: .omitted))")
    } else {
      parts.append("permanent")
    }
    if !s.reason.isEmpty { parts.append(s.reason) }
    return parts.joined(separator: " · ")
  }

  private func load() async {
    do { sanctions = try await service.sanctions() } catch { self.error = error.userMessage }
    loaded = true
  }
}
