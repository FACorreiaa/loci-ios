import LociConnectProto
import SwiftUI

/// The recap's own palette: the traveller's-desk objects keep Loci's brand
/// colours in both appearances, as on the web (`recap.css`, same hex) and in
/// the shared images.
enum RecapPalette {
  static let cream = Color(red: 0xFB / 255, green: 0xF6 / 255, blue: 0xEF / 255)
  static let ink = Color(red: 0x15 / 255, green: 0x1B / 255, blue: 0x23 / 255)
  static let coral = Color(red: 0xF4 / 255, green: 0x7B / 255, blue: 0x5E / 255)
  static let coralDeep = Color(red: 0xB8 / 255, green: 0x45 / 255, blue: 0x2E / 255)
  static let night = Color(red: 0x11 / 255, green: 0x16 / 255, blue: 0x1D / 255)
  static let paper = Color(red: 0xFF / 255, green: 0xFD / 255, blue: 0xF9 / 255)
  static let sand = Color(red: 0xEF / 255, green: 0xE3 / 255, blue: 0xD2 / 255)
  static let post = Color(red: 0xE9 / 255, green: 0xDD / 255, blue: 0xCA / 255)
  /// Holo, the brand's cool partner (web keeps the `--rc-teal` name too).
  static let teal = Color(red: 0x3F / 255, green: 0x6A / 255, blue: 0x93 / 255)
  static let muted = Color(red: 0x5B / 255, green: 0x65 / 255, blue: 0x73 / 255)
}

/// Sizes in hundredths of the card's width, like the web's `cqw`, so a card
/// reads the same on every phone.
struct RecapUnit {
  let u: CGFloat

  func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font { .custom("Outfit", fixedSize: size * u).weight(weight) }
  func italic(_ size: CGFloat) -> Font { .custom("Outfit", fixedSize: size * u).weight(.semibold).italic() }
  func body(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font { .custom("DM Sans", fixedSize: size * u).weight(weight) }
  func mono(_ size: CGFloat) -> Font { .custom("Space Mono", fixedSize: size * u) }
}

extension Loci_Recap_RecapCard {
  /// Drawn on a light ground: the player's progress bars go dark on it.
  var isLight: Bool {
    switch card {
    case .places, .days, .taste, .highlights, .field, .friends, .yearMap, .topCity, .tasteShift, .contributions, .percentile: true
    default: false
    }
  }
}

/// One card. `appeared` flips once the card is on screen, which starts its
/// entrance; with Reduce Motion it is true from the start.
struct RecapCardView: View {
  let recap: Loci_Recap_Recap
  let card: Loci_Recap_RecapCard
  let appeared: Bool
  let unit: RecapUnit

  private var primaryCity: String {
    for c in recap.cards { if case .intro(let i) = c.card { return i.primaryCity } }
    return ""
  }

  var body: some View {
    switch card.card {
    case .intro(let c): IntroCardView(recap: recap, card: c, appeared: appeared, k: unit)
    case .places(let c): PlacesCardView(card: c, appeared: appeared, k: unit)
    case .route(let c): RouteCardView(card: c, city: primaryCity, appeared: appeared, k: unit)
    case .days(let c): DaysCardView(card: c, appeared: appeared, k: unit)
    case .taste(let c): TasteCardView(card: c, city: primaryCity, appeared: appeared, k: unit)
    case .highlights(let c): HighlightsCardView(card: c, appeared: appeared, k: unit)
    case .progress(let c): ProgressCardView(card: c, yearly: recap.kind == .year, appeared: appeared, k: unit)
    case .field(let c): FieldCardView(card: c, appeared: appeared, k: unit)
    case .friends(let c): FriendsCardView(card: c, city: primaryCity, appeared: appeared, k: unit)
    case .outro(let c): OutroCardView(recap: recap, card: c, appeared: appeared, k: unit)
    case .yearMap, .tripsTimeline, .topCity, .tasteShift, .streak, .contributions, .percentile:
      YearCardView(card: card, appeared: appeared, k: unit)
    // Never selected: RecapRules.playable skips what this build cannot draw.
    default: EmptyView()
    }
  }
}

// MARK: - Shared pieces (also used by YearCardView)

struct Kicker: View {
  let text: String
  let k: RecapUnit
  var body: some View { Text(text.uppercased()).font(k.mono(2.8)).tracking(1.4) }
}

/// Rises into place, `delay` seconds after the card appears.
struct Rise: ViewModifier {
  let appeared: Bool
  var delay: Double = 0

