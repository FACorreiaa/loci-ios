import Testing
import Foundation
@testable import loci

struct lociTests {

    @Test func testJWTTokenInspectorValidPayload() async throws {
        // Payload: {"sub": "usr_12345", "exp": 1700000000, "jti": "jwt_id_999"}
        // base64url for header: {"alg":"none"} -> eyJhbGciOiJub25lIn0
        // base64url for payload: {"sub":"usr_12345","exp":1700000000,"jti":"jwt_id_999"} -> eyJzdWIiOiJ1c3JfMTIzNDUiLCJleHAiOjE3MDAwMDAwMDAsImp0aSI6Imp3dF9pZF85OTkifQ
        let token = "eyJhbGciOiJub25lIn0.eyJzdWIiOiJ1c3JfMTIzNDUiLCJleHAiOjE3MDAwMDAwMDAsImp0aSI6Imp3dF9pZF85OTkifQ."
        
        let payload = JWTTokenInspector.payload(from: token)
        #expect(payload != nil)
        #expect(payload?.userID == "usr_12345")
        #expect(payload?.jti == "jwt_id_999")
        #expect(payload?.expiresAt == Date(timeIntervalSince1970: 1700000000))
    }

    @Test func testJWTTokenInspectorUserIdAlternativeKey() async throws {
        // Payload: {"userId": "custom_user_abc"}
        // base64url: {"userId":"custom_user_abc"} -> eyJ1c2VySWQiOiJjdXN0b21fdXNlcl9hYmMifQ
        let token = "eyJhbGciOiJub25lIn0.eyJ1c2VySWQiOiJjdXN0b21fdXNlcl9hYmMifQ."
        
        let userId = JWTTokenInspector.userID(in: token)
        #expect(userId == "custom_user_abc")
    }

    @Test func testJWTTokenInspectorInvalidToken() async throws {
        #expect(JWTTokenInspector.payload(from: "invalid-token") == nil)
        #expect(JWTTokenInspector.payload(from: "") == nil)
        #expect(JWTTokenInspector.payload(from: "a.b") == nil)
    }

    @Test func testAPIErrorDescriptions() async throws {
        let notFound = APIError.notFound(nil)
        #expect(notFound.errorDescription == "The requested resource was not found.")
        
        let customErr = APIError.custom("Custom server error message")
        #expect(customErr.errorDescription == "Custom server error message")
    }

    @Test func testAppConfigEnvironmentResolution() async throws {
        let config = AppConfig.shared
        #expect(!config.connectBaseURL.isEmpty)
        #expect(config.connectBaseURL.hasPrefix("http://") || config.connectBaseURL.hasPrefix("https://"))
        #expect(config.environment == .local || config.environment == .testflight || config.environment == .production)
    }
}
