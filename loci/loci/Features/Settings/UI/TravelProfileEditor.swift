import LociConnectProto
import SwiftUI

/// The travel profile form, in the web form's sections: Basic, Hotels,
/// Dining, Activities, Planning.
struct TravelProfileEditor: View {
  enum Section: String, CaseIterable { case basic = "Basic", hotels = "Hotels", dining = "Dining", activities = "Activities", planning = "Planning" }

  @State var draft: TravelProfileDraft
  let onSave: (TravelProfileDraft) async -> Bool

  @Environment(\.dismiss) private var dismiss
  @State private var section = Section.basic
  @State private var tags: [Loci_Tags_Tag] = []
  @State private var interests: [Loci_Interest_Interest] = []
  @State private var isSaving = false

  init(draft: TravelProfileDraft, onSave: @escaping (TravelProfileDraft) async -> Bool) {
    self._draft = State(initialValue: draft)
    self.onSave = onSave
  }

  var body: some View {
    NavigationStack {
      Form {
        Picker("Section", selection: $section) { ForEach(Section.allCases, id: \.self) { Text($0.rawValue) } }
          .pickerStyle(.segmented).listRowBackground(Color.clear).listRowInsets(EdgeInsets())

        switch section {
        case .basic: basic
        case .hotels: hotels
        case .dining: dining
        case .activities: activities
        case .planning: planning
        }
      }
      .navigationTitle(draft.id == nil ? "New profile" : draft.name).navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            isSaving = true
            Task {
              if await onSave(draft) { dismiss() }
              isSaving = false
            }
          }.disabled(isSaving)
        }
      }
      .task { await loadChoices() }
    }
  }

  // MARK: - Sections

  @ViewBuilder private var basic: some View {
    SwiftUI.Section {
      TextField("Profile name", text: $draft.name)
      Toggle("Default profile", isOn: $draft.isDefault)
    }
    SwiftUI.Section("Search") {
      Stepper("Radius: \(Int(draft.searchRadiusKm)) km", value: $draft.searchRadiusKm, in: 1...100, step: 1)
      Stepper("Budget: \(String(repeating: "€", count: draft.budgetLevel))", value: $draft.budgetLevel, in: 1...5)
      Picker("Time of day", selection: $draft.preferredTime) {
        ForEach(Loci_Profile_DayPreference.choices, id: \.self) { Text($0.label).tag($0) }
      }
      Picker("Pace", selection: $draft.preferredPace) { ForEach(Loci_Profile_SearchPace.choices, id: \.self) { Text($0.label).tag($0) } }
      Picker("Transport", selection: $draft.preferredTransport) {
        ForEach(Loci_Profile_TransportPreference.choices, id: \.self) { Text($0.label).tag($0) }
      }
    }
    SwiftUI.Section {
      Toggle("Accessible places", isOn: $draft.preferAccessible)
      Toggle("Outdoor seating", isOn: $draft.preferOutdoorSeating)
      Toggle("Dog friendly", isOn: $draft.preferDogFriendly)
    }
    if !interests.isEmpty {
      SwiftUI.Section("Interests") {
        ChipGrid(options: interests.map { ($0.id, $0.name) }, selection: $draft.interestIDs)
      }
    }
    if !tags.isEmpty {
      SwiftUI.Section("Tags") { ChipGrid(options: tags.map { ($0.id, $0.name) }, selection: $draft.tagIDs) }
    }
  }

  @ViewBuilder private var hotels: some View {
    SwiftUI.Section("Accommodation types") { ChipGrid(values: TravelProfileDraft.accommodationTypes, selection: $draft.accommodationTypes) }
    SwiftUI.Section("Stars and price") {
      Stepper("Stars from \(Int(draft.starMin))", value: $draft.starMin, in: 1...draft.starMax)
      Stepper("Stars up to \(Int(draft.starMax))", value: $draft.starMax, in: draft.starMin...5)
      Stepper("From \(Int(draft.pricePerNightMin)) / night", value: $draft.pricePerNightMin, in: 0...draft.pricePerNightMax, step: 10)
      Stepper("Up to \(Int(draft.pricePerNightMax)) / night", value: $draft.pricePerNightMax, in: draft.pricePerNightMin...5000, step: 10)
    }
    SwiftUI.Section("Amenities") { ChipGrid(values: TravelProfileDraft.amenities, selection: $draft.amenities) }
  }

  @ViewBuilder private var dining: some View {
    SwiftUI.Section("Cuisines") { ChipGrid(values: TravelProfileDraft.cuisines, selection: $draft.cuisines) }
    SwiftUI.Section("Service style") { ChipGrid(values: TravelProfileDraft.serviceStyles, selection: $draft.serviceStyles) }
    SwiftUI.Section("Price per person") {
      Stepper("From \(Int(draft.pricePerPersonMin))", value: $draft.pricePerPersonMin, in: 0...draft.pricePerPersonMax, step: 5)
      Stepper("Up to \(Int(draft.pricePerPersonMax))", value: $draft.pricePerPersonMax, in: draft.pricePerPersonMin...1000, step: 5)
    }
    SwiftUI.Section {
      Picker("Chains or local", selection: $draft.chainVsLocal) {
        ForEach(TravelProfileDraft.chainVsLocal, id: \.self) { Text($0.optionLabel).tag($0) }
      }
      Toggle("Michelin rated", isOn: $draft.michelinRated)
      Toggle("Local recommendations", isOn: $draft.localRecommendations)
      Toggle("Organic", isOn: $draft.organic)
    }
  }

  @ViewBuilder private var activities: some View {
    SwiftUI.Section("Categories") { ChipGrid(values: TravelProfileDraft.activityCategories, selection: $draft.activityCategories) }
    SwiftUI.Section {
      Picker("Physical activity", selection: $draft.physicalLevel) {
        ForEach(TravelProfileDraft.physicalLevels, id: \.self) { Text($0.optionLabel).tag($0) }
      }
      Picker("Indoor or outdoor", selection: $draft.indoorOutdoor) {
        ForEach(TravelProfileDraft.indoorOutdoor, id: \.self) { Text($0.optionLabel).tag($0) }
      }
      Toggle("Educational", isOn: $draft.educational)
      Toggle("Photo opportunities", isOn: $draft.photography)
      Toggle("Avoid crowds", isOn: $draft.avoidCrowds)
    }
  }

  @ViewBuilder private var planning: some View {
    SwiftUI.Section {
      Picker("Planning style", selection: $draft.planningStyle) {
        ForEach(TravelProfileDraft.planningStyles, id: \.self) { Text($0.optionLabel).tag($0) }
      }
      Picker("Time flexibility", selection: $draft.timeFlexibility) {
        ForEach(TravelProfileDraft.timeFlexibility, id: \.self) { Text($0.optionLabel).tag($0) }
      }
      Toggle("Avoid peak season", isOn: $draft.avoidPeakSeason)
    }
    SwiftUI.Section("Preferred seasons") { ChipGrid(values: TravelProfileDraft.seasons, selection: $draft.seasons) }
  }

  /// Only active tags and interests are offered, as on web.
  private func loadChoices() async {
    async let tagsCall = try? rpc("") { await SettingsClients.tags.getTags(request: .init(), headers: [:]) }.tags
    var interestRequest = Loci_Interest_GetInterestsRequest()
    interestRequest.activeOnly = true
    let request = interestRequest
    async let interestsCall = try? rpc("", request) { await SettingsClients.interests.getInterests(request: $0, headers: [:]) }.interests
    tags = (await tagsCall ?? []).filter(\.active)
    interests = (await interestsCall ?? []).filter(\.active)
  }
}

