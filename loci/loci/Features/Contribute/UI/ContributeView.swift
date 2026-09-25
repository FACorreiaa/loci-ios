import LociConnectProto
import SwiftUI

/// Profile › Contribute (web: /contribute). The scout's standing, the places
/// that need a fresh look, places waiting on a second scout, and a way to
/// report on, or add, a place that isn't on the list.
struct ContributeView: View {
  @State private var store: ContributeStore
  @State private var addingPlace = false
  @FocusState private var searchFocused: Bool

  init(store: ContributeStore = ContributeStore()) {
    _store = State(initialValue: store)
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          ScoutHero(profile: store.profile)
          missingPlace
          if !store.shownPending.isEmpty { pendingSection }
          tasksSection(proxy: proxy)
          addPlaceCard
        }
        .padding(LociTheme.defaultPadding)
      }
    }
    .background(Color.lociPaper.ignoresSafeArea())
    .navigationTitle("Contribute")
    .navigationBarTitleDisplayMode(.inline)
    .navigationDestination(for: VerificationTask.self) { task in
      // A filed report changes the counts and the task's open questions, so both reload.
      ClaimFormView(task: task, service: store.service) { Task { await store.load() } }
    }
    .sheet(isPresented: $addingPlace) {
      AddPlaceView(store: addPlaceStore)
    }
    .errorAlert($store.error)
    .refreshable { await store.load() }
    .task {
      if store.phase == .idle { await store.load() }
      await store.prepareSearch()
    }
    .onAppear { Analytics.screen("contribute") }
  }

  private var addPlaceStore: AddPlaceStore {
    let add = AddPlaceStore(service: store.service, city: store.city)
    add.onSubmitted = { Task { await store.refreshProfile() } }
    return add
  }

  // MARK: - Missing place

  private var missingPlace: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "safari")
          .font(.title3)
          .foregroundStyle(Color.lociCoral)
          .frame(width: 40, height: 40)
          .background(Color.lociMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 4) {
          Text("Not on the list").lociCoordStyle(10)
          Text("Something we're missing").font(.lociTitle(20)).foregroundStyle(Color.lociInk)
          Text("A place you know that isn't in the list below. Look it up and file what you observed.")
            .font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk)
        }
      }
      VStack(spacing: 8) {
        searchField("Café, lookout, market…", text: $store.query, symbol: "magnifyingglass")
        searchField("City", text: $store.city, symbol: "building.2")
        Button {
          searchFocused = false
          Task { await store.search() }
        } label: {
          Text(store.isSearching ? "Searching…" : "Look up")
            .font(.lociBody(15).weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: LociTheme.minTapTarget)
        }
        .lociProminentButton()
        .disabled(!store.canSearch)
      }
      if store.searchContext != nil {
        Text("Searching within 25 km of you.").font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk)
      }
      searchResults
    }
    .lociCard()
  }

  private func searchField(_ prompt: String, text: Binding<String>, symbol: String) -> some View {
    HStack(spacing: 8) {
      Image(systemName: symbol).foregroundStyle(Color.lociMutedInk).accessibilityHidden(true)
      TextField(prompt, text: text)
        .font(.lociBody(15))
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled()
        .submitLabel(.search)
        .focused($searchFocused)
        .onSubmit { Task { await store.search() } }
    }
    .padding(.horizontal, 12)
    .frame(minHeight: LociTheme.minTapTarget)
    .background(Color.lociPaper, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.lociBorder))
  }

  @ViewBuilder private var searchResults: some View {
    if let message = store.searchError {
      Text(message).font(.lociCaption(13)).foregroundStyle(Color.lociDestructive)
    } else if store.hasSearched, !store.isSearching, store.results.isEmpty {
      Text(
        "Not in the catalog under that name. Try a landmark, a neighbourhood, or a more specific spelling — field reports need a catalogued place."
      )
        .font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk)
        .padding(10)
        .background(Color.lociMuted.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    } else if !store.results.isEmpty {
      VStack(spacing: 0) {
        ForEach(Array(store.results.enumerated()), id: \.offset) { index, poi in
          if index > 0 { Divider() }
          resultRow(poi)
        }
      }
      .background(Color.lociPaper, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.lociBorder))
    }
  }

  @ViewBuilder private func resultRow(_ poi: Loci_Poi_POIDetailedInfo) -> some View {
    let label = HStack(alignment: .top, spacing: 10) {
      Image(systemName: "mappin").foregroundStyle(Color.lociCoral).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(poi.name).font(.lociBody(15).weight(.semibold)).foregroundStyle(Color.lociInk).lineLimit(1)
        let subtitle = ContributePayload.searchSubtitle(poi)
        if !subtitle.isEmpty { Text(subtitle).font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk).lineLimit(1) }
      }
      Spacer(minLength: 8)
      Text(ContributePayload.canReport(poiID: poi.id) ? "Report" : "Not reportable")
        .font(.lociCaption(12).weight(.semibold))
        .foregroundStyle(ContributePayload.canReport(poiID: poi.id) ? Color.lociForest : Color.lociMutedInk)
    }
    .padding(.horizontal, 12).padding(.vertical, 10)
    .frame(minHeight: LociTheme.minTapTarget)
    .contentShape(Rectangle())

    if ContributePayload.canReport(poiID: poi.id) {
      NavigationLink(value: store.task(for: poi)) { label }.buttonStyle(.plain)
    } else {
      label.accessibilityHint("This place isn't stored yet, so it can't take a report.")
    }
  }

  // MARK: - Pending places

  private var pendingSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Waiting on a second scout").lociCoordStyle(10)
        Text("Does this place exist?").font(.lociTitle(20)).foregroundStyle(Color.lociInk)
      }
      ForEach(store.shownPending) { place in
        PendingPlaceCard(
          place: place,
          outcome: store.outcome(for: place),
          isConfirming: store.confirming.contains(place.submissionID),
          failure: store.confirmFailed[place.submissionID]
        ) { Task { await store.confirm(place) } }
      }
    }
  }

  // MARK: - Tasks

  @ViewBuilder private func tasksSection(proxy: ScrollViewProxy) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Knowledge gaps near you").lociCoordStyle(10)
        Text("Places that need a fresh look").font(.lociTitle(20)).foregroundStyle(Color.lociInk)
        Text("Two matching reports verify a fact.").font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk)
      }
      .id("tasks")
      switch store.phase {
      case .idle, .loading:
        ForEach(0..<3, id: \.self) { _ in
          RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous).fill(Color.lociMuted).frame(height: 72)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading places to verify")
      case .failed(let message):
        ContentUnavailableView {
          Label("Could not load places to verify", systemImage: "exclamationmark.triangle")
        } description: {
          Text(message)
        } actions: {
          Button("Try again") { Task { await store.load() } }.lociProminentButton()
        }
      case .loaded where store.tasks.isEmpty:
        ContentUnavailableView(
          "Nothing queued right now",
          systemImage: "checkmark.seal",
          description: Text("We ask about places you have been looking at. Look up a place you know above, or explore a city and check back.")
        )
      case .loaded:
        ForEach(store.visibleTasks) { task in
          NavigationLink(value: task) { TaskRow(task: task) }.buttonStyle(.plain)
        }
        TaskPager(page: store.page, pageCount: store.pageCount, range: store.pageRange, total: store.tasks.count) { next in
          withAnimation(.smooth) {
            store.goToPage(next)
            proxy.scrollTo("tasks", anchor: .top)
          }
        }
      }
    }
  }

  // MARK: - Add a place

  private var addPlaceCard: some View {
    Button {
      addingPlace = true
    } label: {
      HStack(spacing: 12) {
        Image(systemName: "mappin.and.ellipse").font(.title3).foregroundStyle(Color.lociCoral).accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text("Add a place").font(.lociHeadline(16)).foregroundStyle(Color.lociInk)
          Text("Not in the catalog at all? Propose it. It goes live once another scout confirms it exists.")
            .font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk).multilineTextAlignment(.leading)
        }
        Spacer(minLength: 4)
        Image(systemName: "chevron.right").foregroundStyle(Color.lociMutedInk).accessibilityHidden(true)
      }
      .lociCard()
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// Reputation, reports and verified, plus the badges web fetches but never shows.
private struct ScoutHero: View {
  let profile: ContributorProfile

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Local scout network").font(.lociCoord(10)).textCase(.uppercase).tracking(1.2).foregroundStyle(Color.heroInk.opacity(0.7))
      Text("Make the field guide more true.").font(.lociTitle(26)).foregroundStyle(Color.heroInk)
      Text("Confirm the useful details algorithms miss: current hours, accessibility, noise, crowds, and the feel of a place.")
        .font(.lociBody(14)).foregroundStyle(Color.heroInk.opacity(0.8))
      HStack(spacing: 8) {
        stat(profile.reputation, "Reputation")
        stat(profile.submittedClaims, "Reports")
        stat(profile.acceptedClaims, "Verified")
      }
      if !profile.badges.isEmpty {
        FlowLayout(spacing: 6) {
          ForEach(profile.badges, id: \.self) { slug in
            Label(ScoutBadge.title(slug), systemImage: "rosette")
              .font(.lociCaption(12).weight(.semibold))
              .padding(.horizontal, 10).padding(.vertical, 5)
              .background(Color.heroInk.opacity(0.16), in: Capsule())
              .foregroundStyle(Color.heroInk)
              .accessibilityHint(ScoutBadge.detail(slug) ?? "")
          }
        }
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.clusterHero, in: RoundedRectangle(cornerRadius: LociTheme.cornerRadiusHero, style: .continuous))
  }

  private func stat(_ value: Int, _ label: String) -> some View {
    VStack(spacing: 2) {
      Text("\(value)").font(.lociTitle(22)).foregroundStyle(Color.heroInk).monospacedDigit()
      Text(label).font(.lociCaption(11)).foregroundStyle(Color.heroInk.opacity(0.65))
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 10)
    .background(Color.heroInk.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .accessibilityElement(children: .combine)
  }
}