  func body(content: Content) -> some View {
    content.opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 14).animation(.easeOut(duration: 0.55).delay(delay), value: appeared)
  }
}

/// Lands like a rubber stamp.
struct Thud: ViewModifier {
  let appeared: Bool
  var delay: Double = 0

  func body(content: Content) -> some View {
    content.scaleEffect(appeared ? 1 : 1.9).opacity(appeared ? 0.9 : 0).blur(radius: appeared ? 0 : 2).animation(
      .spring(response: 0.32, dampingFraction: 0.55).delay(delay),
      value: appeared
    )
  }
}

extension View {
  func rise(_ appeared: Bool, _ delay: Double = 0) -> some View { modifier(Rise(appeared: appeared, delay: delay)) }
  func thud(_ appeared: Bool, _ delay: Double = 0) -> some View { modifier(Thud(appeared: appeared, delay: delay)) }
}

/// A number that counts up when the card appears.
struct CountUp: View, Animatable {
  var value: Double
  var animatableData: Double {
    get { value }
    set { value = newValue }
  }
  var body: some View { Text(Int(value.rounded()).formatted()) }
}

private struct Barcode: View {
  var body: some View {
    Canvas { ctx, size in
      var x: CGFloat = 0
      let widths: [CGFloat] = [2, 1, 3, 1, 2, 2, 1, 3]
      var i = 0
      while x < size.width {
        let w = widths[i % widths.count]
        ctx.fill(Path(CGRect(x: x, y: 0, width: w, height: size.height)), with: .color(RecapPalette.ink.opacity(0.85)))
        x += w + CGFloat((i % 3) + 1)
        i += 1
      }
    }.accessibilityHidden(true)
  }
}

struct CenteredColumn<Content: View>: View {
  let k: RecapUnit
  @ViewBuilder var content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 4 * k.u) { content }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding(
      .horizontal,
      8 * k.u
    ).padding(.top, 12 * k.u).padding(.bottom, 16 * k.u)
  }
}

// MARK: - Cards

private struct IntroCardView: View {
  let recap: Loci_Recap_Recap
  let card: Loci_Recap_IntroCard
  let appeared: Bool
  let k: RecapUnit

  var body: some View {
    ZStack(alignment: .top) {
      RadialGradient(
        colors: [Color(red: 0.17, green: 0.23, blue: 0.26), RecapPalette.night],
        center: .topTrailing,
        startRadius: 0,
        endRadius: 140 * k.u
      )
      Text(card.lede).font(k.italic(6.6)).foregroundStyle(RecapPalette.cream).frame(maxWidth: .infinity, alignment: .leading).padding(
        .horizontal,
        7 * k.u
      ).padding(.top, 22 * k.u).rise(appeared, 0.15)
      tag.padding(.top, 62 * k.u).rotationEffect(.degrees(appeared ? -2 : -24), anchor: UnitPoint(x: 0.5, y: -0.2)).offset(
        y: appeared ? 0 : -120 * k.u
      ).animation(.interpolatingSpring(stiffness: 70, damping: 7), value: appeared)
    }
  }

