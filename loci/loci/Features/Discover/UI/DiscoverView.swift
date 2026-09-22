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

  @State private var path: [SessionLink] = []
  @State private var page: Loci_Discover_DiscoverPageData?
  @State private var city = ""
  @State private var composerSeed = ""
  @State private var error: String?

  var body: some View {
    NavigationStack(path: $path) {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          hero
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
      .refreshable { await load() }
      .task { if page == nil { await load() } }
      .errorAlert($error)
    }
  }

  // MARK: - Sections

  private var hero: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Where to next?").font(.lociDisplay(30)).foregroundStyle(Color.lociInk)
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
