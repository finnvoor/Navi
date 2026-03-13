import Foundation
import Valet

// MARK: - CredentialStorage

struct CredentialStorage {
    // MARK: Lifecycle

    init(sharedAccessGroupIdentifier identifier: SharedGroupIdentifier) {
        valet = Valet.sharedGroupValet(with: identifier, accessibility: .afterFirstUnlock)
    }

    // MARK: Internal

    func has(_ provider: String) -> Bool {
        (try? valet.string(forKey: key(provider, "access"))) != nil
    }

    func getAPIKey(_ provider: String) async -> String? {
        guard let accessToken = try? valet.string(forKey: key(provider, "access")),
              !accessToken.isEmpty else { return nil }

        let nowMs = Date().timeIntervalSince1970 * 1000
        let expires = (try? valet.string(forKey: key(provider, "expires"))).flatMap(Double.init) ?? 0

        if nowMs >= expires {
            guard let refreshToken = try? valet.string(forKey: key(provider, "refresh")),
                  !refreshToken.isEmpty else { return nil }

            switch provider {
            case NaviProvider.codex.oauthProviderID:
                guard let refreshed = try? await CodexOAuthFlow.refreshToken(refreshToken) else { return nil }
                set(provider, accessToken: refreshed.accessToken, refreshToken: refreshed.refreshToken, expiresAt: refreshed.expiresAt)
                setExtra(provider, key: "accountID", value: refreshed.accountID)
                return refreshed.accessToken

            default:
                guard let refreshed = try? await AnthropicOAuthFlow.refreshToken(refreshToken) else { return nil }
                set(provider, accessToken: refreshed.accessToken, refreshToken: refreshed.refreshToken, expiresAt: refreshed.expiresAt)
                return refreshed.accessToken
            }
        }

        return accessToken
    }

    func getExtra(_ provider: String, key extraKey: String) -> String? {
        try? valet.string(forKey: key(provider, extraKey))
    }

    func setExtra(_ provider: String, key extraKey: String, value: String) {
        try? valet.setString(value, forKey: key(provider, extraKey))
    }

    func set(_ provider: String, accessToken: String, refreshToken: String?, expiresAt: Double?) {
        try? valet.setString(accessToken, forKey: key(provider, "access"))
        if let refreshToken {
            try? valet.setString(refreshToken, forKey: key(provider, "refresh"))
        }
        if let expiresAt {
            try? valet.setString(String(expiresAt), forKey: key(provider, "expires"))
        }
    }

    func remove(_ provider: String) {
        try? valet.removeObject(forKey: key(provider, "access"))
        try? valet.removeObject(forKey: key(provider, "refresh"))
        try? valet.removeObject(forKey: key(provider, "expires"))
        try? valet.removeObject(forKey: key(provider, "accountID"))
    }

    // MARK: Private

    private let valet: Valet

    private func key(_ provider: String, _ field: String) -> String {
        "\(provider).\(field)"
    }
}
