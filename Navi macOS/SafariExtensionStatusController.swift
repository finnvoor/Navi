import AppKit
import Observation
import SafariServices

private let extensionBundleIdentifier = "com.finnvoorhees.Navi.Extension"

// MARK: - SafariExtensionStatusController

@MainActor
@Observable final class SafariExtensionStatusController {
    private(set) var extensionEnabled: Bool?

    func refreshState() async {
        do {
            let state = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SFSafariExtensionState?, Error>) in
                SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: extensionBundleIdentifier) { state, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: state)
                    }
                }
            }
            extensionEnabled = state?.isEnabled
        } catch {
            extensionEnabled = false
        }
    }

    func openPreferences() async {
        await withCheckedContinuation { continuation in
            SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionBundleIdentifier) { _ in
                continuation.resume()
            }
        }
    }
}
