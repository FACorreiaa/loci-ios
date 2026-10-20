import LociConnectProto
import SwiftUI

/// The year-in-review cards. Same desk, bigger drawer: a wall map, a
/// calendar strip, a postcard of the year's city, a ledger and a seal, as the
/// server draws them (render/cards_year.go).
struct YearCardView: View {
  let card: Loci_Recap_RecapCard
  let appeared: Bool
  let k: RecapUnit

  var body: some View {
    switch card.card {
    case .yearMap(let c): YearMapCardView(card: c, appeared: appeared, k: k)
    case .tripsTimeline(let c): TripsTimelineCardView(card: c, appeared: appeared, k: k)
    case .topCity(let c): TopCityCardView(card: c, appeared: appeared, k: k)
    case .tasteShift(let c): TasteShiftCardView(card: c, appeared: appeared, k: k)
    case .streak(let c): StreakCardView(card: c, appeared: appeared, k: k)
    case .contributions(let c): ContributionsCardView(card: c, appeared: appeared, k: k)
    case .percentile(let c): PercentileCardView(card: c, appeared: appeared, k: k)
    default: EmptyView()
    }
  }
}

// MARK: - Pieces

/// "June" or "Jun" in the reader's language. A bare gregorian calendar has no
/// locale, and its month symbols come out as "M06".
private func monthName(_ month: Int, short: Bool = false) -> String {
  guard let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: month, day: 1)) else { return "" }
  return date.formatted(.dateTime.month(short ? .abbreviated : .wide))
}

/// "6 cities", "1 day away".
private func count(_ n: Int32, _ one: String, _ many: String) -> String { "\(Int(n).formatted()) \(n == 1 ? one : many)" }

/// A big number with its noun beside it, as every year card opens.
private struct Headcount: View {
  let value: Int32
  let noun: String
  let numberColor: Color
  let nounColor: Color
  let appeared: Bool
  let k: RecapUnit

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 2 * k.u) {
      CountUp(value: appeared ? Double(max(value, 0)) : 0).animation(.easeOut(duration: 1.1), value: appeared).font(k.display(28, .black))
        .foregroundStyle(numberColor).lineLimit(1).minimumScaleFactor(0.5)
      Text(noun).font(k.italic(8)).foregroundStyle(nounColor).lineLimit(1).minimumScaleFactor(0.6)
    }.accessibilityElement(children: .ignore).accessibilityLabel("\(max(value, 0)) \(noun)")
  }
}

/// Number over caption, for the rows of stats under a card.
private struct Stat: View {
  let value: String
  let caption: String
  let k: RecapUnit

  var body: some View {
    VStack(spacing: 1 * k.u) {
      Text(value).font(k.display(10, .black)).lineLimit(1).minimumScaleFactor(0.4)
      Kicker(text: caption, k: k).opacity(0.7)
    }.frame(maxWidth: .infinity).accessibilityElement(children: .combine)
  }
}

/// The card's sentence, under its numbers.
private struct Headline: View {
  let text: String
  let k: RecapUnit
  var body: some View { Text(text).font(k.body(4.1)).fixedSize(horizontal: false, vertical: true) }
}

private struct DashedRule: View {
  var vertical = false
  var body: some View {
    Rectangle().stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 4])).frame(width: vertical ? 1 : nil, height: vertical ? nil : 1).opacity(0.35)
      .accessibilityHidden(true)
  }
}

/// Fits lat/lon points into a rect (equirectangular, cos-lat corrected),
/// like the route sketch, but as points for pins.
enum PinProjection {
  static func points(_ pts: [Loci_Recap_RoutePoint], in rect: CGRect) -> [CGPoint] {
    let valid = pts.filter { $0.latitude.isFinite && $0.longitude.isFinite }
    guard !valid.isEmpty else { return [] }
    let midLat = valid.map(\.latitude).reduce(0, +) / Double(valid.count)
    let c = cos(midLat * .pi / 180)
    let xs = valid.map { $0.longitude * c }
    let ys = valid.map { -$0.latitude }
    guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return [] }
    let span = max(maxX - minX, (maxY - minY) * Double(rect.width / max(rect.height, 1)), 1e-6)
    let scale = Double(rect.width) / span
    let ox = Double(rect.minX) + (Double(rect.width) - (maxX - minX) * scale) / 2
    let oy = Double(rect.minY) + (Double(rect.height) - (maxY - minY) * scale) / 2
    return xs.indices.map { CGPoint(x: ox + (xs[$0] - minX) * scale, y: oy + (ys[$0] - minY) * scale) }
  }
}

