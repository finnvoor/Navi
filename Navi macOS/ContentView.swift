import NaviKit
import Observation
import SwiftUI

// MARK: - ContentView

struct ContentView: View {
    // MARK: Internal

    let authController: AuthController
    let extensionController: SafariExtensionStatusController

    var body: some View {
        @Bindable var authController = authController
        @Bindable var extensionController = extensionController

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("NAVI")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(2.8)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 12) {
                    Text("AI Provider for Safari")
                        .font(.system(size: 30, weight: .bold, design: .rounded))

                    Text("Choose your AI provider and sign in. The Safari extension will use the same login on macOS.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 14) {
                    StatusBadge(
                        isActive: extensionController.extensionEnabled == true,
                        activeTitle: "Safari Extension Enabled",
                        inactiveTitle: "Safari Extension Required",
                        text: extensionMessage
                    )

                    Button("Open Safari Settings") {
                        Task { await extensionController.openPreferences() }
                    }
                    .buttonStyle(.bordered)
                }

                Picker("Provider", selection: $authController.provider) {
                    ForEach(NaviProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 14) {
                    StatusBadge(
                        isActive: authController.isAuthenticated,
                        activeTitle: "\(authController.provider.displayName) Connected",
                        inactiveTitle: "\(authController.provider.displayName) Required",
                        text: authController.statusMessage
                    )

                    HStack(spacing: 12) {
                        Button(authController.isAuthenticated ? "Reconnect \(authController.provider.displayName)" : "Sign In with \(authController.provider.displayName)") {
                            Task { await authController.login() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.accentColor)
                        .disabled(authController.isWorking)

                        if authController.isAuthenticated {
                            Button("Disconnect") {
                                Task { await authController.logout() }
                            }
                            .buttonStyle(.bordered)
                            .disabled(authController.isWorking)
                        } else if authController.authorizationURL != nil {
                            Button("Open Login Again") {
                                authController.reopenAuthorizationPage()
                            }
                            .buttonStyle(.bordered)
                            .disabled(authController.isWorking)
                        }
                    }

                    if let codePrompt = authController.codePrompt {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(codePrompt)
                                .font(.subheadline.weight(.semibold))

                            TextField("Paste the authorization code or redirect URL", text: $authController.codeInput, axis: .vertical)
                                .textFieldStyle(.roundedBorder)

                            HStack(spacing: 12) {
                                Button("Finish Sign-In") {
                                    authController.submitCode()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.accentColor)

                                Button("Cancel") {
                                    authController.cancelCodeEntry()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                    }

                    if let errorMessage = authController.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    InstructionRow(number: "1", text: "Enable the Navi extension in Safari Settings > Extensions.")
                    InstructionRow(number: "2", text: "Allow Navi on the sites you want it to inspect or control.")
                    InstructionRow(number: "3", text: "Open Safari and click the Navi toolbar button.")
                    InstructionRow(number: "4", text: "Ask Navi to summarize the page or drive the tab.")
                }

                Text("Navi will use the \(authController.provider.displayName) login stored in the app to summarize pages and drive Safari actions through the extension.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .frame(minWidth: 420, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await extensionController.refreshState()
            await authController.refreshState()
        }
    }

    // MARK: Private

    private var extensionMessage: String {
        if extensionController.extensionEnabled == true {
            "Safari's Navi extension is enabled."
        } else if extensionController.extensionEnabled == false {
            "Safari's Navi extension is off. Turn it on in Safari Settings > Extensions."
        } else {
            "Checking Safari's Navi extension status…"
        }
    }
}

// MARK: - StatusBadge

private struct StatusBadge: View {
    let isActive: Bool
    let activeTitle: String
    let inactiveTitle: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isActive ? Color.green : Color.accentColor)
                    .frame(width: 10, height: 10)

                Text(isActive ? activeTitle : inactiveTitle)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(1.4)
            }

            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

// MARK: - InstructionRow

private struct InstructionRow: View {
    let number: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor))

            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    ContentView(
        authController: AuthController(),
        extensionController: SafariExtensionStatusController()
    )
}
