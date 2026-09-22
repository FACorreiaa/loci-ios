import LociConnectProto
import SwiftUI

/// The moving "In season" strip (web: Dashboard/InSeasonBand). Destinations
/// with a reason to go this month, plus the cities people asked about this
/// week. Tapping a chip puts its request in the search box; nothing runs
/// until the person sends it.
///
/// Motion: one slow linear loop, driven by `TimelineView` so it can be paused
/// (touch, off-screen) and resumed from where it is. With Reduce Motion, or
/// too few chips to fill a row, it is a plain horizontal scroll instead.
struct InSeasonBand: View {
  /// Where a tapped chip's prompt goes.
  @Binding var seed: String

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var trending: [InSeasonTrending]?
  @State private var isPaused = false
  @State private var isVisible = false

  private var items: [InSeasonItem] {
    InSeason.items(picks: SeasonalPicks.picks(forMonth: Calendar.current.component(.month, from: Date())), trending: trending)
  }

  var body: some View {
    let items = items
    if !items.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text("In season · \(InSeason.monthLabel())").lociCoordStyle(10)
        if reduceMotion || !InSeason.needsMarquee(count: items.count) {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { ForEach(items) { chip($0) } }.padding(.vertical, 4).padding(.horizontal, LociTheme.defaultPadding)
          }
          .padding(.horizontal, -LociTheme.defaultPadding)
        } else {
          Marquee(loopDuration: InSeason.loopDuration(count: items.count), spacing: 8, isPaused: isPaused || !isVisible) {
            ForEach(items) { chip($0) }
          }
          .frame(height: 44)
          // Fade the ends so chips enter and leave softly (web: the mask-image).
          .mask(
            LinearGradient(
              stops: [
                .init(color: .clear, location: 0), .init(color: .black, location: 0.08),
                .init(color: .black, location: 0.92), .init(color: .clear, location: 1),
              ],
              startPoint: .leading,
              endPoint: .trailing
            )
          )
          // Run edge to edge under the screen margin, so chips fade at the
          // screen's edge rather than cutting at the text column.
          .padding(.horizontal, -LociTheme.defaultPadding)
          .onAppear { isVisible = true }
          .onDisappear { isVisible = false }
        }
        Text("Tap one to put it in the box above.").font(.lociCaption(11)).foregroundStyle(Color.lociMutedInk)
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("In season")
      .task { await loadTrending() }
    }
  }

  private func chip(_ item: InSeasonItem) -> some View {
    Button {
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      seed = item.prompt
    } label: {
      HStack(spacing: 6) {
        Text(item.emoji)
        if !item.flag.isEmpty { Text(item.flag) }
        Text(item.city).font(.lociHeadline(14)).foregroundStyle(Color.lociInk)
        Text("· \(item.hook)").font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk)
        if item.planned > 0, item.hook != "planned this week" {
          Text("· \(item.planned) planned this week").font(.lociCaption(11)).foregroundStyle(Color.lociMutedInk)
        }
      }
      .lineLimit(1)
      .fixedSize()
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(Color.lociCard, in: Capsule())
      .overlay(Capsule().stroke(Color.lociBorder, lineWidth: LociTheme.borderWidth))
    }
    .buttonStyle(PressScaleButtonStyle())
    .accessibilityLabel("Plan \(item.city): \(item.hook)")
    // A touch on the strip holds it still, like hover on web; lifting releases it.
    .simultaneousGesture(
      DragGesture(minimumDistance: 0)
        .onChanged { _ in isPaused = true }
        .onEnded { _ in isPaused = false }
    )
  }

  /// web: useTrendingDiscoveries(8). Without it the strip is the curated table alone.
  private func loadTrending() async {
    var request = Loci_Discover_GetTrendingRequest()
    request.limit = 8
    let response = try? await rpc("", request) {
      await Loci_Discover_DiscoverServiceClient(client: ConnectTransport.shared.protocolClient).getTrending(request: $0, headers: [:])
    }
    trending = response?.trending.map { InSeasonTrending(cityName: $0.cityName, searchCount: Int($0.searchCount), emoji: $0.emoji) }
  }
}

/// Feedback on touch-down: the chip settles to 98% while pressed
/// (NATIVE_DESIGN `press`: 150ms, scale 0.98; off under Reduce Motion).
struct PressScaleButtonStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
      .opacity(configuration.isPressed ? 0.9 : 1)
      .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
  }
}

/// Content that scrolls left forever. The content is laid out twice with the
/// same gap between and after the copies, so when the first copy has fully
/// left, the second sits exactly where the first began (web: the track's
/// `padding-inline-end` equals its `gap`).
struct Marquee<Content: View>: View {
  let loopDuration: TimeInterval
  let spacing: CGFloat
  let isPaused: Bool
  @ViewBuilder let content: () -> Content

  @State private var copyWidth: CGFloat = 0
  /// Loop time banked before the current run; grows only when a run pauses.
  @State private var banked: TimeInterval = 0
  /// When the current run started; nil while paused.
  @State private var runningSince: Date?

  var body: some View {
    // The track is an overlay, so its width (two copies of the content) never
    // reaches the layout; the strip takes whatever width its parent gives it.
    Color.clear
      .overlay(alignment: .leading) {
        TimelineView(.animation(paused: isPaused)) { context in
          HStack(spacing: spacing) {
            copy
            copy
          }
          .fixedSize()
          .offset(x: copyWidth > 0 ? -((copyWidth + spacing) * progress(at: context.date)) : 0)
        }
      }
      .clipped()
    .onAppear { if !isPaused { runningSince = Date() } }
    .onChange(of: isPaused) { _, paused in
      let now = Date()
      if paused {
        if let runningSince { banked += now.timeIntervalSince(runningSince) }
        runningSince = nil
      } else {
        runningSince = now
      }
    }
  }

  private var copy: some View {
    HStack(spacing: spacing) { content() }
      .fixedSize()
      .background(
        GeometryReader { proxy in
          Color.clear.onAppear { copyWidth = proxy.size.width }.onChange(of: proxy.size.width) { _, width in copyWidth = width }
        }
      )
  }

  /// Fraction of one loop completed, read from the clock: nothing is written
  /// during a frame, and a pause holds the strip where it is.
  private func progress(at date: Date) -> Double {
    let elapsed = banked + (runningSince.map { date.timeIntervalSince($0) } ?? 0)
    let loop = max(loopDuration, 1)
    return elapsed.truncatingRemainder(dividingBy: loop) / loop
  }
}
