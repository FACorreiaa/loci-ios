import Connect
import LociConnectProto

/// Generated clients for every service the settings screens talk to. All share
/// the authenticated transport.
nonisolated enum SettingsClients {
  private static var transport: ProtocolClientInterface { ConnectTransport.shared.protocolClient }

  static let auth = Loci_Auth_AuthServiceClient(client: transport)
  static let user = Loci_User_UserServiceClient(client: transport)
  static let recommendation = Loci_Recommendation_RecommendationServiceClient(client: transport)
  static let memory = Loci_Memory_MemoryServiceClient(client: transport)
  static let tags = Loci_Tags_TagsServiceClient(client: transport)
  static let interests = Loci_Interest_InterestServiceClient(client: transport)
  static let profiles = Loci_Profile_ProfileServiceClient(client: transport)
  static let apiKeys = Loci_Apikey_ApiKeyServiceClient(client: transport)
  static let aiCredentials = Loci_Aicreds_AiCredentialServiceClient(client: transport)
  static let messaging = Loci_Messaging_MessagingServiceClient(client: transport)
  static let integrations = Loci_Integrations_IntegrationServiceClient(client: transport)
  static let localContext = Loci_Localcontext_LocalContextServiceClient(client: transport)
  static let calendar = Loci_Calendar_CalendarServiceClient(client: transport)
}
