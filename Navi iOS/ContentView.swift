import NaviKit
import Observation
import SwiftUI
import UIKit

// MARK: - ContentView

struct ContentView: View {
    // MARK: Lifecycle

    init() {
        _auth = State(initialValue: AuthController { url in
            UIApplication.shared.open(url)
        })
    }

    // MARK: Internal

    var body: some View {
        @Bindable var auth = auth

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("NAVI")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(2.8)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 12) {
                    Text("AI Provider for Safari")
                        .font(.system(size: 30, weight: .bold, design: .rounded))

                    Text("Choose your AI provider and sign in. The Safari extension will use the same login.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Picker("Provider", selection: $auth.provider) {
                    ForEach(NaviProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 14) {
                    StatusBadge(isAuthenticated: auth.isAuthenticated, text: auth.statusMessage)

                    HStack(spacing: 12) {
                        Button(auth.isAuthenticated ? "Reconnect \(auth.provider.displayName)" : "Sign In with \(auth.provider.displayName)") {
                            Task { await auth.login() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.accentColor)
                        .disabled(auth.isWorking)

                        if auth.isAuthenticated {
                            Button("Disconnect") {
                                Task { await auth.logout() }
                            }
                            .buttonStyle(.bordered)
                            .disabled(auth.isWorking)
                        } else if auth.authorizationURL != nil {
                            Button("Open Login Again") {
                                auth.reopenAuthorizationPage()
                            }
                            .buttonStyle(.bordered)
                            .disabled(auth.isWorking)
                        }
                    }

                    if let codePrompt = auth.codePrompt {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(codePrompt)
                                .font(.subheadline.weight(.semibold))

                            TextField("Paste the authorization code or redirect URL", text: $auth.codeInput, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                            HStack(spacing: 12) {
                                Button("Finish Sign-In") {
                                    auth.submitCode()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.accentColor)

                                Button("Cancel") {
                                    auth.cancelCodeEntry()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        )
                    }

                    if let errorMessage = auth.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Color.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    InstructionRow(number: "1", text: "Open the Settings app.")
                    InstructionRow(number: "2", text: "Go to Apps > Safari > Extensions.")
                    InstructionRow(number: "3", text: "Turn on Navi.")
                    InstructionRow(number: "4", text: "Allow Navi on websites you want it to control.")
                    InstructionRow(number: "5", text: "Open Safari and tap the Navi extension button.")
                }

                Text("Navi will use the \(auth.provider.displayName) login stored in the app to summarize pages and drive Safari actions through the extension.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .task {
            await auth.refreshState()
        }
    }

    // MARK: Private

    @State private var auth: AuthController
}

// MARK: - StatusBadge

private struct StatusBadge: View {
    let isAuthenticated: Bool
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isAuthenticated ? Color.green : Color.accentColor)
                    .frame(width: 10, height: 10)

                Text(isAuthenticated ? "Connected" : "Sign-In Required")
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
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
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
    ContentView()
}