/// A seal's edge: a circle with `bumps` scallops.
private struct Scallop: Shape {
  var bumps = 40
  var depth: CGFloat = 0.03

  func path(in rect: CGRect) -> Path {
    let c = CGPoint(x: rect.midX, y: rect.midY)
    let r = min(rect.width, rect.height) / 2
    var path = Path()
    let steps = bumps * 8
    for i in 0...steps {
      let a = Double(i) / Double(steps) * 2 * .pi
      let rr = r * (1 - depth + depth * CGFloat(cos(Double(bumps) * a)))
      let p = CGPoint(x: c.x + rr * CGFloat(cos(a)), y: c.y + rr * CGFloat(sin(a)))
      if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
    }
    path.closeSubpath()
    return path
  }
}

/// Lays children out left to right, wrapping when a row is full: a run of
/// ticket labels.
private struct Flow: Layout {
  var spacing: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? .infinity
    return CGSize(width: proposal.width ?? 0, height: rows(subviews, width: width).last.map { $0.y + $0.height } ?? 0)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    for row in rows(subviews, width: bounds.width) {
      var x = bounds.minX
      for i in row.indices {
        let size = subviews[i].sizeThatFits(.unspecified)
        let w = min(size.width, bounds.width)
        subviews[i].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(width: w, height: size.height))
        x += w + spacing
      }
    }
  }

  private struct Row {
    var indices: [Int] = []
    var y: CGFloat = 0
    var height: CGFloat = 0
  }

  private func rows(_ subviews: Subviews, width: CGFloat) -> [Row] {
    var rows = [Row()]
    var x: CGFloat = 0
    for i in subviews.indices {
      let size = subviews[i].sizeThatFits(.unspecified)
      if x > 0, x + size.width > width {
        let last = rows[rows.count - 1]
        rows.append(Row(y: last.y + last.height + spacing))
        x = 0
      }
      rows[rows.count - 1].indices.append(i)
      rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
      x += size.width + spacing
    }
    return rows
  }
}

// MARK: - Year map

private struct YearMapCardView: View {
  let card: Loci_Recap_YearMapCard
  let appeared: Bool
  let k: RecapUnit

  var body: some View {
    ZStack {
      RecapPalette.sand
      VStack(alignment: .leading, spacing: 3 * k.u) {
        Headcount(
          value: card.countriesCount,
          noun: card.countriesCount == 1 ? "country" : "countries",
          numberColor: RecapPalette.ink,
          nounColor: RecapPalette.coralDeep,
          appeared: appeared,
          k: k
        )
        Kicker(text: count(card.citiesCount, "city", "cities"), k: k).foregroundStyle(RecapPalette.muted)
        map.frame(height: 52 * k.u).rise(appeared, 0.3)
        ledger
        if !card.headline.isEmpty { Headline(text: card.headline, k: k).rise(appeared, 1.2) }
      }.foregroundStyle(RecapPalette.ink).padding(.horizontal, 7 * k.u).padding(.top, 15 * k.u).padding(.bottom, 10 * k.u)
        .frame(maxHeight: .infinity, alignment: .top)
    }
  }

  private var map: some View {
    GeometryReader { geo in
      let rect = CGRect(origin: .zero, size: geo.size).insetBy(dx: 12 * k.u, dy: 7 * k.u)
      let pins = PinProjection.points(Array(card.cities.prefix(40)), in: rect)
      ZStack(alignment: .topLeading) {
        Canvas { ctx, size in
          var grid = Path()
          stride(from: 6 * k.u, to: size.width, by: 6 * k.u).forEach {
            grid.move(to: CGPoint(x: $0, y: 0))
            grid.addLine(to: CGPoint(x: $0, y: size.height))
          }
          stride(from: 6 * k.u, to: size.height, by: 6 * k.u).forEach {
            grid.move(to: CGPoint(x: 0, y: $0))
            grid.addLine(to: CGPoint(x: size.width, y: $0))
          }
          ctx.stroke(grid, with: .color(RecapPalette.ink.opacity(0.07)), lineWidth: 1)
        }
        ForEach(Array(pins.enumerated()), id: \.offset) { i, p in
          pin(i, at: p, rightSide: p.x > geo.size.width * 0.62)
        }
      }.background(RecapPalette.paper, in: RoundedRectangle(cornerRadius: 10)).shadow(color: RecapPalette.ink.opacity(0.2), radius: 8, y: 5)
    }.accessibilityElement(children: .ignore).accessibilityLabel("Map of \(card.cities.map(\.label).joined(separator: ", "))")
  }

