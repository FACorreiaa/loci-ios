import LociConnectProto
import SwiftUI

/// MCP and agents (web: settings tab "connections", and the /mcp guide).
/// Four cards, as on web: agent keys, model provider, Telegram, outbound MCP servers.
struct ConnectionsView: View {
  var body: some View {
    List {
      Section {
        LabeledContent("MCP endpoint") {
          Text(ConnectTransport.shared.mcpEndpoint.absoluteString).font(.lociCoord(12)).textSelection(.enabled)
        }
      } footer: {
        Text("Give an agent a key below and it can search places and plan trips with your Loci account.")
      }
      McpKeysSection()
      ModelProviderSection()
      TelegramSection()
      OutboundConnectionsSection()
    }
    .settingsStyle("MCP and agents")
  }
}

// MARK: - Agent keys

/// ApiKeyService: ListApiKeys, CreateApiKey{name, scopes, clientKind}, RevokeApiKey{id},
/// GetSetupInstructions{clientKind}.
struct McpKeysSection: View {
  /// web: lib/api/api-keys.ts CLIENT_KINDS
  static let clientKinds: [(value: String, label: String)] = [
    ("claude_code", "Claude Code"), ("claude_desktop", "Claude Desktop"), ("cursor", "Cursor"), ("codex", "Codex"),
    ("hermes", "Hermes"), ("other", "Other MCP client"),
  ]

  static func label(for kind: String) -> String { clientKinds.first { $0.value == kind }?.label ?? "Other MCP client" }

  @State private var keys: [Loci_Apikey_ApiKey] = []
  @State private var isCreating = false
  @State private var issued: Loci_Apikey_CreateApiKeyResponse?
  @State private var revoking: Loci_Apikey_ApiKey?
  @State private var error: String?

  var body: some View {
    Section {
      ForEach(keys.filter { !$0.hasRevokedAt }, id: \.id) { key in
        NavigationLink {
          SetupInstructionsView(clientKind: key.clientKind)
        } label: {
          VStack(alignment: .leading, spacing: 2) {
            Text(key.name)
            Text("\(Self.label(for: key.clientKind)) · \(key.keyPrefix)… · \(key.scopes.joined(separator: ", "))")
              .font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
          }
        }
        .swipeActions { Button("Revoke", role: .destructive) { revoking = key } }
      }
      Button("Connect an agent", systemImage: "plus") { isCreating = true }
    } header: {
      Text("Agents")
    }
    .sheet(isPresented: $isCreating) { CreateKeySheet { issued = $0; Task { await load() } } }
    .sheet(item: Binding(get: { issued.map(IssuedKey.init) }, set: { if $0 == nil { issued = nil } })) { IssuedKeyView(issued: $0.response) }
    .confirmationDialog(
      "\(Self.label(for: revoking?.clientKind ?? "other")) stops working with this key.",
      isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }),
      titleVisibility: .visible
    ) {
      Button("Revoke key", role: .destructive) { if let key = revoking { Task { await revoke(key.id) } } }
    }
    .errorAlert($error)
    .task { await load() }
  }

  private func load() async {
    do {
      keys = try await rpc("Could not load your keys.") { await SettingsClients.apiKeys.listApiKeys(request: .init(), headers: [:]) }.apiKeys
    } catch { self.error = error.userMessage }
  }

  private func revoke(_ id: String) async {
    var request = Loci_Apikey_RevokeApiKeyRequest()
    request.id = id
    do {
      _ = try await rpc("Could not revoke the key.", request) { await SettingsClients.apiKeys.revokeApiKey(request: $0, headers: [:]) }
      await load()
    } catch { self.error = error.userMessage }
  }
}

/// Wraps a create response so it can drive `.sheet(item:)`.
struct IssuedKey: Identifiable {
  let response: Loci_Apikey_CreateApiKeyResponse
  var id: String { response.apiKey.id }
}

struct CreateKeySheet: View {
  /// web: lib/api/api-keys.ts API_KEY_SCOPES
  static let scopes: [KeyScope] = [
    KeyScope(value: "read", label: "Read", detail: "Search places and read your saved lists, favourites and itineraries."),
    KeyScope(value: "write", label: "Write", detail: "Add favourites, edit lists and change your saved itineraries."),
    KeyScope(value: "write:generate", label: "Generate", detail: "Run AI generation, which spends your daily quota."),
  ]

