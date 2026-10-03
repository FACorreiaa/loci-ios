import Contacts
import ContactsUI
import LociConnectProto
import SwiftUI

/// Friends from the address book. Numbers and emails are hashed on the phone
/// (`ContactHasher`) and only the hashes are sent; nothing is stored for
/// contacts who are not on Loci. With limited access (iOS 18+) the person
/// picks which contacts the app sees, and can add more.
struct ContactMatchView: View {
  @State private var status = CNContactStore.authorizationStatus(for: .contacts)
  @State private var matches: [Match] = []
  @State private var isMatching = false
  @State private var hasMatched = false
  @State private var showsPicker = false
  @State private var error: String?

  struct Match: Identifiable {
    var id: String { user.id }
    let user: Loci_Social_PublicUser
    let contactName: String
    var relationship: Relationship
  }

  var body: some View {
    List {
      Section {
        switch status {
        case .notDetermined:
          Button("Find friends in my contacts", systemImage: "person.crop.circle.badge.checkmark") { requestAccess() }
        case .denied, .restricted:
          Text("Contacts access is off. Turn it on in Settings to find friends here.").foregroundStyle(Color.lociMutedInk)
          if let url = URL(string: UIApplication.openSettingsURLString) { Link("Open Settings", destination: url) }
        case .limited:
          Button("Choose more contacts", systemImage: "person.badge.plus") { showsPicker = true }
        default:
          EmptyView()
        }
      } footer: {
        VStack(alignment: .leading, spacing: 6) {
          Text("Friends show up here when the number or email in your contacts is one they've verified on Loci.")
          Text("Only scrambled fingerprints of numbers and emails leave your phone, and nothing is kept for people who aren't on Loci.")
        }
      }
      .listRowBackground(Color.lociCard)

      if isMatching {
        Section { ProgressView() }.listRowBackground(Color.lociCard)
      } else if hasMatched {
        Section(matches.isEmpty ? "None of your contacts are on Loci yet" : "On Loci") {
          ForEach($matches) { $match in
            PersonRow(user: match.user, subtitle: match.contactName) {
              RelationshipButton(user: match.user, relationship: $match.relationship)
            }
          }
        }
        .listRowBackground(Color.lociCard)
      }
    }
    .settingsStyle("From your contacts")
    .limitedContactAccessPicker(isPresented: $showsPicker) { _ in Task { await match() } }
    .errorAlert($error)
    .task { if status == .authorized || status == .limited { await match() } }
  }

  private func requestAccess() {
    Task {
      _ = try? await CNContactStore().requestAccess(for: .contacts)
      status = CNContactStore.authorizationStatus(for: .contacts)
      if status == .authorized || status == .limited { await match() }
    }
  }

  private func match() async {
    isMatching = true
    defer {
      isMatching = false
      hasMatched = true
    }
    let region = Locale.current.region?.identifier
    let names = await Task.detached { Self.hashedContacts(region: region) }.value
    if names.isEmpty {
      matches = []
      return
    }
    do {
      let found = try await SocialAPI.matchContacts(hashes: Array(names.keys))
      var seen = Set<String>()
      matches = found.compactMap { hit in
        guard seen.insert(hit.user.id).inserted else { return nil }
        return Match(user: hit.user, contactName: names[hit.hash] ?? "", relationship: Relationship(hit.relationship))
      }
    } catch {
      self.error = error.userMessage
    }
  }

  /// hash → the contact's name, for every contact the app may read.
  nonisolated static func hashedContacts(region: String?) -> [String: String] {
    let keys: [CNKeyDescriptor] = [
      CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
      CNContactPhoneNumbersKey as CNKeyDescriptor,
      CNContactEmailAddressesKey as CNKeyDescriptor,
    ]
    var out: [String: String] = [:]
    try? CNContactStore().enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { contact, _ in
      let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
      let hashes = ContactHasher.hashes(
        phones: contact.phoneNumbers.map(\.value.stringValue),
        emails: contact.emailAddresses.map { $0.value as String },
        region: region
      )
      for hash in hashes { out[hash] = name }
    }
    return out
  }
}
