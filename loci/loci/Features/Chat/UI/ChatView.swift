import SwiftUI
import Connect
import LociConnectProto

public struct ChatMessageItem: Identifiable {
    public let id = UUID()
    public let role: String
    public let text: String
}

public struct ChatView: View {
    @State private var messages: [ChatMessageItem] = [
        ChatMessageItem(role: "assistant", text: "Hello! I'm your Loci travel companion. Where would you like to explore or plan an itinerary for?")
    ]
    @State private var inputText: String = ""
    @State private var sessionId: String?
    @State private var isSending: Bool = false

    private let client: Loci_Chat_ChatServiceClient

    public init(client: Loci_Chat_ChatServiceClient = Loci_Chat_ChatServiceClient(client: ConnectTransport.shared.protocolClient)) {
        self.client = client
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Messages List
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(messages) { msg in
                                HStack {
                                    if msg.role == "user" {
                                        Spacer()
                                        Text(msg.text)
                                            .padding(14)
                                            .background(Color.lociCoral)
                                            .foregroundColor(.white)
                                            .cornerRadius(LociTheme.cornerRadius)
                                            .frame(maxWidth: 280, alignment: .trailing)
                                    } else {
                                        HStack(alignment: .top, spacing: 8) {
                                            Image("LociMascot")
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 32, height: 32)
                                                .padding(.top, 4)

                                            Text(msg.text)
                                                .padding(14)
                                                .background(Color.lociCard)
                                                .foregroundColor(.lociInk)
                                                .cornerRadius(LociTheme.cornerRadius)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: LociTheme.cornerRadius)
                                                        .stroke(Color.lociBorder.opacity(0.6), lineWidth: LociTheme.borderWidth)
                                                )
                                                .frame(maxWidth: 280, alignment: .leading)
                                        }
                                        Spacer()
                                    }
                                }
                                .id(msg.id)
                            }

                            if isSending {
                                HStack {
                                    ProgressView()
                                        .padding(.leading, 40)
                                    Spacer()
                                }
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: messages.count) {
                        if let last = messages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                // Input Bar
                HStack(spacing: 10) {
                    TextField("Ask anything about your destination...", text: $inputText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.lociCard)
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.lociBorder.opacity(0.6), lineWidth: LociTheme.borderWidth)
                        )
                        .onSubmit {
                            sendMessage()
                        }

                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? .lociInk.opacity(0.3) : .lociCoral)
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.lociPaper)
            }
            .background(Color.lociPaper.ignoresSafeArea())
            .navigationTitle("AI Assistant")
        }
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isSending else { return }

        inputText = ""
        messages.append(ChatMessageItem(role: "user", text: trimmed))
        isSending = true

        Task {
            var headers: Connect.Headers = [:]
            if let token = try? await AuthSessionManager.shared.validAccessToken() {
                headers["Authorization"] = ["Bearer \(token)"]
            }

            if let currentSession = sessionId {
                var request = Loci_Chat_ContinueChatRequest()
                request.sessionID = currentSession
                request.message = trimmed

                let response = await client.continueChat(request: request, headers: headers)
                await MainActor.run {
                    self.isSending = false
                    if let msg = response.message {
                        self.messages.append(ChatMessageItem(role: "assistant", text: msg.message))
                    } else if let error = response.error {
                        self.messages.append(ChatMessageItem(role: "assistant", text: "Error: \(error.message ?? "Unknown")"))
                    }
                }
            } else {
                var request = Loci_Chat_StartChatRequest()
                request.initialMessage = trimmed

                let response = await client.startChat(request: request, headers: headers)
                await MainActor.run {
                    self.isSending = false
                    if let msg = response.message {
                        self.sessionId = msg.sessionID
                        self.messages.append(ChatMessageItem(role: "assistant", text: msg.message))
                    } else if let error = response.error {
                        self.messages.append(ChatMessageItem(role: "assistant", text: "Error: \(error.message ?? "Unknown")"))
                    }
                }
            }
        }
    }
}