private extension Color {
  /// The hero's fixed deep green, the same in light and dark (web: .loci-hero).
  static let clusterHero = LociTheme.clusterColor
  /// Text on the hero: the paper colour, fixed, so it stays light in dark mode.
  static let heroInk = LociTheme.stampInk
}

/// A knowledge-gap place: its name, the first two fields asked about, "+N".
private struct TaskRow: View {
  let task: VerificationTask

  var body: some View {
    let labels = task.requestedFields.map(PlaceFactVocabulary.label)
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "mappin").foregroundStyle(Color.lociCoral).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 6) {
        Text(task.poiName).font(.lociHeadline(16)).foregroundStyle(Color.lociInk).lineLimit(2)
        HStack(spacing: 6) {
          ForEach(labels.prefix(2), id: \.self) { label in
            Text(label).font(.lociCaption(11)).padding(.horizontal, 6).padding(.vertical, 2)
              .background(Color.lociMuted, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
              .foregroundStyle(Color.lociInk)
          }
          if labels.count > 2 { Text("+\(labels.count - 2)").font(.lociCaption(11)).foregroundStyle(Color.lociMutedInk) }
        }
      }
      Spacer(minLength: 4)
      Text("Verify").lociCoordStyle(9)
      Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.lociMutedInk).accessibilityHidden(true)
    }
    .lociCard(padding: 14)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityHint("Asks about \(labels.joined(separator: ", "))")
  }
}

