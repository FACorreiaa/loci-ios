import Foundation

public extension Notification.Name {
    static let authSessionDidAuthenticate = Notification.Name("loci.authSessionDidAuthenticate")
    static let authSessionWillInvalidate = Notification.Name("loci.authSessionWillInvalidate")
    static let authSessionDidInvalidate = Notification.Name("loci.authSessionDidInvalidate")
}

public protocol AuthSessionManaging: Sendable {
    func restoreSessionIfNeeded() async -> Bool
    func validAccessToken() async throws -> String?
    func getRefreshToken() async throws -> String?
    func storeSession(accessToken: String, refreshToken: String?, userId: String?, username: String?) async throws
    func logout() async
    func invalidateSession() async
    var currentUserID: String? { get }
    var currentUsername: String? { get }
}

public final class AuthSessionManager: AuthSessionManaging, @unchecked Sendable {
    public static let shared = AuthSessionManager()

    private let secureStore: SecureStringStoring
    private let accessTokenKey = "loci_auth_access_token"
    private let refreshTokenKey = "loci_auth_refresh_token"
    private let userIdKey = "loci_auth_user_id"
    private let usernameKey = "loci_auth_username"

    public private(set) var currentUserID: String?
    public private(set) var currentUsername: String?

    public init(secureStore: SecureStringStoring = KeychainStringStore()) {
        self.secureStore = secureStore
        self.currentUserID = try? secureStore.string(for: userIdKey)
        self.currentUsername = try? secureStore.string(for: usernameKey)
    }

    public func restoreSessionIfNeeded() async -> Bool {
        do {
            let token = try await validAccessToken()
            return !(token?.isEmpty ?? true)
        } catch {
            return false
        }
    }

    public func validAccessToken() async throws -> String? {
        guard let token = try secureStore.string(for: accessTokenKey), !token.isEmpty else {
            return nil
        }

        if let expiry = JWTTokenInspector.expirationDate(in: token) {
            if expiry <= Date() {
                // If expired, try to refresh via refreshTokenKey
                if let rToken = try secureStore.string(for: refreshTokenKey), !rToken.isEmpty {
                    return nil // Needs refresh
                }
                await invalidateSession()
                return nil
            }
        }

        return token
    }

    public func getRefreshToken() async throws -> String? {
        return try secureStore.string(for: refreshTokenKey)
    }

    public func storeSession(accessToken: String, refreshToken: String?, userId: String?, username: String?) async throws {
        try secureStore.setString(accessToken, for: accessTokenKey)
        if let refreshToken, !refreshToken.isEmpty {
            try secureStore.setString(refreshToken, for: refreshTokenKey)
        }
        if let userId, !userId.isEmpty {
            try secureStore.setString(userId, for: userIdKey)
            self.currentUserID = userId
        }
        if let username, !username.isEmpty {
            try secureStore.setString(username, for: usernameKey)
            self.currentUsername = username
        }

        await MainActor.run {
            NotificationCenter.default.post(name: .authSessionDidAuthenticate, object: nil)
        }
    }

    public func logout() async {
        await invalidateSession()
    }

    public func invalidateSession() async {
        try? secureStore.removeValue(for: accessTokenKey)
        try? secureStore.removeValue(for: refreshTokenKey)
        try? secureStore.removeValue(for: userIdKey)
        try? secureStore.removeValue(for: usernameKey)
        self.currentUserID = nil
        self.currentUsername = nil

        await MainActor.run {
            NotificationCenter.default.post(name: .authSessionDidInvalidate, object: nil)
        }
    }
}
