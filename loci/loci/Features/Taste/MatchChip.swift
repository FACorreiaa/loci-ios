import LociConnectProto
import SwiftUI

/// "87% match". Tapping opens the reasons behind the number (web: MatchChip).
struct MatchChip: View {
  let place: Loci_Poi_POIDetailedInfo
  @State private var showingReasons = false

  var body: some View {
    if let label = place.matchLabel {
      Button {
        showingReasons = true
      } label: {
        Label(label, systemImage: "sparkles")
          .font(.lociCaption(11)).foregroundStyle(Color.lociInk)
          .padding(.horizontal, 6).padding(.vertical, 2)
          .background(Color.lociForest.opacity(0.18), in: Capsule())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(label). Why it fits you")
      .sheet(isPresented: $showingReasons) { MatchReasonsSheet(place: place) }
    }
  }
}

/// "Why it fits you": the reasons, and a way to correct what Loci learned.
struct MatchReasonsSheet: View {
  let place: Loci_Poi_POIDetailedInfo
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section {
          Text("\(place.name) is a \(place.matchLabel ?? "match") for your taste.")
            .font(.lociCaption(14)).foregroundStyle(Color.lociMutedInk)
        }
        Section {
          if place.matchReasons.isEmpty {
            Text("Loci scored it from the places you've saved, visited and rated.")
          } else {
            ForEach(place.matchReasons, id: \.self) { reason in
              Label(reason, systemImage: "sparkles")
            }
          }
        }
        Section {
          NavigationLink("Not quite? Tell Loci") { SettingsRouteDestination(route: .memory) }
        }
      }
      .navigationTitle("Why it fits you")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
    }
    .presentationDetents([.medium, .large])
  }
}