  private var tag: some View {
    VStack(alignment: .leading, spacing: 2 * k.u) {
      Circle().fill(RecapPalette.night).frame(width: 6 * k.u).overlay(Circle().stroke(Color(red: 0.85, green: 0.8, blue: 0.71), lineWidth: 3)).frame(
        maxWidth: .infinity
      )
      Text(card.shortCode.isEmpty ? "···" : card.shortCode).font(k.display(20, .black)).foregroundStyle(RecapPalette.coralDeep).minimumScaleFactor(
        0.5
      ).lineLimit(1)
      Text(card.primaryCity.isEmpty ? recap.title : card.primaryCity).font(k.display(6.4, .semibold)).lineLimit(2)
      if !card.country.isEmpty { Kicker(text: card.country, k: k).foregroundStyle(RecapPalette.muted) }
      Rectangle().stroke(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])).frame(height: 1).foregroundStyle(RecapPalette.muted.opacity(0.5)).padding(
        .top,
        4 * k.u
      )
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading) {
          Kicker(text: "Days", k: k).foregroundStyle(RecapPalette.muted)
          Text("\(card.dayCount)").font(k.display(5.6, .semibold))
        }
        Spacer()
        VStack(alignment: .leading) {
          Kicker(text: "When", k: k).foregroundStyle(RecapPalette.muted)
          Text(recap.periodLabel).font(k.display(5.6, .semibold))
        }
        Spacer()
      }
      Barcode().frame(height: 7 * k.u).padding(.top, 4 * k.u)
    }.foregroundStyle(RecapPalette.ink).padding(.horizontal, 6 * k.u).padding(.vertical, 5 * k.u).background(
      RecapPalette.paper,
      in: UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 14, bottomTrailingRadius: 14, topTrailingRadius: 10)
    ).shadow(color: .black.opacity(0.35), radius: 14, y: 10).frame(width: 70 * k.u).accessibilityElement(children: .combine)
  }
}

private struct PlacesCardView: View {
  let card: Loci_Recap_PlacesCard
  let appeared: Bool
  let k: RecapUnit

  private struct Spot {
    let x, y, r: CGFloat
    let color: Color
    let round: Bool
  }

  /// Centres in card-width units; the card is about 178 units tall, and the
  /// count and headline take the top 70.
  private let spots: [Spot] = [
    Spot(x: 26, y: 88, r: -12, color: RecapPalette.coralDeep, round: true),
    Spot(x: 72, y: 86, r: 7, color: RecapPalette.ink, round: false),
    Spot(x: 52, y: 112, r: -4, color: RecapPalette.coralDeep, round: false),
    Spot(x: 24, y: 136, r: -9, color: RecapPalette.teal, round: false),
    Spot(x: 74, y: 136, r: 14, color: RecapPalette.ink, round: true),
    Spot(x: 48, y: 158, r: 6, color: RecapPalette.teal, round: true),
  ]

  var body: some View {
    let byStops = card.placesCount == 0
    ZStack(alignment: .topLeading) {
      RecapPalette.sand
      VStack(alignment: .leading, spacing: 3 * k.u) {
        HStack(alignment: .firstTextBaseline, spacing: 2 * k.u) {
          CountUp(value: appeared ? Double(byStops ? card.stopsDone : card.placesCount) : 0).animation(.easeOut(duration: 1.1), value: appeared).font(
            k.display(30, .black)
          )
          Text(byStops ? "of \(card.stopsPlanned) stops" : "places").font(k.italic(7.5)).foregroundStyle(RecapPalette.coralDeep)
        }
        if !card.headline.isEmpty { Text(card.headline).font(k.body(4.1)) }
      }.padding(.horizontal, 7 * k.u).padding(.top, 18 * k.u).rise(appeared)
      ForEach(Array(card.groups.prefix(spots.count).enumerated()), id: \.offset) { i, group in
        stamp(group, spots[i]).position(x: spots[i].x * k.u, y: spots[i].y * k.u).thud(appeared, 0.9 + Double(i) * 0.42)
      }
    }.foregroundStyle(RecapPalette.ink)
  }

