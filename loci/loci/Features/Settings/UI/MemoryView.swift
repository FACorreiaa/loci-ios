import LociConnectProto
import SwiftUI

/// What Loci remembers (web: /settings/memory). MemoryService: GetMemory{includeEvidence},
/// ForgetTrait{traitKey}, ForgetEvidence{feedbackId}.
struct MemoryView: View {
  @State private var memory: Loci_Memory_GetMemoryResponse?
  @State private var error: String?

  var body: some View {
    List {
      if let memory {
        if !memory.personalizationEnabled {
          Text("Personalisation is off, so nothing new is being learned.").foregroundStyle(Color.lociMutedInk)
        }
        if memory.traits.isEmpty {
          Text("Loci doesn't remember anything about you yet.").foregroundStyle(Color.lociMutedInk)
        }
        ForEach(memory.traits, id: \.key) { trait in
          Section {
            ForEach(trait.evidence, id: \.id) { evidence in
              VStack(alignment: .leading, spacing: 2) {
                Text(evidence.poiName.isEmpty ? evidence.event : evidence.poiName)
                if !evidence.cityName.isEmpty { Text(evidence.cityName).font(.lociCaption()).foregroundStyle(Color.lociMutedInk) }
              }
              .swipeActions {
                Button("Forget", role: .destructive) { Task { await forget(evidence: evidence.feedbackID) } }
              }
            }
          } header: {
            HStack {
              Text(trait.label)
              Spacer()
              Button("Forget") { Task { await forget(trait: trait.key) } }.font(.lociCaption()).textCase(nil)
            }
          } footer: {
            Text("From \(trait.evidenceCount) signals")
          }
        }
      } else {
        ProgressView()
      }
    }
    .settingsStyle("What Loci remembers")
    .refreshable { await load() }
    .errorAlert($error)
    .task { await load() }
  }

  private func load() async {
    var request = Loci_Memory_GetMemoryRequest()
    request.includeEvidence = true
    do {
      memory = try await rpc("Could not load your memory.", request) { await SettingsClients.memory.getMemory(request: $0, headers: [:]) }
    } catch { self.error = error.userMessage }
  }

  private func forget(trait key: String) async {
    var request = Loci_Memory_ForgetTraitRequest()
    request.traitKey = key
    do {
      _ = try await rpc("Could not forget that.", request) { await SettingsClients.memory.forgetTrait(request: $0, headers: [:]) }
      await load()
    } catch { self.error = error.userMessage }
  }

  private func forget(evidence id: String) async {
    var request = Loci_Memory_ForgetEvidenceRequest()
    request.feedbackID = id
    do {
      _ = try await rpc("Could not forget that.", request) { await SettingsClients.memory.forgetEvidence(request: $0, headers: [:]) }
      await load()
    } catch { self.error = error.userMessage }
  }
}