  let onIssued: (Loci_Apikey_CreateApiKeyResponse) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var clientKind = "claude_code"
  @State private var scopes: Set<String> = ["read"]
  @State private var isSaving = false
  @State private var error: String?

  var body: some View {
    NavigationStack {
      Form {
        Picker("Agent", selection: $clientKind) { ForEach(McpKeysSection.clientKinds, id: \.value) { Text($0.label).tag($0.value) } }
        TextField("Key name (e.g. Laptop)", text: $name)
        Section("Access") {
          ForEach(Self.scopes, id: \.value) { scope in
            let isOn = Binding(
              get: { scopes.contains(scope.value) },
              set: { if $0 { scopes.insert(scope.value) } else { scopes.remove(scope.value) } }
            )
            Toggle(isOn: isOn) {
              VStack(alignment: .leading) {
                Text(scope.label)
                Text(scope.detail).font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
              }
            }
          }
        }
      }
      .navigationTitle("Connect an agent").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Create") { Task { await create() } }
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || scopes.isEmpty || isSaving)
        }
      }
      .errorAlert($error)
    }
  }

  private func create() async {
    isSaving = true
    defer { isSaving = false }
    var request = Loci_Apikey_CreateApiKeyRequest()
    request.name = name.trimmingCharacters(in: .whitespaces)
    request.clientKind = clientKind
    request.scopes = Self.scopes.map(\.value).filter(scopes.contains)
    do {
      let response = try await rpc("Could not create the key.", request) { await SettingsClients.apiKeys.createApiKey(request: $0, headers: [:]) }
      dismiss()
      onIssued(response)
    } catch { self.error = error.userMessage }
  }
}

/// The plaintext key, shown once, with the setup snippet for that agent.
struct IssuedKeyView: View {
  let issued: Loci_Apikey_CreateApiKeyResponse
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section {
          Text(issued.plaintextKey).font(.lociCoord(13)).textSelection(.enabled)
          Button("Copy key", systemImage: "doc.on.doc") { UIPasteboard.general.string = issued.plaintextKey }
        } header: {
          Text("Your key")
        } footer: {
          Text("This is the only time Loci shows the whole key. Store it in your agent now.")
        }
        if issued.hasSetup { SetupBlocks(instructions: issued.setup) }
      }
      .navigationTitle("Key for \(McpKeysSection.label(for: issued.apiKey.clientKind))").navigationBarTitleDisplayMode(.inline)
      .toolbar { Button("Done") { dismiss() } }
    }
  }
}

/// Setup steps for an agent, without a key (ApiKeyService.GetSetupInstructions).
struct SetupInstructionsView: View {
  let clientKind: String
  @State private var instructions: Loci_Apikey_SetupInstructions?
  @State private var error: String?

  var body: some View {
    List {
      if let instructions { SetupBlocks(instructions: instructions) } else { ProgressView() }
    }
    .settingsStyle(McpKeysSection.label(for: clientKind))
    .errorAlert($error)
    .task {
      var request = Loci_Apikey_GetSetupInstructionsRequest()
      request.clientKind = clientKind
      do {
        instructions = try await rpc("Could not load the setup steps.", request) {
          await SettingsClients.apiKeys.getSetupInstructions(request: $0, headers: [:])
        }.instructions
      } catch { self.error = error.userMessage }
    }
  }
}

/// The server-built snippets (web: SetupBlocks.tsx): the config, the safer
/// variant, the export line and a prompt to try.
struct SetupBlocks: View {
  let instructions: Loci_Apikey_SetupInstructions

  var body: some View {
    if !instructions.config.isEmpty { block(instructions.configLabel.isEmpty ? "Config" : instructions.configLabel, instructions.config) }
    if !instructions.exportLine.isEmpty { block("Environment", instructions.exportLine) }
    if !instructions.safe.isEmpty {
      block(instructions.safeLabel.isEmpty ? "Keep the key out of the file" : instructions.safeLabel, instructions.safe, note: instructions.safeNote)
    }
    if !instructions.prompt.isEmpty { block("Try asking", instructions.prompt) }
  }