  private func stamp(_ g: Loci_Recap_PlaceGroup, _ s: Spot) -> some View {
    VStack(spacing: 0.6 * k.u) {
      Text(g.label).font(k.display(4.4, .heavy)).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.7)
      Text(g.firstDate.isEmpty ? "\(g.placesCount) place\(g.placesCount == 1 ? "" : "s")" : Self.short(g.firstDate)).font(k.mono(2.4)).textCase(
        .uppercase
      )
    }.foregroundStyle(s.color).padding(3 * k.u).frame(width: s.round ? 27 * k.u : nil, height: s.round ? 27 * k.u : nil).frame(maxWidth: 40 * k.u)
      .overlay {
        if s.round {
          Circle().stroke(s.color, lineWidth: 2.5).overlay(Circle().inset(by: 1.6 * k.u).stroke(s.color, lineWidth: 1.2))
        } else {
          RoundedRectangle(cornerRadius: 4).stroke(s.color, lineWidth: 2.5).overlay(
            RoundedRectangle(cornerRadius: 3).inset(by: 4).stroke(s.color, lineWidth: 1)
          )
        }
      }.rotationEffect(.degrees(s.r)).accessibilityElement(children: .combine)
  }

  static func short(_ iso: String) -> String {
    guard let date = RecapRules.localDate(iso, calendar: Calendar(identifier: .gregorian)) else { return "" }
    return date.formatted(.dateTime.day().month(.abbreviated))
  }
}

private struct RouteCardView: View {
  let card: Loci_Recap_RouteCard
  let city: String
  let appeared: Bool
  let k: RecapUnit

  var body: some View {
    ZStack {
      RecapPalette.night
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Kicker(text: "Boarding pass", k: k)
          Spacer()
          Kicker(text: "Loci", k: k)
        }.foregroundStyle(RecapPalette.cream).padding(.horizontal, 6 * k.u).padding(.vertical, 3.5 * k.u).background(RecapPalette.coralDeep)
        VStack(alignment: .leading, spacing: 3 * k.u) {
          legs
          Text(RecapRules.km(card.distanceKm)).font(k.display(17, .black)).foregroundStyle(RecapPalette.coralDeep).minimumScaleFactor(0.5).lineLimit(
            1
          )
          Kicker(text: RecapRules.basisCaption(card.basis), k: k).foregroundStyle(RecapPalette.muted)
          if card.points.count >= 2 {
            RouteSketch(points: card.points, progress: appeared ? 1 : 0).stroke(
              RecapPalette.coral,
              style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            ).animation(.easeOut(duration: 1.6).delay(0.6), value: appeared).frame(maxWidth: .infinity, maxHeight: .infinity)
          } else {
            Spacer(minLength: 0)
          }
          Barcode().frame(height: 7 * k.u)
        }.padding(6 * k.u)
      }.foregroundStyle(RecapPalette.ink).background(RecapPalette.paper).clipShape(RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 7 * k.u)
        .padding(.top, 20 * k.u).padding(.bottom, 26 * k.u).offset(y: appeared ? 0 : 40 * k.u).opacity(appeared ? 1 : 0).animation(
          .spring(response: 0.7, dampingFraction: 0.8),
          value: appeared
        )
    }
  }

  @ViewBuilder private var legs: some View {
    if let first = card.points.first?.label, let last = card.points.last?.label, card.points.count >= 2 {
      HStack {
        Text(first).lineLimit(1)
        Text("→").accessibilityHidden(true)
        Text(last).lineLimit(1)
      }.font(k.display(5, .semibold))
    } else if !city.isEmpty {
      Text("Around \(city)").font(k.display(5, .semibold))
    }
  }
}

/// The route drawn as a line, projected to fit (equirectangular, cos-lat corrected).
private struct RouteSketch: Shape {
  let points: [Loci_Recap_RoutePoint]
  var progress: CGFloat
  var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }

  func path(in rect: CGRect) -> Path {
    let midLat = points.map(\.latitude).reduce(0, +) / Double(max(points.count, 1))
    let k = cos(midLat * .pi / 180)
    let xs = points.map { $0.longitude * k }
    let ys = points.map { -$0.latitude }
    guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return Path() }
    let inset = rect.insetBy(dx: 8, dy: 8)
    let span = max(maxX - minX, (maxY - minY) * Double(inset.width / max(inset.height, 1)), 1e-6)
    let scale = Double(inset.width) / span
    let ox = Double(inset.minX) + (Double(inset.width) - (maxX - minX) * scale) / 2
    let oy = Double(inset.minY) + (Double(inset.height) - (maxY - minY) * scale) / 2
    var path = Path()
    for (i, x) in xs.enumerated() {
      let p = CGPoint(x: ox + (x - minX) * scale, y: oy + (ys[i] - minY) * scale)
      if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
    }
    return path.trimmedPath(from: 0, to: progress)
  }
}

