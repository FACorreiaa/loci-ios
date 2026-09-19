import SwiftUI
import Connect
import LociConnectProto

public struct DiscoverView: View {
    @State private var query: String = ""
    @State private var selectedCategory: String = "All"
    @State private var pois: [Loci_Poi_POIDetailedInfo] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    private let categories = ["All", "Dining", "Sights", "Lodging", "Culture"]
    private let client: Loci_Poi_PoiserviceClient

    public init(client: Loci_Poi_PoiserviceClient = Loci_Poi_PoiserviceClient(client: ConnectTransport.shared.protocolClient)) {
        self.client = client
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.lociInk.opacity(0.5))
                    TextField("Search destinations, restaurants, sights...", text: $query)
                        .autocorrectionDisabled()
                        .onSubmit {
                            search()
                        }
                    if !query.isEmpty {
                        Button {
                            query = ""
                            search()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.lociInk.opacity(0.4))
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.lociCard)
                .cornerRadius(LociTheme.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: LociTheme.cornerRadius)
                        .stroke(Color.lociBorder.opacity(0.6), lineWidth: LociTheme.borderWidth)
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Category Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { category in
                            Button {
                                selectedCategory = category
                                search()
                            } label: {
                                Text(category)
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(selectedCategory == category ? Color.lociForest : Color.lociCard)
                                    .foregroundColor(selectedCategory == category ? .white : .lociInk)
                                    .cornerRadius(20)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(selectedCategory == category ? Color.clear : Color.lociBorder.opacity(0.6), lineWidth: 1)
                                    )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                // Results / States
                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if let errorMessage {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.largeTitle)
                            .foregroundColor(.lociCoral)
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.lociInk.opacity(0.7))
                        Button("Retry") {
                            search()
                        }
                        .foregroundColor(.lociCoral)
                    }
                    .padding()
                    Spacer()
                } else if pois.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image("LociMascot")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                            .opacity(0.8)
                        Text("Find Your Next Place")
                            .font(.headline)
                            .foregroundColor(.lociInk)
                        Text("Search for cities, sights, cafes, or hidden gems to begin exploring.")
                            .font(.subheadline)
                            .foregroundColor(.lociInk.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(pois, id: \.id) { poi in
                                POICardView(poi: poi)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 24)
                    }
                }
            }
            .background(Color.lociPaper.ignoresSafeArea())
            .navigationTitle("Discover")
        }
        .task {
            if pois.isEmpty {
                search()
            }
        }
    }

    private func search() {
        isLoading = true
        errorMessage = nil
        Task {
            var request = Loci_Poi_SearchPOIRequest()
            request.query = query
            if selectedCategory != "All" {
                request.searchType = selectedCategory.lowercased()
            }

            let response = await client.searchPoi(request: request, headers: [:])
            await MainActor.run {
                self.isLoading = false
                if let error = response.error {
                    self.errorMessage = error.message
                } else if let message = response.message {
                    self.pois = message.pois
                }
            }
        }
    }
}
