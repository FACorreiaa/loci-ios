import Foundation

public nonisolated enum JWTTokenInspector {
  public struct Payload: Equatable, Sendable {
    public let userID: String?
    public let expiresAt: Date?
    public let jti: String?

    public init(userID: String?, expiresAt: Date?, jti: String? = nil) {
      self.userID = userID
      self.expiresAt = expiresAt
      self.jti = jti
    }
  }

  public static func payload(from token: String) -> Payload? {
    let segments = token.split(separator: ".", omittingEmptySubsequences: false)
    guard segments.count >= 2, let data = decodeBase64URL(String(segments[1])),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }

    let userId = (json["userId"] as? String) ?? (json["sub"] as? String)
    let exp = json["exp"] as? Double
    let jti = json["jti"] as? String
    let expiresAt = exp.map(Date.init(timeIntervalSince1970:))
    return Payload(userID: userId, expiresAt: expiresAt, jti: jti)
  }

  public static func expirationDate(in token: String) -> Date? { payload(from: token)?.expiresAt }

  public static func userID(in token: String) -> String? { payload(from: token)?.userID }

  public static func jti(in token: String) -> String? { payload(from: token)?.jti }

  private static func decodeBase64URL(_ base64URL: String) -> Data? {
    var base64 = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while !base64.count.isMultiple(of: 4) { base64.append("=") }
    return Data(base64Encoded: base64)
  }
}