  /// A pin, and for the first few (the most-visited) its city on whichever
  /// side has room.
  @ViewBuilder private func pin(_ i: Int, at p: CGPoint, rightSide: Bool) -> some View {
    let labelWidth = 30 * k.u
    ZStack {
      Circle().fill(RecapPalette.coral.opacity(0.25)).frame(width: 3.2 * k.u)
      Circle().fill(RecapPalette.coralDeep).frame(width: 1.6 * k.u)
    }.position(p).thud(appeared, 0.5 + Double(min(i, 12)) * 0.08)
    if i < 8, card.cities.indices.contains(i) {
      Text(card.cities[i].label.uppercased()).font(k.mono(2)).tracking(0.6).lineLimit(1).minimumScaleFactor(0.7)
        .frame(width: labelWidth, alignment: rightSide ? .trailing : .leading)
        .position(x: p.x + (rightSide ? -1 : 1) * (2.6 * k.u + labelWidth / 2), y: p.y).rise(appeared, 0.8)
    }
  }

  private var ledger: some View {
    VStack(spacing: 1.6 * k.u) {
      ForEach(Array(card.countries.prefix(4).enumerated()), id: \.offset) { i, c in
        VStack(spacing: 1.2 * k.u) {
          HStack(alignment: .firstTextBaseline, spacing: 2 * k.u) {
            Text(c.country.isEmpty ? c.countryCode : c.country).font(k.display(5, .heavy)).lineLimit(1).minimumScaleFactor(0.6)
            if c.firstTime {
              Text("NEW").font(k.mono(2)).tracking(0.8).foregroundStyle(RecapPalette.paper)
                .padding(.horizontal, 1.6 * k.u).padding(.vertical, 0.5 * k.u)
                .background(RecapPalette.coralDeep, in: Capsule())
            }
            Spacer(minLength: 2 * k.u)
            Kicker(text: "\(count(c.citiesCount, "city", "cities")) · \(count(c.days, "day", "days"))", k: k).foregroundStyle(RecapPalette.muted)
              .lineLimit(1).minimumScaleFactor(0.7)
          }
          DashedRule()
        }.rise(appeared, 0.8 + Double(i) * 0.15).accessibilityElement(children: .combine)
      }
    }
  }
}

// MARK: - Trips timeline

private struct TripsTimelineCardView: View {
  let card: Loci_Recap_TripsTimelineCard
  let appeared: Bool
  let k: RecapUnit

  private static let initials = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]

  var body: some View {
    ZStack {
      RecapPalette.night
      VStack(alignment: .leading, spacing: 3 * k.u) {
        Headcount(
          value: card.tripsCount,
          noun: card.tripsCount == 1 ? "trip" : "trips",
          numberColor: RecapPalette.coral,
          nounColor: RecapPalette.cream,
          appeared: appeared,
          k: k
        )
        Kicker(text: count(card.daysAway, "day away", "days away"), k: k).opacity(0.7)
        strip.frame(height: 56 * k.u).padding(.top, 3 * k.u)
        tickets
        Spacer(minLength: 0)
        if !card.headline.isEmpty { Headline(text: card.headline, k: k).rise(appeared, 1.4) }
      }.foregroundStyle(RecapPalette.cream).padding(.horizontal, 7 * k.u).padding(.top, 15 * k.u).padding(.bottom, 10 * k.u)
    }
  }

  private var days: [Int32] {
    var out = [Int32](repeating: 0, count: 12)
    for m in card.months where (1...12).contains(m.month) { out[Int(m.month) - 1] = max(m.days, 0) }
    return out
  }

  private var strip: some View {
    let values = days
    let most = max(values.max() ?? 1, 1)
    return HStack(alignment: .bottom, spacing: 1.4 * k.u) {
      ForEach(0..<12, id: \.self) { i in
        VStack(spacing: 1.4 * k.u) {
          GeometryReader { geo in
            ZStack(alignment: .bottom) {
              RoundedRectangle(cornerRadius: 4).fill(RecapPalette.paper.opacity(0.06))
              if values[i] > 0 {
                RoundedRectangle(cornerRadius: 4).fill(i + 1 == Int(card.busiestMonth) ? RecapPalette.coral : RecapPalette.cream.opacity(0.75))
                  .frame(height: appeared ? max(2 * k.u, geo.size.height * CGFloat(values[i]) / CGFloat(most)) : 0)
                  .animation(.easeOut(duration: 0.8).delay(0.4 + Double(i) * 0.06), value: appeared)
              }
            }
          }
          Text(Self.initials[i]).font(k.mono(2.4)).opacity(i + 1 == Int(card.busiestMonth) ? 1 : 0.6)
        }
      }
    }.accessibilityElement(children: .ignore).accessibilityLabel(stripLabel)
  }

  private var stripLabel: String {
    let busy = days.enumerated().filter { $0.element > 0 }.map { "\(monthName($0.offset + 1)): \(count($0.element, "day", "days"))" }
    return busy.isEmpty ? "No trips by month" : busy.joined(separator: ", ")
  }

  private var tickets: some View {
    Flow(spacing: 1.6 * k.u) {
      ForEach(Array(card.trips.prefix(8).enumerated()), id: \.offset) { i, t in
        Text((t.cityName.isEmpty ? "Trip" : t.cityName).uppercased()).font(k.mono(2.4)).tracking(0.8).lineLimit(1).minimumScaleFactor(0.6)
          .padding(.horizontal, 2 * k.u).padding(.vertical, 1.2 * k.u)
          .overlay(RoundedRectangle(cornerRadius: 4).stroke(RecapPalette.cream.opacity(0.45), lineWidth: 1))
          .rise(appeared, 1 + Double(i) * 0.08)
      }
    }
  }
}

