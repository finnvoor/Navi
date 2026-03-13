import Foundation
import Observation

// MARK: - AuthController

@Observable
@MainActor public final class AuthController {
    // MARK: Lifecycle

    public init(urlOpener: @escaping @MainActor (URL) -> Void = { _ in }) {
        self.urlOpener = urlOpener
        _provider = NaviSharedStorage.selectedProvider()
        Task { await refreshState() }
    }

    // MARK: Public

    public private(set) var isAuthenticated = false
    public private(set) var isWorking = false
    public private(set) var statusMessage = ""
    public private(set) var errorMessage: String?
    public private(set) var authorizationURL: URL?
    public private(set) var codePrompt: String?
    public var codeInput = ""

    public var provider: NaviProvider {
        get { _provider }
        set {
            guard newValue != _provider else { return }
            cancelCodeEntry()
            _provider = newValue
            NaviSharedStorage.setSelectedProvider(newValue)
            Task { await refreshState() }
        }
    }

    public var bridgeState: AuthBridgeState {
        AuthBridgeState(
            isAuthenticated: isAuthenticated,
            isWorking: isWorking,
            statusMessage: statusMessage,
            errorMessage: errorMessage,
            codePrompt: codePrompt,
            authorizationURL: authorizationURL?.absoluteString
        )
    }

    public func refreshState() async {
        do {
            let storage = try NaviSharedStorage.credentialStorage()
            let defaults = try NaviSharedStorage.userDefaults()
            if defaults.string(forKey: NaviSharedStorage.modelIDKey)?.isEmpty != false {
                defaults.set(_provider.defaultModelID, forKey: NaviSharedStorage.modelIDKey)
            }

            isAuthenticated = storage.has(_provider.oauthProviderID)
            if !isWorking {
                statusMessage = isAuthenticated
                    ? "\(_provider.displayName) is connected. Navi can use it in Safari."
                    : "Sign in with \(_provider.displayName) to enable the Safari extension."
            }
        } catch {
            isAuthenticated = false
            statusMessage = error.localizedDescription
        }
    }

    public func login() async {
        guard !isWorking else { return }

        errorMessage = nil
        statusMessage = "Preparing \(_provider.displayName) sign-in…"
        isWorking = true

        do {
            try await performOAuthLogin()
            authorizationURL = nil
            codePrompt = nil
            promptContinuation = nil
            isWorking = false
            statusMessage = "\(_provider.displayName) is connected. You can use Navi in Safari now."
            await refreshState()
        } catch {
            promptContinuation = nil
            codePrompt = nil
            authorizationURL = nil
            isWorking = false
            errorMessage = error.localizedDescription
            statusMessage = "\(_provider.displayName) sign-in failed."
            await refreshState()
        }
    }

    public func submitCode() {
        guard let continuation = promptContinuation else { return }

        let code = codeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            errorMessage = "Paste the authorization code or redirect URL."
            return
        }

        promptContinuation = nil
        codePrompt = nil
        errorMessage = nil
        statusMessage = "Finishing \(_provider.displayName) sign-in…"
        continuation.resume(returning: code)
    }

    public func cancelCodeEntry() {
        if let callbackServer {
            Task { await callbackServer.cancel() }
            self.callbackServer = nil
        }
        guard let continuation = promptContinuation else { return }

        promptContinuation = nil
        codePrompt = nil
        statusMessage = "\(_provider.displayName) sign-in cancelled."
        continuation.resume(throwing: AuthError.cancelled)
    }

    public func logout() async {
        do {
            let storage = try NaviSharedStorage.credentialStorage()
            storage.remove(_provider.oauthProviderID)
            errorMessage = nil
            authorizationURL = nil
            codePrompt = nil
            promptContinuation = nil
            statusMessage = "\(_provider.displayName) has been disconnected."
            await refreshState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func reopenAuthorizationPage() {
        guard let authorizationURL else { return }
        urlOpener(authorizationURL)
    }

    // MARK: Private

    private var _provider: NaviProvider
    private var promptContinuation: CheckedContinuation<String, Error>?
    private var oauthVerifier: String?
    private let urlOpener: @MainActor (URL) -> Void

    private var callbackServer: OAuthCallbackServer?

    private func performOAuthLogin() async throws {
        switch _provider {
        case .anthropic:
            try await performAnthropicLogin()
        case .codex:
            try await performCodexLogin()
        }
    }

    private func performAnthropicLogin() async throws {
        let storage = try NaviSharedStorage.credentialStorage()
        let flow = AnthropicOAuthFlow()

        let (authURL, verifier) = try flow.startAuthorization()
        oauthVerifier = verifier

        authorizationURL = authURL
        statusMessage = "Complete the sign-in in your browser, then paste the code here."
        urlOpener(authURL)

        codeInput = ""
        codePrompt = "Paste the authorization code or redirect URL:"
        statusMessage = "Paste the authorization code or redirect URL to finish sign-in."

        let code = try await withCheckedThrowingContinuation { continuation in
            self.promptContinuation = continuation
        }

        guard let verifier = oauthVerifier else {
            throw AuthError.cancelled
        }

        statusMessage = "Exchanging code for tokens…"
        let tokens = try await flow.exchangeCode(code, verifier: verifier)
        oauthVerifier = nil

        storage.set(
            _provider.oauthProviderID,
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            expiresAt: tokens.expiresAt
        )
    }

    private func performCodexLogin() async throws {
        let storage = try NaviSharedStorage.credentialStorage()
        let flow = CodexOAuthFlow()

        let (authURL, verifier) = try flow.startAuthorization()
        oauthVerifier = verifier

        // Extract state from combined verifier#state
        let parts = verifier.split(separator: "#", maxSplits: 1)
        let expectedState = parts.count > 1 ? String(parts[1]) : nil

        // Start callback server to intercept the redirect
        let callbackServer = OAuthCallbackServer()
        self.callbackServer = callbackServer

        authorizationURL = authURL
        statusMessage = "Signing in with Codex…"
        urlOpener(authURL)

        // Also show manual paste as fallback
        codeInput = ""
        codePrompt = "Or paste the redirect URL here if the browser didn't redirect:"

        // Start server — when it receives the code, resume the prompt continuation
        Task {
            if let code = try? await callbackServer.start(expectedState: expectedState) {
                if let continuation = self.promptContinuation {
                    self.promptContinuation = nil
                    self.codePrompt = nil
                    continuation.resume(returning: code)
                }
            }
        }

        // Wait for either: server callback resumes this, or user manually pastes
        let code = try await withCheckedThrowingContinuation { continuation in
            self.promptContinuation = continuation
        }
        await callbackServer.stop()
        self.callbackServer = nil

        self.callbackServer = nil
        guard let verifier = oauthVerifier else {
            throw AuthError.cancelled
        }

        statusMessage = "Exchanging code for tokens…"
        let tokens = try await flow.exchangeCode(code, verifier: verifier)
        oauthVerifier = nil

        storage.set(
            _provider.oauthProviderID,
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            expiresAt: tokens.expiresAt
        )
        storage.setExtra(_provider.oauthProviderID, key: "accountID", value: tokens.accountID)
    }
}

// MARK: - AuthError

enum AuthError: LocalizedError {
    case cancelled

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .cancelled:
            "Sign-in was cancelled."
        }
    }
}
