import SwiftUI

/// You on the map while following a route: a little walker in a badge that
/// faces the way you are going and bobs in step while you move. Mirrored, not
/// rotated, so it never walks upside down. Stands still under Reduce Motion.
struct WalkerFigure: View {
  let facesLeft: Bool
  let isMoving: Bool
  let destinationName: String?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var mirrored: Bool { facesLeft == WalkingRoute.symbolFacesRight }
  private var bobs: Bool { isMoving && !reduceMotion }

  var body: some View {
    ZStack(alignment: .bottom) {
      Ellipse()
        .fill(.black.opacity(0.22))
        .frame(width: 22, height: 7)
        .offset(y: 4)
      Circle()
        .fill(Color.lociForest)
        .frame(width: 40, height: 40)
        .overlay(Circle().stroke(.white, lineWidth: 3))
        .overlay {
          Image(systemName: isMoving ? "figure.walk" : "figure.stand")
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(.white)
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            .contentTransition(.symbolEffect(.replace))
        }
        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
        .phaseAnimator([false, true]) { badge, up in
          badge.offset(y: bobs && up ? -5 : 0)
        } animation: { _ in
          .easeInOut(duration: 0.3)
        }
        .padding(.bottom, 6)
    }
    .animation(.easeInOut(duration: 0.2), value: mirrored)
    .accessibilityElement()
    .accessibilityLabel(destinationName.map { "You, walking to \($0)" } ?? "You")
  }
}

#Preview {
  HStack(spacing: 24) {
    WalkerFigure(facesLeft: false, isMoving: true, destinationName: "Bolhão")
    WalkerFigure(facesLeft: true, isMoving: true, destinationName: "Bolhão")
    WalkerFigure(facesLeft: false, isMoving: false, destinationName: nil)
  }
  .padding()
}