  private func block(_ title: String, _ text: String, note: String = "") -> some View {
    Section {
      Text(text).font(.lociCoord(12)).textSelection(.enabled)
      Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
    } header: {
      Text(title)
    } footer: {
      if !note.isEmpty { Text(note) }
    }
  }
}

// MARK: - Model provider

/// Bring your own model key. AiCredentialService: ListProviders, GetCredential,
/// SaveCredential{provider, apiKey, model, baseUrl}, VerifyCredential, DeleteCredential.
struct ModelProviderSection: View {
  @State private var providers: [Loci_Aicreds_Provider] = []
  @State private var enabled = false
  @State private var credential: Loci_Aicreds_Credential?
  @State private var isEditing = false
  @State private var status: String?
  @State private var error: String?

  var body: some View {
    if enabled {
      Section {
        if let credential {
          LabeledContent(providers.first { $0.name == credential.provider }?.label ?? credential.provider, value: credential.keyHint)
          if !credential.model.isEmpty { LabeledContent("Model", value: credential.model) }
          if !credential.lastError.isEmpty { Text(credential.lastError).foregroundStyle(Color.lociDestructive).font(.lociCaption()) }
          Button("Check it works") { Task { await verify() } }
          Button("Remove key", role: .destructive) { Task { await remove() } }
        } else {
          Button("Use my own model key", systemImage: "key") { isEditing = true }
        }
        if let status { Text(status).font(.lociCaption()) }
      } header: {
        Text("Model provider")
      } footer: {
        Text("Searches run on your key instead of Loci's.")
      }
      .sheet(isPresented: $isEditing) { SaveCredentialSheet(providers: providers) { credential = $0 } }
      .errorAlert($error)
    } else {
      Color.clear.frame(height: 0).listRowBackground(Color.clear).task { await load() }
    }
  }

  private func load() async {
    do {
      let list = try await rpc("") { await SettingsClients.aiCredentials.listProviders(request: .init(), headers: [:]) }
      providers = list.providers
      enabled = list.enabled
      guard list.enabled else { return }
      let current = try await rpc("") { await SettingsClients.aiCredentials.getCredential(request: .init(), headers: [:]) }
      credential = current.hasCredential ? current.credential : nil
    } catch { enabled = false }
  }

  private func verify() async {
    do {
      let result = try await rpc("Could not check the key.") {
        await SettingsClients.aiCredentials.verifyCredential(request: .init(), headers: [:])
      }
      status = !result.checked ? "This provider can't be checked from here." : result.ok ? "The key works." : result.error
    } catch { self.error = error.userMessage }
  }

  private func remove() async {
    do {
      _ = try await rpc("Could not remove the key.") { await SettingsClients.aiCredentials.deleteCredential(request: .init(), headers: [:]) }
      credential = nil
      status = nil
    } catch { self.error = error.userMessage }
  }
}

struct SaveCredentialSheet: View {
  let providers: [Loci_Aicreds_Provider]
  let onSaved: (Loci_Aicreds_Credential) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var provider = ""
  @State private var apiKey = ""
  @State private var model = ""
  @State private var baseURL = ""
  @State private var error: String?

  private var selected: Loci_Aicreds_Provider? { providers.first { $0.name == provider } }