/// "Places 1–5 of 12" and Previous / Next (web: TaskPager).
private struct TaskPager: View {
  let page: Int
  let pageCount: Int
  let range: (start: Int, end: Int)
  let total: Int
  let onChange: (Int) -> Void

  var body: some View {
    if total > 0 {
      HStack {
        Text("Places \(range.start)–\(range.end) of \(total)").lociCoordStyle(10)
        Spacer()
        if pageCount > 1 {
          Button("Previous page", systemImage: "chevron.left") { onChange(page - 1) }
            .disabled(page <= 1)
          Text("\(page) of \(pageCount)").font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk).monospacedDigit()
          Button("Next page", systemImage: "chevron.right") { onChange(page + 1) }
            .disabled(page >= pageCount)
        }
      }
      .labelStyle(.iconOnly)
      .buttonStyle(.bordered)
      .tint(Color.lociForest)
      .padding(.top, 4)
    }
  }
}

/// "Does this place exist?": the other half of somebody's submission (web: PendingPlaceCard).
private struct PendingPlaceCard: View {
  let place: PendingPlace
  let outcome: PlaceSubmissionResult?
  let isConfirming: Bool
  let failure: ContributeError?
  let onConfirm: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "questionmark.circle").foregroundStyle(Color.lociCoral).accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(place.name).font(.lociHeadline(16)).foregroundStyle(Color.lociInk)
          if !place.subtitle.isEmpty { Text(place.subtitle).font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk) }
        }
      }
      if let outcome {
        Label(
          outcome.promoted ? "Confirmed. It is on the guide now." : "Thanks — still waiting on one more scout.",
          systemImage: "checkmark.circle.fill"
        )
        .font(.lociCaption(13).weight(.semibold))
        .foregroundStyle(Color.lociForest)
      } else {
        // A refusal that a retry cannot change (no coordinates yet, your own
        // place) takes the button away and says why; anything else keeps it.
        if failure?.canRetry ?? true {
          Button(action: onConfirm) {
            Text(isConfirming ? "Confirming…" : "Yes, it exists")
              .font(.lociBody(15).weight(.semibold))
              .frame(maxWidth: .infinity, minHeight: LociTheme.minTapTarget)
          }
          .lociProminentButton()
          .disabled(isConfirming)
        }
        if let failure {
          Text(failure.message(for: .confirm)).font(.lociCaption(12)).foregroundStyle(Color.lociDestructive)
        }
      }
    }
    .lociCard()
  }
}

