import CryptoKit
import Foundation

// MARK: - AnthropicOAuthFlow

struct AnthropicOAuthFlow {
    // MARK: Internal

    struct Tokens: Sendable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Double
    }

    static func refreshToken(_ refreshToken: String) async throws -> Tokens {
        let url = URL(string: tokenEndpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "client_id": clientID,
            "refresh_token": refreshToken,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            throw OAuthFlowError.refreshFailed(responseBody)
        }

        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        let nowMs = Date().timeIntervalSince1970 * 1000
        let expiresAt = nowMs + token.expires_in * 1000 - 5 * 60 * 1000

        return Tokens(accessToken: token.access_token, refreshToken: token.refresh_token, expiresAt: expiresAt)
    }

    func startAuthorization() throws -> (url: URL, verifier: String) {
        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(from: verifier)

        var components = URLComponents(string: "https://claude.ai/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: verifier),
        ]

        guard let url = components.url else {
            throw OAuthFlowError.invalidURL
        }

        return (url, verifier)
    }

    func exchangeCode(_ codeOrRedirectURL: String, verifier: String) async throws -> Tokens {
        let parsed = parseAuthorizationInput(codeOrRedirectURL)
        guard let code = parsed.code, !code.isEmpty else {
            throw OAuthFlowError.invalidCode
        }

        if let state = parsed.state, state != verifier {
            throw OAuthFlowError.stateMismatch
        }

        let url = URL(string: "\(Self.tokenEndpoint)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "grant_type": "authorization_code",
            "client_id": Self.clientID,
            "code": code,
            "state": verifier,
            "redirect_uri": Self.redirectURI,
            "code_verifier": verifier,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            throw OAuthFlowError.exchangeFailed(responseBody)
        }

        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        let nowMs = Date().timeIntervalSince1970 * 1000
        let expiresAt = nowMs + token.expires_in * 1000 - 5 * 60 * 1000

        return Tokens(accessToken: token.access_token, refreshToken: token.refresh_token, expiresAt: expiresAt)
    }

    // MARK: Private

    // MARK: - Response Types

    private struct TokenResponse: Decodable {
        var access_token: String
        var refresh_token: String
        var expires_in: Double
    }

    // MARK: - Constants

    private static let clientID: String = {
        let encoded = "OWQxYzI1MGEtZTYxYi00NGQ5LTg4ZWQtNTk0NGQxOTYyZjVl"
        if let data = Data(base64Encoded: encoded), let decoded = String(data: data, encoding: .utf8) {
            return decoded
        }
        return encoded
    }()

    private static let redirectURI = "https://platform.claude.com/oauth/code/callback"
    private static let tokenEndpoint = "https://platform.claude.com/v1/oauth/token"
    private static let scopes = "org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload"

    // MARK: - PKCE

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncoded
    }

    // MARK: - Input Parsing

    private func parseAuthorizationInput(_ input: String) -> (code: String?, state: String?) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (nil, nil) }

        // Try as a full URL
        if let url = URL(string: trimmed),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            let code = components.queryItems?.first { $0.name == "code" }?.value
            let state = components.queryItems?.first { $0.name == "state" }?.value
            if code != nil || state != nil {
                return (code, state)
            }
        }

        // Try as code#state
        if trimmed.contains("#") {
            let parts = trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            let code = parts.first.map(String.init)
            let state = parts.count > 1 ? String(parts[1]) : nil
            return (code, state)
        }

        // Try as a query string fragment
        if trimmed.contains("code=") {
            let prefixed = "https://localhost/?" + trimmed
            if let url = URL(string: prefixed),
               let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                let code = components.queryItems?.first { $0.name == "code" }?.value
                let state = components.queryItems?.first { $0.name == "state" }?.value
                return (code, state)
            }
        }

        // Raw code string
        return (trimmed, nil)
    }
}

// MARK: - OAuthFlowError

enum OAuthFlowError: LocalizedError {
    case invalidURL
    case invalidCode
    case stateMismatch
    case exchangeFailed(String)
    case refreshFailed(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Could not build OAuth URL."
        case .invalidCode: "The authorization code or redirect URL was invalid."
        case .stateMismatch: "OAuth state mismatch. Try signing in again."
        case let .exchangeFailed(body): "Token exchange failed: \(body.prefix(200))"
        case let .refreshFailed(body): "Token refresh failed: \(body.prefix(200))"
        }
    }
}

// MARK: - Base64URL

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
