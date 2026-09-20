import Foundation

public enum APIError: LocalizedError, Equatable, Sendable {
  case invalidURL
  case invalidResponse
  case unauthorized(String?)
  case forbidden(String?)
  case notFound(String?)
  case conflict(String?)
  case network(String)
  case server(String)
  case custom(String)

  public var isUnauthorized: Bool {
    if case .unauthorized = self { return true }
    return false
  }

  public var errorDescription: String? {
    switch self {
    case .invalidURL: return "Invalid request URL."
    case .invalidResponse: return "Unexpected response from server."
    case .unauthorized(let msg): return msg ?? "Your session has expired. Please sign in again."
    case .forbidden(let msg): return msg ?? "You do not have permission to access this resource."
    case .notFound(let msg): return msg ?? "The requested resource was not found."
    case .conflict(let msg): return msg ?? "A conflict occurred with this resource."
    case .network(let details): return "Network connection error: \(details)"
    case .server(let details): return "Server error: \(details)"
    case .custom(let msg): return msg
    }
  }
}