private struct DaysCardView: View {
  let card: Loci_Recap_DaysCard
  let appeared: Bool
  let k: RecapUnit

  var body: some View {
    ZStack {
      RecapPalette.cream
      CenteredColumn(k: k) {
        HStack(alignment: .firstTextBaseline, spacing: 2 * k.u) {
          Text("\(card.daysCompleted)").font(k.display(30, .black))
          Text("of \(card.daysTotal) days").font(k.italic(7.5)).foregroundStyle(RecapPalette.coralDeep)
        }
        Text(card.headline).font(k.body(4.1))
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 15 * k.u), spacing: 2.5 * k.u)], spacing: 2.5 * k.u) {
          ForEach(Array(card.days.prefix(12).enumerated()), id: \.offset) { i, d in
            VStack(spacing: 0.5 * k.u) {
              Text("DAY").font(k.mono(2.4))
              Text("\(d.dayNumber)").font(k.display(6, .bold))
              Text(d.stopsDone > 0 ? "\(d.stopsDone) stops" : (d.completed ? "walked" : " ")).font(k.mono(2.2))
            }.padding(.vertical, 2.5 * k.u).frame(maxWidth: .infinity).foregroundStyle(d.completed ? RecapPalette.cream : RecapPalette.ink)
              .background(d.completed ? RecapPalette.ink : .clear, in: RoundedRectangle(cornerRadius: 6)).overlay(
                RoundedRectangle(cornerRadius: 6).stroke(RecapPalette.ink, lineWidth: 1.5)
              ).rise(appeared, 0.5 + Double(i) * 0.12).accessibilityElement(children: .combine)
          }
        }.padding(.top, 4 * k.u)
      }.foregroundStyle(RecapPalette.ink).rise(appeared)
    }
  }
}

private struct TasteCardView: View {
  let card: Loci_Recap_TasteCard
  let city: String
  let appeared: Bool
  let k: RecapUnit

  var body: some View {
    ZStack(alignment: .topLeading) {
      RecapPalette.post
      Kicker(text: card.fromPeriod ? "On this trip, Loci noticed" : "Your taste, so far", k: k).foregroundStyle(RecapPalette.ink.opacity(0.7))
        .padding(.horizontal, 7 * k.u).padding(.top, 18 * k.u)
      postcard.padding(.horizontal, 6 * k.u).padding(.top, 26 * k.u).padding(.bottom, 26 * k.u).rotationEffect(.degrees(appeared ? -2 : 14)).offset(
        x: appeared ? 0 : 40 * k.u,
        y: appeared ? 0 : 30 * k.u
      ).opacity(appeared ? 1 : 0).animation(.spring(response: 0.8, dampingFraction: 0.8), value: appeared)
    }
  }

  private var postcard: some View {
    VStack(alignment: .leading, spacing: 4 * k.u) {
      HStack {
        Spacer()
        Text(String(city.prefix(2)).uppercased()).font(k.display(4.6, .black)).foregroundStyle(RecapPalette.paper).frame(
          width: 15 * k.u,
          height: 18 * k.u
        ).background(RecapPalette.coral).overlay(Rectangle().inset(by: 1).stroke(RecapPalette.paper, style: StrokeStyle(lineWidth: 3, dash: [2, 3])))
          .accessibilityHidden(true)
      }
      Text(card.headline).font(k.italic(6.8)).fixedSize(horizontal: false, vertical: true)
      ForEach(Array(card.traits.enumerated()), id: \.offset) { i, t in
        VStack(alignment: .leading, spacing: 1.3 * k.u) {
          Text(t.label).font(k.display(5, .semibold))
          GeometryReader { geo in
            ZStack(alignment: .leading) {
              Rectangle().fill(RecapPalette.sand)
              Rectangle().fill(RecapPalette.coralDeep).frame(width: geo.size.width * (appeared ? min(max(t.strength, 0.1), 1) : 0)).animation(
                .easeOut(duration: 0.9).delay(1.2 + Double(i) * 0.45),
                value: appeared
              )
            }
          }.frame(height: 2)
          HStack {
            Text(RecapRules.evidence(t.evidenceCount, t.evidenceKind).uppercased())
            Spacer()
            Text(RecapRules.trend(t.trend).uppercased())
          }.font(k.mono(2.4)).foregroundStyle(RecapPalette.muted)
        }.rise(appeared, 1 + Double(i) * 0.45).accessibilityElement(children: .combine)
      }
      Spacer(minLength: 0)
      Text("Your taste, as Loci sees it").font(k.italic(3.8)).foregroundStyle(RecapPalette.muted)
    }.foregroundStyle(RecapPalette.ink).padding(6 * k.u).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(
      RecapPalette.paper,
      in: RoundedRectangle(cornerRadius: 6)
    ).shadow(color: RecapPalette.ink.opacity(0.35), radius: 16, y: 12)
  }
}

