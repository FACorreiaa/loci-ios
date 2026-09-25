import Foundation

/// Whether a free plan is held to the free feature set (Day-1 exports, the
/// Trip Kit's first day only) or gets everything Pro gets.
///
/// Off by the owner's decision of 2026-09-25: the app has no users worth
/// gating yet, so every plan is entitled to every feature. The server
/// (`PLAN_GATING`, `subscription.Entitled`) and web (`PLAN_GATING_ENABLED`,
/// `canUsePro`) hold the same switch, and `GetEntitlements` already answers
/// unlimited, so the three agree. What a plan *is* (`ProGate.isPro`) stays
/// truthful. The order features will be gated in once there are users lives
/// in `docs/ios/ROADMAP.md` under "Deferred — Pro gating"; flip this and the
/// two other switches together to start.
nonisolated enum PlanGating {
  static let enabled = false
}