  var body: some View {
    NavigationStack {
      Form {
        Picker("Provider", selection: $provider) { ForEach(providers, id: \.name) { Text($0.label).tag($0.name) } }
        SecureField(selected?.keyHint.isEmpty == false ? selected?.keyHint ?? "" : "API key", text: $apiKey)
        TextField(selected?.defaultModel.isEmpty == false ? "Model (\(selected?.defaultModel ?? ""))" : "Model", text: $model)
          .textInputAutocapitalization(.never).autocorrectionDisabled()
        if selected?.requiresBaseURL == true {
          TextField("Base URL", text: $baseURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
        }
        if let note = selected?.note, !note.isEmpty { Text(note).font(.lociCaption()).foregroundStyle(Color.lociMutedInk) }
      }
      .navigationTitle("Model key").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { Task { await save() } }
            .disabled(provider.isEmpty || apiKey.isEmpty || (selected?.requiresBaseURL == true && baseURL.isEmpty))
        }
      }
      .onAppear { if provider.isEmpty { provider = providers.first?.name ?? "" } }
      .errorAlert($error)
    }
  }

  private func save() async {
    var request = Loci_Aicreds_SaveCredentialRequest()
    request.provider = provider
    request.apiKey = apiKey
    request.model = model
    request.baseURL = baseURL
    do {
      let saved = try await rpc("Could not save the key.", request) { await SettingsClients.aiCredentials.saveCredential(request: $0, headers: [:]) }
      onSaved(saved.credential)
      dismiss()
    } catch { self.error = error.userMessage }
  }
}

// MARK: - Telegram

/// MessagingService with platform "telegram": GetLink, CreateLinkCode, Unlink.
struct TelegramSection: View {
  static let platform = "telegram"

  @State private var link: Loci_Messaging_GetLinkResponse?
  @State private var code: Loci_Messaging_CreateLinkCodeResponse?
  @State private var error: String?

  var body: some View {
    Section {
      if let link {
        if link.hasLink {
          LabeledContent("Linked", value: link.link.displayName.isEmpty ? "Telegram" : link.link.displayName)
          Button("Unlink", role: .destructive) { Task { await unlink() } }
        } else if let code {
          Text("Send this code to \(code.botHandle):").font(.lociCaption())
          Text(code.code).font(.lociCoord(18)).textSelection(.enabled)
          if let url = Self.deepLink(bot: code.botHandle, code: code.code) { Link("Open Telegram", destination: url) }
          Button("I've sent it") { Task { await load() } }
        } else if !link.botHandle.isEmpty {
          Button("Link Telegram", systemImage: "paperplane") { Task { await createCode() } }
        } else {
          Text("Telegram isn't available right now.").foregroundStyle(Color.lociMutedInk)
        }
      } else {
        ProgressView()
      }
    } header: {
      Text("Telegram")
    } footer: {
      Text("Plan trips and send voice notes to Loci from a Telegram chat.")
    }
    .errorAlert($error)
    .task { await load() }
  }

  /// web: lib/api/messaging.ts telegramDeepLink
  static func deepLink(bot: String, code: String) -> URL? {
    let handle = bot.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
    guard !handle.isEmpty, !code.isEmpty else { return nil }
    var components = URLComponents(string: "https://t.me/")
    components?.path = "/\(handle)"
    components?.queryItems = [URLQueryItem(name: "start", value: code)]
    return components?.url
  }

  private func load() async {
    var request = Loci_Messaging_GetLinkRequest()
    request.platform = Self.platform
    do {
      link = try await rpc("Could not load Telegram.", request) { await SettingsClients.messaging.getLink(request: $0, headers: [:]) }
      if link?.hasLink == true { code = nil }
    } catch { self.error = error.userMessage }
  }

  private func createCode() async {
    var request = Loci_Messaging_CreateLinkCodeRequest()
    request.platform = Self.platform
    do {
      code = try await rpc("Could not create a link code.", request) { await SettingsClients.messaging.createLinkCode(request: $0, headers: [:]) }
    } catch { self.error = error.userMessage }
  }

  private func unlink() async {
    var request = Loci_Messaging_UnlinkRequest()
    request.platform = Self.platform
    do {
      _ = try await rpc("Could not unlink Telegram.", request) { await SettingsClients.messaging.unlink(request: $0, headers: [:]) }
      await load()
    } catch { self.error = error.userMessage }
  }
}

// MARK: - Outbound MCP servers

/// MCP servers Loci calls out to. IntegrationService: ListConnections,
/// Connect{provider, endpoint, accessToken}, Disconnect{provider}, TestConnection{provider}.
struct OutboundConnectionsSection: View {
  /// web: lib/api/integrations.ts INTEGRATION_PROVIDERS
  static let providers: [IntegrationProvider] = [
    IntegrationProvider(name: "hermes", label: "Hermes", placeholder: "https://hermes.your-tailnet.ts.net/mcp"),
    IntegrationProvider(name: "calendar", label: "Calendar", placeholder: "https://calendar.example.com/mcp"),
  ]

