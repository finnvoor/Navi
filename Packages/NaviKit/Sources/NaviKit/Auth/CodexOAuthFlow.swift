import CryptoKit
import Foundation

// MARK: - CodexOAuthFlow

struct CodexOAuthFlow {
    // MARK: Internal

    struct Tokens: Sendable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Double
        var accountID: String
    }

    static func refreshToken(_ refreshToken: String) async throws -> Tokens {
        let url = URL(string: tokenEndpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ]

        request.httpBody = Self.urlEncodedBody(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            throw OAuthFlowError.refreshFailed(responseBody)
        }

        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let accountID = Self.extractAccountID(from: token.access_token) else {
            throw OAuthFlowError.exchangeFailed("Failed to extract account ID from token")
        }

        let nowMs = Date().timeIntervalSince1970 * 1000
        let expiresAt = nowMs + token.expires_in * 1000 - 5 * 60 * 1000

        return Tokens(
            accessToken: token.access_token,
            refreshToken: token.refresh_token,
            expiresAt: expiresAt,
            accountID: accountID
        )
    }

    func startAuthorization() throws -> (url: URL, verifier: String) {
        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(from: verifier)
        let state = generateState()

        var components = URLComponents(string: Self.authorizeEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "originator", value: "navi"),
        ]

        guard let url = components.url else {
            throw OAuthFlowError.invalidURL
        }

        // Store state alongside verifier using # separator
        return (url, "\(verifier)#\(state)")
    }

    func exchangeCode(_ codeOrRedirectURL: String, verifier: String) async throws -> Tokens {
        let parsed = parseAuthorizationInput(codeOrRedirectURL)
        guard let code = parsed.code, !code.isEmpty else {
            throw OAuthFlowError.invalidCode
        }

        // Extract verifier and state from combined string
        let parts = verifier.split(separator: "#", maxSplits: 1)
        let actualVerifier = String(parts[0])

        let url = URL(string: Self.tokenEndpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "authorization_code",
            "client_id": Self.clientID,
            "code": code,
            "code_verifier": actualVerifier,
            "redirect_uri": Self.redirectURI,
        ]

        request.httpBody = Self.urlEncodedBody(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            throw OAuthFlowError.exchangeFailed(responseBody)
        }

        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let accountID = Self.extractAccountID(from: token.access_token) else {
            throw OAuthFlowError.exchangeFailed("Failed to extract account ID from token")
        }

        let nowMs = Date().timeIntervalSince1970 * 1000
        let expiresAt = nowMs + token.expires_in * 1000 - 5 * 60 * 1000

        return Tokens(
            accessToken: token.access_token,
            refreshToken: token.refresh_token,
            expiresAt: expiresAt,
            accountID: accountID
        )
    }

    // MARK: Private

    private struct TokenResponse: Decodable {
        var access_token: String
        var refresh_token: String
        var expires_in: Double
    }

    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private static let authorizeEndpoint = "https://auth.openai.com/oauth/authorize"
    private static let tokenEndpoint = "https://auth.openai.com/oauth/token"
    private static let redirectURI = "http://localhost:1455/auth/callback"
    private static let scopes = "openid profile email offline_access"

    // MARK: - JWT

    private static func extractAccountID(from token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }

        var base64 = String(parts[1])
        // Pad base64 to multiple of 4
        while base64.count % 4 != 0 {
            base64 += "="
        }
        base64 = base64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = json["https://api.openai.com/auth"] as? [String: Any],
              let accountID = auth["chatgpt_account_id"] as? String,
              !accountID.isEmpty
        else { return nil }

        return accountID
    }

    private static func urlEncodedBody(_ params: [String: String]) -> Data {
        params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)!
    }

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

    private func generateState() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Input Parsing

    private func parseAuthorizationInput(_ input: String) -> (code: String?, state: String?) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (nil, nil) }

        if let url = URL(string: trimmed),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            let code = components.queryItems?.first { $0.name == "code" }?.value
            let state = components.queryItems?.first { $0.name == "state" }?.value
            if code != nil || state != nil {
                return (code, state)
            }
        }

        if trimmed.contains("#") {
            let parts = trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            let code = parts.first.map(String.init)
            let state = parts.count > 1 ? String(parts[1]) : nil
            return (code, state)
        }

        if trimmed.contains("code=") {
            let prefixed = "https://localhost/?" + trimmed
            if let url = URL(string: prefixed),
               let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                let code = components.queryItems?.first { $0.name == "code" }?.value
                let state = components.queryItems?.first { $0.name == "state" }?.value
                return (code, state)
            }
        }

        return (trimmed, nil)
    }
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