private struct HighlightsCardView: View {
  let card: Loci_Recap_HighlightsCard
  let appeared: Bool
  let k: RecapUnit

  private func reason(_ r: Loci_Recap_HighlightReason) -> String {
    switch r {
    case .favorited: "Kept"
    case .reviewed: "Reviewed"
    case .firstVisit: "First visit"
    default: ""
    }
  }

  var body: some View {
    ZStack(alignment: .topLeading) {
      RecapPalette.cream
      VStack(alignment: .leading, spacing: 5 * k.u) {
        Kicker(text: card.headline, k: k).foregroundStyle(RecapPalette.ink.opacity(0.7))
        ForEach(Array(card.highlights.enumerated()), id: \.offset) { i, h in
          VStack(alignment: .leading, spacing: 1 * k.u) {
            Text(h.name).font(k.display(5.4, .semibold)).lineLimit(2)
            HStack(spacing: 4) {
              Text(
                [h.category.replacingOccurrences(of: "_", with: " "), reason(h.reason)].filter { !$0.isEmpty }.joined(separator: " · ").uppercased()
              )
              if h.rating > 0 {
                Text(String(repeating: "★", count: Int(min(h.rating, 5)))).foregroundStyle(RecapPalette.coralDeep).accessibilityLabel(
                  "\(h.rating) out of 5"
                )
              }
            }.font(k.mono(2.4)).foregroundStyle(RecapPalette.muted)
          }.padding(5 * k.u).frame(maxWidth: .infinity, alignment: .leading).background(RecapPalette.paper).overlay(alignment: .top) {
            Circle().fill(RecapPalette.coralDeep).frame(width: 3.4 * k.u).offset(y: -1.7 * k.u)
          }.shadow(color: RecapPalette.ink.opacity(0.25), radius: 10, y: 8).rotationEffect(.degrees([-2, 1.5, -1][i % 3])).rise(
            appeared,
            0.3 + Double(i) * 0.35
          ).accessibilityElement(children: .combine)
        }
      }.foregroundStyle(RecapPalette.ink).padding(.horizontal, 8 * k.u).padding(.top, 18 * k.u)
    }
  }
}

private struct ProgressCardView: View {
  let card: Loci_Recap_ProgressCard
  /// On a year in review the points are the year's, not a trip's.
  var yearly = false
  let appeared: Bool
  let k: RecapUnit

  var body: some View {
    ZStack {
      RecapPalette.night
      CenteredColumn(k: k) {
        Kicker(text: yearly ? "Points this year" : "Points on this trip", k: k).opacity(0.7)
        CountUp(value: appeared ? Double(card.points) : 0).animation(.easeOut(duration: 1.1), value: appeared).font(k.display(24, .black))
          .foregroundStyle(RecapPalette.coral)
        Text(card.headline).font(k.body(4.1))
        HStack(spacing: 3 * k.u) {
          ForEach(Array(card.badges.enumerated()), id: \.offset) { i, b in
            Text(b.label.uppercased()).font(k.mono(2.3)).multilineTextAlignment(.center).padding(3 * k.u).frame(width: 24 * k.u, height: 24 * k.u)
              .overlay(
                Circle().stroke(RecapPalette.coral, lineWidth: 2).overlay(Circle().inset(by: 1.2 * k.u).stroke(RecapPalette.coral, lineWidth: 1))
              ).foregroundStyle(RecapPalette.coral).thud(appeared, 0.7 + Double(i) * 0.3)
          }
        }
        if card.streakDays > 1 { Kicker(text: "\(card.streakDays)-day streak along the way", k: k) }
      }.foregroundStyle(RecapPalette.cream).rise(appeared)
    }
  }
}

