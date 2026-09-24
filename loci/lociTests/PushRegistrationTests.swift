import Foundation
import LociConnectProto
import Testing

@testable import loci

struct PushRegistrationTests {
  /// The registration names the token, our bundle id as the topic and which
  /// APNs host holds the token; the server refuses anything else.
  @Test func requestCarriesTokenTopicAndEnvironment() {
    let token = String(repeating: "ab", count: 32)
    let request = PushRegistration.request(token: token, topic: "com.fernandocorreia.loci.beta", environment: "production")
    #expect(request.platform == .apns)
    #expect(request.endpoint == token)
    #expect(request.apnsTopic == "com.fernandocorreia.loci.beta")
    #expect(request.apnsEnvironment == "production")
    #expect(request.p256Dh.isEmpty && request.auth.isEmpty)
  }

  @Test func environmentFollowsTheBuildConfiguration() {
    #if DEBUG
      #expect(PushRegistration.environment == "sandbox")
    #else
      #expect(PushRegistration.environment == "production")
    #endif
  }
}
