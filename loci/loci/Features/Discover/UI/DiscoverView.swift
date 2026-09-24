import LociConnectProto
import SwiftUI

/// Discover (web: /discover). DiscoverService.GetDiscoverPage for trending
/// cities, featured collections and recent discoveries; a search box that runs
/// ChatService.StreamChat without a profile, as web's Discover does; quick
/// categories that fill the query; entry points to Nearby and Compare.
struct DiscoverView: View {
  /// web: routes/discover.tsx `categories`
  static let quickCategories: [(name: String, symbol: String)] = [
    ("Restaurants", "fork.knife"), ("Hotels", "bed.double"), ("Activities", "target"), ("Attractions", "building.columns"),
    ("Nightlife", "moon.stars"), ("Shopping", "bag"), ("Museums", "paintpalette"), ("Parks", "tree"),
    ("Beaches", "beach.umbrella"), ("Adventure", "mountain.2"), ("Cultural", "theatermasks"), ("Markets", "storefront"),
  ]

  /// Shown until the first search, so a new user sees what a good prompt looks
  /// like. The first is web's landing placeholder, word for word.
  static let examplePrompts = [
    "Three chill days in Lisbon for food and views",
    "A rainy afternoon in Porto",
    "A weekend of markets and street food in Mexico City",
  ]

  @State private var path: [SessionLink] = []
  @State private var page: Loci_Discover_DiscoverPageData?
  @State private var city = ""
  @State private var composerSeed = ""
  @State private var error: String?
  @State private var here = HereBriefModel()
  @State private var linked: AppLink?
  private let router = AppRouter.shared

  var body: some View {
    NavigationStack(path: $path) {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          hero
          if page?.recentDiscoveries.isEmpty == true { examplesSection }
          HereBriefSection(model: here)
          InSeasonBand(seed: $composerSeed)
          quickCategoriesSection
          if let page {
            trendingSection(page.trending)
            featuredSection(page.featured)
            recentSection(page.recentDiscoveries)
          } else {
            ProgressView().frame(maxWidth: .infinity)
          }
        }
        .padding(LociTheme.defaultPadding)
      }
      .background(Color.lociPaper.ignoresSafeArea())
      .navigationTitle("Discover")
      .navigationDestination(for: SessionLink.self) { SearchResultsView(link: $0) }
      .refreshable {
        async let brief: Void = here.load()
        await load()
        await brief
      }
      .task {
        async let brief: Void = here.load()
        if page == nil { await load() }
        await brief
      }
      .errorAlert($error)
      .navigationDestination(item: $linked) { AppLinkDestination(link: $0) }
      .onAppear(perform: openPending)
      .onChange(of: router.pendingLink) { openPending() }
    }
  }

  /// A `/packs/:slug` link pushes the pack over Discover.
  private func openPending() {
    if let link = router.takeLink(for: .discover) { linked = link }
  }

  // MARK: - Sections

  private var hero: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Where to next?").font(.lociDisplay(30)).foregroundStyle(Color.lociInk)
      if !here.placeName.isEmpty {
        Text(here.placeName).font(.lociCaption(13)).foregroundStyle(Color.lociForest)
      }
      TextField("City (optional)", text: $city)
        .font(.lociBody())
        .textContentType(.addressCity)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.lociCard, in: RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous).stroke(Color.lociBorder))
      SearchComposer(
        placeholder: "Restaurants, hotels, a day out…",
        seed: $composerSeed,
        cityName: city.trimmingCharacters(in: .whitespaces).isEmpty ? nil : city.trimmingCharacters(in: .whitespaces),
        useDefaultProfile: false
      ) { path.append($0) }
      HStack(spacing: 12) {
        NavigationLink { NearbyView() } label: { Label("Near me", systemImage: "location") }
        NavigationLink { CompareView() } label: { Label("Weekend: compare two cities", systemImage: "arrow.left.arrow.right") }
      }
      .font(.lociCaption(13))
      .buttonStyle(.bordered)
      .tint(.lociForest)
      packsEntry
    }
  }

  /// City Packs (web: /packs): ready-made itineraries (`18-city-packs.md`).
  private var packsEntry: some View {
    NavigationLink {
      PacksView()
    } label: {
      HStack(spacing: 12) {
        Image(systemName: PacksView.symbol).font(.title3).foregroundStyle(Color.lociForest).accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text("City Packs").font(.lociHeadline(16)).foregroundStyle(Color.lociInk)
          Text("Ready-made trips, day by day").font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
        }
        Spacer()
        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.lociMutedInk).accessibilityHidden(true)
      }
      .lociCard(padding: 12)
    }
    .buttonStyle(.plain)
  }

  private var examplesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Try one").font(.lociHeadline())
      ForEach(Self.examplePrompts, id: \.self) { prompt in
        Button {
          composerSeed = prompt
        } label: {
          Label(prompt, systemImage: "sparkle")
            .font(.lociBody(15))
            .foregroundStyle(Color.lociInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lociCard(padding: 12)
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var quickCategoriesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Quick categories").font(.lociHeadline())
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(Self.quickCategories, id: \.name) { category in
            Button {
              composerSeed = category.name
            } label: {
              Label(category.name, systemImage: category.symbol).font(.lociCaption(13))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.lociSage, in: Capsule())
                .foregroundStyle(Color.lociInk)
            }
          }
        }
      }
    }
  }

  @ViewBuilder private func trendingSection(_ trending: [Loci_Discover_TrendingDiscovery]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Trending today").font(.lociHeadline())
      if trending.isEmpty {
        Text("No trending discoveries yet today").foregroundStyle(Color.lociMutedInk)
      } else {
        ForEach(trending, id: \.cityName) { item in
          Button {
            city = item.cityName
          } label: {
            HStack {
              Text(item.emoji)
              Text(item.cityName).font(.lociBody()).foregroundStyle(Color.lociInk)
              Spacer()
              Text("\(item.searchCount) searches").lociCoordStyle(10)
            }
            .lociCard(padding: 12)
          }
        }
      }
    }
  }

  @ViewBuilder private func featuredSection(_ featured: [Loci_Discover_FeaturedCollection]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Featured collections").font(.lociHeadline())
      if featured.isEmpty {
        Text("No featured collections available").foregroundStyle(Color.lociMutedInk)
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 12) {
            ForEach(featured, id: \.category) { item in
              Button {
                composerSeed = item.title
              } label: {
                VStack(alignment: .leading, spacing: 6) {
                  Text(item.emoji).font(.title)
                  Text(item.title).font(.lociHeadline(15)).foregroundStyle(Color.lociInk).multilineTextAlignment(.leading)
                  Text("\(item.itemCount) places").lociCoordStyle(10)
                }
                .frame(width: 160, alignment: .leading)
                .lociCard(padding: 14)
              }
            }
          }
        }
      }
    }
  }

  @ViewBuilder private func recentSection(_ sessions: [Loci_Chat_ChatSession]) -> some View {
    if !sessions.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text("Your recent discoveries").font(.lociHeadline())
        ForEach(sessions, id: \.id) { session in
          NavigationLink(value: AssistantView.link(for: session)) {
            SessionRow(session: session).frame(maxWidth: .infinity, alignment: .leading).lociCard(padding: 12)
          }
        }
      }
    }
  }

  private func load() async {
    do {
      page = try await rpc("Could not load Discover.") {
        await Loci_Discover_DiscoverServiceClient(client: ConnectTransport.shared.protocolClient).getDiscoverPage(request: .init(), headers: [:])
      }.data
    } catch {
      page = Loci_Discover_DiscoverPageData()
      self.error = error.userMessage
    }
  }
}