  @State private var connections: [Loci_Integrations_Connection] = []
  @State private var enabled = false
  @State private var isAdding = false
  @State private var status: [String: String] = [:]
  @State private var error: String?

  var body: some View {
    if enabled {
      Section {
        ForEach(connections, id: \.provider) { connection in
          VStack(alignment: .leading, spacing: 2) {
            Text(Self.providers.first { $0.name == connection.provider }?.label ?? connection.provider)
            Text(connection.endpoint).font(.lociCoord(11)).foregroundStyle(Color.lociMutedInk).lineLimit(1)
            if let text = status[connection.provider] ?? (connection.lastError.isEmpty ? nil : connection.lastError) {
              Text(text).font(.lociCaption())
            }
          }
          .swipeActions {
            Button("Disconnect", role: .destructive) { Task { await disconnect(connection.provider) } }
            Button("Test") { Task { await test(connection.provider) } }.tint(Color.lociForestFill)
          }
        }
        Button("Connect a server", systemImage: "plus") { isAdding = true }
      } header: {
        Text("Servers Loci can call")
      }
      .sheet(isPresented: $isAdding) { ConnectServerSheet { Task { await load() } } }
      .errorAlert($error)
    } else {
      Color.clear.frame(height: 0).listRowBackground(Color.clear).task { await load() }
    }
  }

  private func load() async {
    do {
      let response = try await rpc("") { await SettingsClients.integrations.listConnections(request: .init(), headers: [:]) }
      enabled = response.enabled
      connections = response.connections
    } catch { enabled = false }
  }

  private func test(_ provider: String) async {
    var request = Loci_Integrations_TestConnectionRequest()
    request.provider = provider
    do {
      let result = try await rpc("Could not test the connection.", request) {
        await SettingsClients.integrations.testConnection(request: $0, headers: [:])
      }
      status[provider] = result.ok ? "Works — \(result.toolNames.count) tools" : result.error
    } catch { self.error = error.userMessage }
  }

  private func disconnect(_ provider: String) async {
    var request = Loci_Integrations_DisconnectRequest()
    request.provider = provider
    do {
      _ = try await rpc("Could not disconnect.", request) { await SettingsClients.integrations.disconnect(request: $0, headers: [:]) }
      await load()
    } catch { self.error = error.userMessage }
  }
}

struct ConnectServerSheet: View {
  let onConnected: () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var provider = OutboundConnectionsSection.providers[0].name
  @State private var endpoint = ""
  @State private var accessToken = ""
  @State private var error: String?

  var body: some View {
    NavigationStack {
      Form {
        Picker("Server", selection: $provider) { ForEach(OutboundConnectionsSection.providers, id: \.name) { Text($0.label).tag($0.name) } }
        TextField(OutboundConnectionsSection.providers.first { $0.name == provider }?.placeholder ?? "https://", text: $endpoint)
          .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
        SecureField("Access token (optional)", text: $accessToken)
      }
      .navigationTitle("Connect a server").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) { Button("Connect") { Task { await connect() } }.disabled(URL(string: endpoint)?.host() == nil) }
      }
      .errorAlert($error)
    }
  }

  private func connect() async {
    var request = Loci_Integrations_ConnectRequest()
    request.provider = provider
    request.endpoint = endpoint
    request.accessToken = accessToken
    do {
      _ = try await rpc("Could not connect.", request) { await SettingsClients.integrations.connect(request: $0, headers: [:]) }
      onConnected()
      dismiss()
    } catch { self.error = error.userMessage }
  }
}

/// An agent key permission (web: lib/api/api-keys.ts API_KEY_SCOPES).
struct KeyScope {
  let value: String
  let label: String
  let detail: String
}

/// An outbound MCP server kind (web: lib/api/integrations.ts INTEGRATION_PROVIDERS).
struct IntegrationProvider {
  let name: String
  let label: String
  let placeholder: String
}