/// Propose a place the guide doesn't have (web: AddPlaceForm). Nothing here
/// reaches a recommendation until another scout says the place exists.
struct AddPlaceView: View {
  @State private var store: AddPlaceStore
  @Environment(\.dismiss) private var dismiss

  init(store: AddPlaceStore) {
    _store = State(initialValue: store)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("What is it called?", text: $store.name).textInputAutocapitalization(.words)
          TextField("Which city?", text: $store.cityName).textInputAutocapitalization(.words)
          TextField("What kind of place? (optional)", text: $store.category, prompt: Text("cafe, museum, viewpoint…"))
            .textInputAutocapitalization(.never)
        } footer: {
          Text("It goes live once another scout confirms it exists.")
        }
        Section {
          Button {
            Task { await store.submit() }
          } label: {
            Label(store.isSubmitting ? "Submitting…" : "Add this place", systemImage: "mappin.and.ellipse")
              .frame(maxWidth: .infinity)
          }
          .disabled(!store.draft.isReady || store.isSubmitting)
        }
        if let result = store.result {
          Section {
            Label(result.message, systemImage: result.promoted ? "checkmark.seal.fill" : "clock")
              .foregroundStyle(Color.lociInk)
          }
        }
      }
      .font(.lociBody(15))
      .scrollContentBackground(.hidden)
      .background(Color.lociPaper.ignoresSafeArea())
      .navigationTitle("Add a place")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
      .errorAlert($store.error)
      .onAppear { Analytics.screen("add_place") }
    }
    .presentationDetents([.medium, .large])
  }
}
