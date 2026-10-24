import LociConnectProto
import SwiftProtobuf
import SwiftUI

/// Notes between the people planning a trip (web: components/trip/TripComments.tsx):
/// about the trip, or about one of its stops. Others' comments can be
/// reported or their author blocked, which App Review asks of anything people
/// write to each other. The page owns the network: each action is a closure
/// that answers with the error to show, if any.
struct TripCommentsSection: View {
  let comments: [Loci_Trip_TripComment]
  /// The trip's stops, for "about" and for naming what a comment is on.
  let stops: [Loci_Trip_TripStop]
  /// The stop the composer is about; the page sets it from a stop's swipe.
  @Binding var aboutStopID: String
  let onPost: (_ body: String, _ stopID: String?) async -> String?
  let onDelete: (Loci_Trip_TripComment) async -> String?
  let onReport: (Loci_Trip_TripComment, _ reason: String) async -> String?
  let onBlock: (Loci_Trip_TripComment) async -> String?

  @State private var draft = ""
  @State private var posting = false
  @State private var postError: String?
  @State private var errors: [String: String] = [:]
  @State private var blocking: Loci_Trip_TripComment?

  static let maxLength = 2000

  var body: some View {
    Section("Comments · \(comments.count)") {
      if comments.isEmpty {
        Text("Nothing yet. Leave a note for everyone on the trip.")
          .font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk)
      }
      ForEach(comments, id: \.id) { row($0) }
      composer
    }
    .confirmationDialog(
      "Block \(blocking.map(Self.name) ?? "them")?",
      isPresented: Binding(get: { blocking != nil }, set: { if !$0 { blocking = nil } }),
      titleVisibility: .visible,
      presenting: blocking
    ) { comment in
      Button("Block", role: .destructive) { run(comment) { await onBlock(comment) } }
    } message: { _ in
      Text("You won't see each other's comments or profiles.")
    }
  }

  nonisolated static func name(_ c: Loci_Trip_TripComment) -> String {
    c.mine ? "You" : c.hasAuthor ? c.author.shownName : "Someone"
  }

  /// "Rui · on Miradouro da Graça": what the byline says before the time.
  nonisolated static func byline(_ c: Loci_Trip_TripComment, stops: [Loci_Trip_TripStop]) -> String {
    guard !c.stopID.isEmpty, let stop = stops.first(where: { $0.id == c.stopID }) else { return name(c) }
    return "\(name(c)) · on \(stop.name)"
  }

  private func row(_ c: Loci_Trip_TripComment) -> some View {
    HStack(alignment: .top, spacing: 10) {
      if c.hasAuthor { UserAvatar(user: c.author, size: 28) }
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
          Text(Self.byline(c, stops: stops))
          if c.hasCreatedAt {
            Text("·")
            Text(c.createdAt.date, format: .relative(presentation: .named, unitsStyle: .abbreviated))
          }
        }
        .font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk)
        Text(c.body).font(.lociBody(15)).foregroundStyle(Color.lociInk).textSelection(.enabled)
        if let error = errors[c.id] {
          Text(error).font(.lociCaption(13)).foregroundStyle(Color.lociDestructive)
        }
      }
      Spacer(minLength: 0)
      if c.canDelete || !c.mine { menu(c) }
    }
    .padding(.vertical, 2)
  }

  private func menu(_ c: Loci_Trip_TripComment) -> some View {
    Menu {
      if c.canDelete {
        Button("Delete", systemImage: "trash", role: .destructive) { run(c) { await onDelete(c) } }
      }
      if !c.mine {
        Menu("Report", systemImage: "flag") {
          ForEach(TripCommentsAPI.reportReasons, id: \.value) { reason in
            Button(reason.label) { run(c) { await onReport(c, reason.value) } }
          }
        }
        if c.hasAuthor {
          Button("Block \(c.author.shownName)", systemImage: "hand.raised") { blocking = c }
        }
      }
    } label: {
      Image(systemName: "ellipsis").foregroundStyle(Color.lociMutedInk).frame(width: 28, height: 28)
    }
    .accessibilityLabel("Comment actions")
    .buttonStyle(.borderless)
  }

  private var composer: some View {
    VStack(alignment: .leading, spacing: 8) {
      if !stops.isEmpty {
        Picker("About", selection: $aboutStopID) {
          Text("The whole trip").tag("")
          ForEach(stops, id: \.id) { Text($0.name).tag($0.id) }
        }
        .font(.lociCaption(13))
      }
      TextField(placeholder, text: $draft, axis: .vertical)
        .lineLimit(2...6)
        .onChange(of: draft) { _, text in
          if text.count > Self.maxLength { draft = String(text.prefix(Self.maxLength)) }
        }
      if let postError {
        Text(postError).font(.lociCaption(13)).foregroundStyle(Color.lociDestructive)
      }
      HStack {
        Spacer()
        Button(posting ? "Posting…" : "Post") { Task { await post() } }
          .buttonStyle(.borderedProminent).tint(.lociCoralFill).controlSize(.small)
          .disabled(posting || trimmed.isEmpty)
      }
    }
    .padding(.vertical, 4)
  }

  private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

  private var placeholder: String {
    stops.first(where: { $0.id == aboutStopID }).map { "Something about \($0.name)…" } ?? "Write a comment…"
  }

  private func post() async {
    posting = true
    postError = nil
    let stop = stops.contains { $0.id == aboutStopID } ? aboutStopID : nil
    if let error = await onPost(trimmed, stop) {
      postError = error
    } else {
      draft = ""
      aboutStopID = ""
    }
    posting = false
  }

  private func run(_ c: Loci_Trip_TripComment, _ action: @escaping () async -> String?) {
    Task {
      errors[c.id] = nil
      errors[c.id] = await action()
    }
  }
}
