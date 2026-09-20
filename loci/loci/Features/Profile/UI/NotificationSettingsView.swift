import SwiftUI
import UserNotifications

public struct NotificationSettingsView: View {
    @ObservedObject private var notificationManager = PushNotificationManager.shared
    @State private var isRequesting: Bool = false

    public init() {}

    public var body: some View {
        List {
            Section("Push Notifications") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Status")
                            .font(.body.weight(.medium))
                        Text(statusDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    statusBadge
                }

                if notificationManager.authorizationStatus == .notDetermined {
                    Button {
                        requestPermission()
                    } label: {
                        HStack {
                            if isRequesting {
                                ProgressView()
                                    .padding(.trailing, 4)
                            }
                            Text("Enable Notifications")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isRequesting)
                } else if notificationManager.authorizationStatus == .denied {
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
            .listRowBackground(Color.lociCard)

            if let token = notificationManager.deviceToken {
                Section("APNS Device Token") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Active Token")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.secondary)
                        Text(token)
                            .font(.system(.caption2, design: .monospaced))
                            .lineLimit(3)
                            .foregroundColor(.lociInk)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.lociCard)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.lociPaper.ignoresSafeArea())
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await notificationManager.refreshAuthorizationStatus()
        }
    }

    private var statusDescription: String {
        switch notificationManager.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "Push notifications are active and ready."
        case .denied:
            return "Notifications are disabled in iOS Settings."
        case .notDetermined:
            return "Permissions have not been requested yet."
        @unknown default:
            return "Unknown authorization status."
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch notificationManager.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            Label("Active", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundColor(.green)
        case .denied:
            Label("Disabled", systemImage: "xmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundColor(.red)
        case .notDetermined:
            Label("Not Enabled", systemImage: "questionmark.circle")
                .font(.caption)
                .foregroundColor(.orange)
        @unknown default:
            EmptyView()
        }
    }

    private func requestPermission() {
        isRequesting = true
        Task {
            await notificationManager.requestAuthorization()
            isRequesting = false
        }
    }
}