// MARK: - Top city

private struct TopCityCardView: View {
  let card: Loci_Recap_TopCityCard
  let appeared: Bool
  let k: RecapUnit

  var body: some View {
    ZStack {
      RecapPalette.cream
      VStack(alignment: .leading, spacing: 5 * k.u) {
        Kicker(text: "Your city this year", k: k).foregroundStyle(RecapPalette.muted)
        postcard.rotationEffect(.degrees(appeared ? -3 : 10)).offset(y: appeared ? 0 : 30 * k.u).opacity(appeared ? 1 : 0)
          .animation(.spring(response: 0.8, dampingFraction: 0.75), value: appeared)
        HStack(spacing: 0) {
          Stat(value: Int(card.days).formatted(), caption: "Days", k: k)
          DashedRule(vertical: true).frame(height: 12 * k.u)
          Stat(value: Int(card.placesCount).formatted(), caption: "Places", k: k)
          DashedRule(vertical: true).frame(height: 12 * k.u)
          Stat(value: Int(card.tripsCount).formatted(), caption: "Trips", k: k)
        }.padding(.top, 4 * k.u).rise(appeared, 0.9)
        if !card.headline.isEmpty { Headline(text: card.headline, k: k).rise(appeared, 1.2) }
      }.foregroundStyle(RecapPalette.ink).padding(.horizontal, 7 * k.u).padding(.top, 18 * k.u).frame(maxHeight: .infinity, alignment: .top)
    }
  }

  private var postcard: some View {
    VStack(alignment: .leading, spacing: 3 * k.u) {
      ZStack {
        RecapPalette.coralDeep
        Canvas { ctx, size in
          var waves = Path()
          for row in 0..<5 {
            let y = size.height * (0.15 + CGFloat(row) * 0.18)
            waves.move(to: CGPoint(x: 0, y: y))
            stride(from: 0, through: size.width, by: 3).forEach { x in
              waves.addLine(to: CGPoint(x: x, y: y + 1.2 * k.u * sin(x / (4 * k.u) + CGFloat(row))))
            }
          }
          ctx.stroke(waves, with: .color(RecapPalette.paper.opacity(0.18)), lineWidth: 1.5)
        }
        Text(card.cityName.isEmpty ? "Your city" : card.cityName).font(k.display(13, .black)).foregroundStyle(RecapPalette.paper)
          .multilineTextAlignment(.center)
          .lineLimit(2).minimumScaleFactor(0.4).padding(.horizontal, 5 * k.u)
      }.frame(height: 48 * k.u)
      HStack {
        Kicker(text: "Greetings from", k: k)
        Spacer()
        Kicker(text: card.country.isEmpty ? card.countryCode : card.country, k: k).foregroundStyle(RecapPalette.muted)
      }
    }.padding(4 * k.u).background(RecapPalette.paper, in: RoundedRectangle(cornerRadius: 6))
      .shadow(color: RecapPalette.ink.opacity(0.3), radius: 14, y: 10)
      .accessibilityElement(children: .ignore).accessibilityLabel("Greetings from \(card.cityName)")
  }
}

