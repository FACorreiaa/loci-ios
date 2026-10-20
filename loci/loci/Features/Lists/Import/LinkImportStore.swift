import Foundation
import Observation

/// Paste a link, see the places it mentions, keep the picked ones in a list
/// (web: components/import/ImportFromLink.tsx).
@MainActor @Observable final class LinkImportStore {
  var url = ""
  var cityHint = ""
  var listName = ""
  var target = LinkImportTarget.new
  var error: String?
  private(set) var result: LinkImportResult?
  private(set) var selection: Set<String> = []
  private(set) var outcome: LinkImportOutcome?
  private(set) var isReading = false
  private(set) var isSaving = false

  let service: any LinkImportService

  init(service: any LinkImportService = ConnectLinkImportService()) {
    self.service = service
  }

  var chosen: [ImportedPlace] { (result?.places ?? []).filter { $0.canSave && selection.contains($0.id) } }

  func isPicked(_ place: ImportedPlace) -> Bool { selection.contains(place.id) }

  func toggle(_ place: ImportedPlace) {
    guard place.canSave else { return }
    if selection.contains(place.id) { selection.remove(place.id) } else { selection.insert(place.id) }
  }

  func read() async {
    guard let link = LinkImportLink.normalized(url) else {
      error = "Paste a public link to a post, video, map pin or article."
      return
    }
    isReading = true
    defer { isReading = false }
    error = nil
    outcome = nil
    do {
      let found = try await service.importPlaces(url: link, cityHint: cityHint.trimmingCharacters(in: .whitespacesAndNewlines))
      result = found
      selection = found.defaultSelection
      listName = found.defaultListName
      Analytics.capture(.linkImported, ["source": found.source, "places": found.places.count, "resolved": found.defaultSelection.count])
    } catch {
      self.error = Self.message(for: error)
    }
  }

  /// Saves the picked places in order. A place already in the list counts as
  /// there; one that fails stays picked so a second tap retries only it.
  func save() async {
    let places = chosen
    guard !places.isEmpty, let result else { return }
    isSaving = true
    defer { isSaving = false }
    error = nil
    let listID: String
    switch target {
    case .existing(let id):
      listID = id
    case .new:
      let name = listName.trimmingCharacters(in: .whitespacesAndNewlines)
      do {
        listID = try await service.createList(name: name.isEmpty ? result.defaultListName : name)
      } catch {
        self.error = Self.message(for: error)
        return
      }
      // A retry adds to the list just made rather than making another.
      target = .existing(listID)
    }
    var done = LinkImportOutcome(listID: listID)
    var stillPicked: Set<String> = []
    for place in places {
      guard let poiID = place.poiID else { continue }
      do {
        try await service.addPlace(poiID: poiID, toList: listID)
        done.added += 1
      } catch APIError.conflict {
        done.already += 1
      } catch {
        done.failed += 1
        stillPicked.insert(place.id)
      }
    }
    selection = stillPicked
    outcome = done
    if done.added > 0 { Analytics.capture(.poiSaved, ["surface": "link_import", "count": done.added]) }
  }

  /// Server refusals arrive in lower case ("no places found on that page").
  static func message(for error: Error) -> String {
    switch error {
    case APIError.custom(let text):
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let first = trimmed.first else { return "Couldn't import that link." }
      return first.uppercased() + trimmed.dropFirst() + (trimmed.hasSuffix(".") ? "" : ".")
    case APIError.network:
      return "Couldn't read the places right now. Try again in a minute."
    default:
      return error.localizedDescription
    }
  }
}
