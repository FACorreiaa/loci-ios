import LociConnectProto
import SwiftUI

/// Admin: mute or ban someone from boards, for a while or for good.
struct SanctionSheet: View {
  let target: SanctionTarget
  let service: BoardsService
  let onDone: () -> Void

  @State private var kind: Loci_Boards_V1_SanctionKind
  @State private var days: Int
  @State private var reason = ""
  @State private var sending = false
  @State private var error: String?
  @Environment(\.dismiss) private var dismiss

  /// 0 means permanent.
  private static let durations: [(String, Int)] = [("1 day", 1), ("1 week", 7), ("30 days", 30), ("Permanent", 0)]

  init(target: SanctionTarget, service: BoardsService, onDone: @escaping () -> Void) {
    self.target = target
    self.service = service
    self.onDone = onDone
    _kind = State(initialValue: target.kind)
    _days = State(initialValue: target.kind == .ban ? 0 : 7)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("Sanction", selection: $kind) {
            Text("Mute").tag(Loci_Boards_V1_SanctionKind.mute)
            Text("Ban").tag(Loci_Boards_V1_SanctionKind.ban)
          }.pickerStyle(.segmented)
        } footer: {
          Text("A mute stops them posting, commenting and voting. A ban also hides everything they wrote until it is lifted.")
        }
        Section("For") { Picker("Duration", selection: $days) { ForEach(Self.durations, id: \.1) { Text($0.0).tag($0.1) } } }
        Section("Reason (only admins see it)") { TextField("Optional", text: $reason, axis: .vertical).lineLimit(2...4) }
      }.navigationTitle(target.user.shownName).navigationBarTitleDisplayMode(.inline).toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button(kind == .ban ? "Ban" : "Mute", role: kind == .ban ? .destructive : nil) {
            Task {
              sending = true
              defer { sending = false }
              do {
                try await service.sanction(
                  userID: target.user.id,
                  kind: kind,
                  reason: String(reason.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500)),
                  days: days == 0 ? nil : days
                )
                onDone()
                dismiss()
              } catch { self.error = error.userMessage }
            }
          }.disabled(sending)
        }
      }.errorAlert($error)
    }.presentationDetents([.medium, .large])
  }
}