// MARK: - Taste shift

private struct TasteShiftCardView: View {
  let card: Loci_Recap_TasteShiftCard
  let appeared: Bool
  let k: RecapUnit

  var body: some View {
    ZStack {
      RecapPalette.post
      VStack(alignment: .leading, spacing: 4 * k.u) {
        Kicker(text: "Your taste, January to now", k: k).foregroundStyle(RecapPalette.ink.opacity(0.7))
        Text(card.trait.label.isEmpty ? "Something new" : card.trait.label).font(k.display(11, .black)).lineLimit(3)
          .minimumScaleFactor(0.5).rise(appeared)
        bar("January", card.strengthStart, RecapPalette.ink.opacity(0.35), delay: 0.5)
        bar("Now", card.strengthEnd, RecapPalette.coralDeep, delay: 0.9)
        if !card.runnersUp.isEmpty {
          VStack(alignment: .leading, spacing: 1.5 * k.u) {
            Kicker(text: "Also on the rise", k: k).foregroundStyle(RecapPalette.muted)
            ForEach(Array(card.runnersUp.prefix(2).enumerated()), id: \.offset) { _, t in Text(t.label).font(k.display(5.2, .heavy)).lineLimit(1) }
          }.padding(.top, 3 * k.u).rise(appeared, 1.3)
        }
        Spacer(minLength: 0)
        if !card.headline.isEmpty { Headline(text: card.headline, k: k).rise(appeared, 1.5) }
      }.foregroundStyle(RecapPalette.ink).padding(.horizontal, 7 * k.u).padding(.top, 18 * k.u).padding(.bottom, 10 * k.u)
    }
  }

  private func bar(_ label: String, _ value: Double, _ color: Color, delay: Double) -> some View {
    let v = value.isFinite ? min(max(value, 0), 1) : 0
    return VStack(alignment: .leading, spacing: 1.2 * k.u) {
      Kicker(text: label, k: k).foregroundStyle(RecapPalette.muted)
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule().fill(RecapPalette.paper.opacity(0.8))
          Capsule().fill(color).frame(width: appeared ? max(geo.size.height, geo.size.width * v) : geo.size.height)
            .animation(.easeOut(duration: 0.9).delay(delay), value: appeared)
        }
      }.frame(height: 5 * k.u)
    }.accessibilityElement(children: .ignore).accessibilityLabel("\(label): \(Int((v * 100).rounded())) percent")
  }
}

// MARK: - Streak

private struct StreakCardView: View {
  let card: Loci_Recap_StreakCard
  let appeared: Bool
  let k: RecapUnit

  var body: some View {
    let run = Int(max(card.longestStreakDays, 0))
    let shown = min(run, 35)
    ZStack {
      RecapPalette.night
      VStack(alignment: .leading, spacing: 3 * k.u) {
        CountUp(value: appeared ? Double(run) : 0).animation(.easeOut(duration: 1), value: appeared).font(k.display(32, .black))
          .foregroundStyle(RecapPalette.coral)
        Text("days in a row").font(k.italic(8)).foregroundStyle(RecapPalette.cream)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2.6 * k.u), count: 7), spacing: 2.6 * k.u) {
          ForEach(0..<shown, id: \.self) { i in
            Circle().fill(RecapPalette.coral).aspectRatio(1, contentMode: .fit).thud(appeared, 0.5 + Double(i) * 0.05)
          }
        }.padding(.top, 3 * k.u).accessibilityHidden(true)
        if run > shown { Kicker(text: "+\(run - shown) more", k: k).opacity(0.7) }
        if !card.headline.isEmpty { Headline(text: card.headline, k: k).padding(.top, 2 * k.u).rise(appeared, 1.2) }
        Spacer(minLength: 0)
        stats.rise(appeared, 1.4)
      }.foregroundStyle(RecapPalette.cream).padding(.horizontal, 7 * k.u).padding(.top, 15 * k.u).padding(.bottom, 12 * k.u)
    }.accessibilityElement(children: .combine)
  }

  private var stats: some View {
    HStack(spacing: 0) {
      Stat(value: Int(max(card.activeDays, 0)).formatted(), caption: "Active days", k: k)
      if (1...12).contains(card.bestMonth) {
        DashedRule(vertical: true).frame(height: 12 * k.u)
        Stat(value: monthName(Int(card.bestMonth), short: true), caption: "Best month", k: k)
      }
    }
  }
}

