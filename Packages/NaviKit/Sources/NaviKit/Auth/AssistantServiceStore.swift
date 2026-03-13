import Foundation

// MARK: - AssistantServiceConfiguration

struct AssistantServiceConfiguration: Sendable {
    var provider: NaviProvider
    var modelID: String
    var apiKey: String
    var accountID: String?
}

// MARK: - AssistantServiceStore

struct AssistantServiceStore {
    // MARK: Internal

    func loadSnapshot() throws -> AssistantServiceSnapshot {
        let provider = NaviSharedStorage.selectedProvider()
        return try AssistantServiceSnapshot(
            provider: provider,
            modelID: storedModelID(for: provider),
            isAuthenticated: hasAuthenticatedSession(for: provider)
        )
    }

    func loadConfiguration() async throws -> AssistantServiceConfiguration {
        let provider = NaviSharedStorage.selectedProvider()
        let modelID = storedModelID(for: provider)
        guard let apiKey = try await currentCredential(for: provider) else {
            throw AssistantServiceError.missingAuthentication(provider)
        }

        let trimmedCredential = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCredential.isEmpty else {
            throw AssistantServiceError.invalidCredential(provider)
        }

        let storage = try NaviSharedStorage.credentialStorage()
        let accountID = storage.getExtra(provider.oauthProviderID, key: "accountID")
        return AssistantServiceConfiguration(provider: provider, modelID: modelID, apiKey: trimmedCredential, accountID: accountID)
    }

    func storedModelID(for provider: NaviProvider) -> String {
        let defaults = try? NaviSharedStorage.userDefaults()
        let value = defaults?.string(forKey: NaviSharedStorage.modelIDKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value! : provider.defaultModelID
    }

    // MARK: Private

    private func currentCredential(for provider: NaviProvider) async throws -> String? {
        let storage = try NaviSharedStorage.credentialStorage()
        return await storage.getAPIKey(provider.oauthProviderID)
    }

    private func hasAuthenticatedSession(for provider: NaviProvider) throws -> Bool {
        let storage = try NaviSharedStorage.credentialStorage()
        return storage.has(provider.oauthProviderID)
    }
}

// MARK: - AssistantServiceError

enum AssistantServiceError: LocalizedError {
    case missingAuthentication(NaviProvider)
    case invalidCredential(NaviProvider)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .missingAuthentication(provider):
            "Open the Navi app and sign in with \(provider.displayName) before starting Navi."
        case let .invalidCredential(provider):
            "The stored \(provider.displayName) credential is not valid."
        }
    }
}