private struct FieldCardView: View {
  let card: Loci_Recap_FieldCard
  let appeared: Bool
  let k: RecapUnit

  var body: some View {
    ZStack {
      RecapPalette.sand
      CenteredColumn(k: k) {
        Kicker(text: "Your field rank in \(card.cityName)", k: k).opacity(0.7)
        VStack(spacing: 1 * k.u) {
          Text(card.rankLabel).font(k.display(9, .black))
          Text("\(card.score.formatted()) field points".uppercased()).font(k.mono(3))
        }.foregroundStyle(RecapPalette.coralDeep).frame(width: 46 * k.u, height: 46 * k.u).overlay(
          Circle().stroke(RecapPalette.coralDeep, lineWidth: 2.5).overlay(
            Circle().inset(by: 1.6 * k.u).stroke(RecapPalette.coralDeep, lineWidth: 1.2)
          )
        ).rotationEffect(.degrees(-8)).thud(appeared, 0.5)
        Text(card.headline).font(k.body(4.1))
        if card.placesKept > 0 || card.daysFinished > 0 {
          Kicker(text: "\(card.placesKept) places kept · \(card.daysFinished) days finished", k: k).opacity(0.7)
        }
      }.foregroundStyle(RecapPalette.ink).rise(appeared)
    }
  }
}

private struct FriendsCardView: View {
  let card: Loci_Recap_FriendsCard
  let city: String
  let appeared: Bool
  let k: RecapUnit

  var body: some View {
    ZStack {
      RecapPalette.cream
      CenteredColumn(k: k) {
        Text("\(card.friendsBeenCount)").font(k.display(24, .black))
        Text(card.headline.isEmpty ? "of your friends have \(city.isEmpty ? "this city" : city) on a trip too." : card.headline).font(k.body(4.1))
        HStack(spacing: 2.5 * k.u) {
          if card.friends.isEmpty {
            ForEach(0..<min(5, Int(card.friendsBeenCount)), id: \.self) { i in
              Circle().strokeBorder(RecapPalette.muted, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])).background(Circle().fill(RecapPalette.sand))
                .frame(width: 14 * k.u, height: 14 * k.u).thud(appeared, 0.6 + Double(i) * 0.18)
            }
          } else {
            ForEach(Array(card.friends.prefix(5).enumerated()), id: \.offset) { i, f in
              Text(RecapRules.initials(f.displayName)).font(k.display(5, .semibold)).foregroundStyle(RecapPalette.cream).frame(
                width: 14 * k.u,
                height: 14 * k.u
              ).background(Circle().fill(RecapPalette.ink)).accessibilityLabel(f.displayName).thud(appeared, 0.6 + Double(i) * 0.18)
            }
          }
        }.accessibilityElement(children: .combine)
      }.foregroundStyle(RecapPalette.ink).rise(appeared)
    }
  }
}

private struct OutroCardView: View {
  let recap: Loci_Recap_Recap
  let card: Loci_Recap_OutroCard
  let appeared: Bool
  let k: RecapUnit

  var body: some View {
    ZStack {
      RecapPalette.night
      CenteredColumn(k: k) {
        Kicker(text: recap.kind == .year ? recap.title : "\(recap.title) · \(recap.periodLabel)", k: k).opacity(0.7)
        Text(card.headline).font(k.display(10, .semibold))
        if !card.summaryLine.isEmpty { Kicker(text: card.summaryLine, k: k).foregroundStyle(RecapPalette.coral) }
      }.foregroundStyle(RecapPalette.cream).rise(appeared)
    }
  }
}