// MARK: - Contributions

private struct ContributionsCardView: View {
  let card: Loci_Recap_ContributionsCard
  let appeared: Bool
  let k: RecapUnit

  private var tiles: [(Int32, String)] {
    [(card.reviewsCount, "Reviews"), (card.listsCount, "Lists"), (card.postsCount, "Posts"), (card.submissionsCount, "Places added")]
  }

  var body: some View {
    let total = tiles.reduce(Int32(0)) { $0 + max($1.0, 0) }
    ZStack {
      RecapPalette.cream
      VStack(alignment: .leading, spacing: 3 * k.u) {
        Kicker(text: "Given back", k: k).foregroundStyle(RecapPalette.muted)
        CountUp(value: appeared ? Double(total) : 0).animation(.easeOut(duration: 1.1), value: appeared).font(k.display(28, .black))
        Text("for other travellers").font(k.italic(7.5)).foregroundStyle(RecapPalette.coralDeep)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 4 * k.u), GridItem(.flexible())], spacing: 4 * k.u) {
          ForEach(Array(tiles.enumerated()), id: \.offset) { i, t in tile(t.0, t.1).rise(appeared, 0.5 + Double(i) * 0.15) }
        }.padding(.top, 3 * k.u)
        if !card.headline.isEmpty { Headline(text: card.headline, k: k).padding(.top, 2 * k.u).rise(appeared, 1.2) }
      }.foregroundStyle(RecapPalette.ink).padding(.horizontal, 7 * k.u).padding(.top, 18 * k.u).frame(maxHeight: .infinity, alignment: .top)
    }
  }

  private func tile(_ value: Int32, _ caption: String) -> some View {
    VStack(spacing: 1.5 * k.u) {
      Text(Int(max(value, 0)).formatted()).font(k.display(12, .black)).lineLimit(1).minimumScaleFactor(0.4)
      Kicker(text: caption, k: k).foregroundStyle(RecapPalette.muted)
    }.foregroundStyle(value > 0 ? RecapPalette.ink : RecapPalette.ink.opacity(0.3)).frame(maxWidth: .infinity).padding(.vertical, 6 * k.u)
      .background(RecapPalette.paper, in: RoundedRectangle(cornerRadius: 8)).shadow(color: RecapPalette.ink.opacity(0.18), radius: 8, y: 6)
      .accessibilityElement(children: .combine)
  }
}

// MARK: - Percentile

private struct PercentileCardView: View {
  let card: Loci_Recap_PercentileCard
  let appeared: Bool
  let k: RecapUnit

  private var metric: String {
    switch card.metric {
    case .cities: "for cities"
    case .daysWalked: "for days walked"
    case .contributions: "for giving back"
    default: "for places kept"
    }
  }

  var body: some View {
    ZStack {
      RecapPalette.sand
      VStack(spacing: 5 * k.u) {
        Kicker(text: "Of every Loci traveller this year", k: k).foregroundStyle(RecapPalette.muted).frame(maxWidth: .infinity, alignment: .leading)
        seal.frame(width: 70 * k.u, height: 70 * k.u).rotationEffect(.degrees(8)).thud(appeared, 0.4).padding(.vertical, 4 * k.u)
        if card.value > 0 { Kicker(text: "\(count(card.value, "place", "places")) this year", k: k).rise(appeared, 1) }
        if !card.headline.isEmpty {
          Headline(text: card.headline, k: k).frame(maxWidth: .infinity, alignment: .leading).rise(appeared, 1.2)
        }
      }.foregroundStyle(RecapPalette.ink).padding(.horizontal, 7 * k.u).padding(.top, 18 * k.u).frame(maxHeight: .infinity, alignment: .top)
    }
  }

  private var seal: some View {
    ZStack {
      Scallop().fill(RecapPalette.coralDeep.opacity(0.92))
      Circle().inset(by: 5 * k.u).stroke(RecapPalette.paper.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
      VStack(spacing: 1 * k.u) {
        Text("TOP").font(k.mono(3.6)).tracking(1.5)
        Text("\(max(card.topPercent, 1))%").font(k.display(20, .black)).lineLimit(1).minimumScaleFactor(0.5)
        Text(metric.uppercased()).font(k.mono(2.4)).tracking(0.8)
      }.foregroundStyle(RecapPalette.paper)
    }.accessibilityElement(children: .ignore).accessibilityLabel("Top \(max(card.topPercent, 1)) percent \(metric)")
  }
}