/// Toggleable chips in a wrapping layout. Selection holds the option ids.
struct ChipGrid: View {
  let options: [(id: String, label: String)]
  @Binding var selection: Set<String>

  init(options: [(String, String)], selection: Binding<Set<String>>) {
    self.options = options.map { (id: $0.0, label: $0.1) }
    self._selection = selection
  }

  init(values: [String], selection: Binding<Set<String>>) {
    self.init(options: values.map { ($0, $0.optionLabel) }, selection: selection)
  }

  var body: some View {
    FlowLayout(spacing: 8) {
      ForEach(options, id: \.id) { option in
        let isOn = selection.contains(option.id)
        Button {
          if isOn { selection.remove(option.id) } else { selection.insert(option.id) }
        } label: {
          Text(option.label).font(.lociCaption(13)).padding(.horizontal, 12).padding(.vertical, 7)
            .background(isOn ? Color.lociForest : Color.lociMuted, in: Capsule())
            .foregroundStyle(isOn ? Color.lociPaper : Color.lociInk)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
      }
    }
    .padding(.vertical, 4)
  }
}

/// Wraps children onto new rows when they run out of width.
struct FlowLayout: Layout {
  var spacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    rows(in: proposal.width ?? .infinity, subviews: subviews).size
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    for placement in rows(in: bounds.width, subviews: subviews).placements {
      subviews[placement.index].place(
        at: CGPoint(x: bounds.minX + placement.origin.x, y: bounds.minY + placement.origin.y),
        proposal: .unspecified
      )
    }
  }

  private func rows(in width: CGFloat, subviews: Subviews) -> (size: CGSize, placements: [(index: Int, origin: CGPoint)]) {
    var placements: [(index: Int, origin: CGPoint)] = []
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowHeight: CGFloat = 0
    var maxX: CGFloat = 0
    for (index, subview) in subviews.enumerated() {
      let size = subview.sizeThatFits(.unspecified)
      if x > 0, x + size.width > width {
        x = 0
        y += rowHeight + spacing
        rowHeight = 0
      }
      placements.append((index, CGPoint(x: x, y: y)))
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
      maxX = max(maxX, x - spacing)
    }
    return (CGSize(width: maxX, height: y + rowHeight), placements)
  }
}
