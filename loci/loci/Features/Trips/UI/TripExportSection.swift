import Connect
import LociConnectProto
import SwiftUI

/// "Take it with you": Apple Calendar plus the server exports (web:
/// components/trip/TripExportMenu.tsx). ICS always works, PDF is Pro past one
/// day, Markdown is Pro (`TripExportGate`). The server enforces the same rules;
/// this only saves a round trip and says why. No pricing link (App Store 3.1.1).
struct TripExportSection: View {
  let trip: Loci_Trip_TripDraft
  let isPro: Bool

  @State private var busy: Loci_Trip_ExportFormat?
  @State private var exportedFile: URL?
  @State private var notice: String?
  @State private var calendarStatus: String?
  @State private var error: String?

  var body: some View {
    Section("Take it with you") {
      Button("Add to Apple Calendar", systemImage: "calendar.badge.plus") { Task { await addToCalendar() } }
      if let calendarStatus { Text(calendarStatus).font(.lociCaption()).foregroundStyle(Color.lociMutedInk) }
      Menu {
        ForEach(TripExportGate.formats, id: \.self) { format in
          Button {
            Task { await export(format) }
          } label: {
            if TripExportGate.isLocked(format, isPro: isPro, dayCount: trip.days.count) {
              Label("\(TripExportGate.label(format)) · Pro", systemImage: "lock")
            } else {
              Text(TripExportGate.label(format))
            }
          }
        }
      } label: {
        HStack {
          Label("Export", systemImage: "arrow.down.doc")
          if busy != nil { Spacer(); ProgressView() }
        }
      }
      .disabled(busy != nil)
      if let notice { Text(notice).font(.lociCaption()).foregroundStyle(Color.lociMutedInk) }
      if let exportedFile {
        ShareLink(item: exportedFile) { Label("Share \(exportedFile.lastPathComponent)", systemImage: "square.and.arrow.up") }
      }
    }
    .listRowBackground(Color.lociCard)
    .errorAlert($error)
  }

  private func export(_ format: Loci_Trip_ExportFormat) async {
    let dayCount = trip.days.count
    switch TripExportGate.decide(format, isPro: isPro, dayCount: dayCount) {
    case .locked(let message):
      notice = message
    case .export(let gateNotice):
      busy = format
      defer { busy = nil }
      notice = gateNotice
      do {
        let response = try await TripAPI.export(tripID: trip.id, format: format)
        let url = FileManager.default.temporaryDirectory.appending(path: TripExportGate.filename(serverName: response.filename, format: format))
        try response.data.write(to: url, options: .atomic)
        exportedFile = url
        Analytics.capture(.tripExported, ["format": TripExportGate.analyticsName(format), "day_count": dayCount])
      } catch let rpcError as TripRPCError {
        if rpcError.code == .permissionDenied {
          notice = "That export is included with Pro."
        } else if !rpcError.isCancelled {
          error = rpcError.message
        }
      } catch {
        self.error = error.userMessage
      }
    }
  }

  private func addToCalendar() async {
    do {
      guard try await AppleCalendar.shared.requestAccess() else {
        calendarStatus = "Calendar access is off in Settings."
        return
      }
      try AppleCalendar.shared.writeTrip(trip)
      calendarStatus = "Added to the Loci calendar on this iPhone."
    } catch { self.error = error.userMessage }
  }
}
