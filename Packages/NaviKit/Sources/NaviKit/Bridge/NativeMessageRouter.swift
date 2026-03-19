import Foundation
#if canImport(AppKit)
import AppKit
#endif

// MARK: - NativeMessageRouter

public enum NativeMessageRouter {
    public static func handle(message: [String: Any]) async -> [String: Any] {
        do {
            let request = try NativeBridgeRequest(message: message)
            let response = try await route(request)
            return try response.dictionary()
        } catch {
            return [
                "ok": false,
                "error": displayMessage(for: error),
            ]
        }
    }
}

private extension NativeMessageRouter {
    static func route(_ request: NativeBridgeRequest) async throws -> NativeBridgeResponse {
        switch request {
        case .loadServiceState:
            return try await .serviceState(BrowserAgentCoordinator.shared.loadServiceState())

        case let .startRun(prompt, conversation):
            return try await .run(BrowserAgentCoordinator.shared.startRun(prompt: prompt, conversation: conversation))

        case let .getRun(runID):
            return try await .run(BrowserAgentCoordinator.shared.getRun(runID: runID))

        case let .cancelRun(runID):
            return try await .run(BrowserAgentCoordinator.shared.cancelRun(runID: runID))

        case let .submitToolResult(runID, callID, result):
            return try await .run(BrowserAgentCoordinator.shared.submitToolResult(runID: runID, callID: callID, result: result))

        case .checkForUpdates:
            await requestCheckForUpdates()
            return .ok
        }
    }

    static func requestCheckForUpdates() async {
        #if canImport(AppKit)
        UpdateRequestBridge.markPendingCheckForUpdates()
        DistributedNotificationCenter.default().post(name: UpdateRequestBridge.notificationName, object: nil)
        await openContainingApp()
        #endif
    }

    static func openContainingApp() async {
        #if canImport(AppKit)
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.finnvoorhees.Navi") else { return }
        try? await NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
        #endif
    }

    static func displayMessage(for error: Error) -> String {
        if let bridgeError = error as? NativeBridgeError {
            return bridgeError.localizedDescription
        }

        return error.localizedDescription
    }
}
