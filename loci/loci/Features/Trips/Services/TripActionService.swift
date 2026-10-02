import Connect
import Foundation
import LociConnectProto

/// Why a proposed trip change could not be applied, in the card's words.
nonisolated struct TripActionError: Error, Equatable, Sendable {
  enum Kind: Equatable, Sendable { case stale, gone, invalid, other }

  let kind: Kind
  let message: String

  init(kind: Kind, message: String) {
    self.kind = kind
    self.message = message
  }

  /// FailedPrecondition is a stale trip ("trip version conflict") or a
  /// proposal already used, dismissed or expired; the text tells them apart.
  init(_ error: ConnectError?, fallback: String) {
    let text = error?.message ?? ""
    switch error?.code {
    case .failedPrecondition: kind = text.contains("version") ? .stale : .gone
    case .notFound: kind = .gone
    case .invalidArgument: kind = .invalid
    default: kind = .other
    }
    message = text.isEmpty ? fallback : text
  }

  var userMessage: String {
    switch kind {
    case .stale: "This trip changed since the suggestion. Ask again for a fresh one."
    case .gone: "This suggestion was already used or has expired."
    case .invalid: "That change can't be made to this trip."
    case .other: "Couldn't make that change. Try again."
    }
  }
}

/// ApplyTripAction / DismissTripAction. A protocol so the model can be tested.
nonisolated protocol TripActionService: Sendable {
  func apply(proposalID: String, option: Int?, baseVersion: Int64) async throws(TripActionError) -> Loci_Chat_ApplyTripActionResponse
  func dismiss(proposalID: String) async throws(TripActionError)
}

nonisolated struct ConnectTripActionService: TripActionService {
  private let client = Loci_Chat_ChatServiceClient(client: ConnectTransport.shared.protocolClient)

  func apply(proposalID: String, option: Int?, baseVersion: Int64) async throws(TripActionError) -> Loci_Chat_ApplyTripActionResponse {
    var request = Loci_Chat_ApplyTripActionRequest()
    request.proposalID = proposalID
    if let option { request.optionIndex = Int32(option) }
    request.baseVersion = baseVersion
    let sent = request
    let response = await withAuthRetry { await client.applyTripAction(request: sent, headers: [:]) }
    if let message = response.message { return message }
    throw TripActionError(response.error, fallback: "Couldn't make that change.")
  }

  func dismiss(proposalID: String) async throws(TripActionError) {
    var request = Loci_Chat_DismissTripActionRequest()
    request.proposalID = proposalID
    let sent = request
    let response = await withAuthRetry { await client.dismissTripAction(request: sent, headers: [:]) }
    if response.message == nil { throw TripActionError(response.error, fallback: "Couldn't dismiss that.") }
  }
}
