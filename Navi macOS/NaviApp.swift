import AppKit
import Combine
import NaviKit
import Observation
import Sparkle
import SwiftUI

// MARK: - NaviApp

@main struct NaviApp: App {
    // MARK: Internal

    var body: some Scene {
        WindowGroup {
            ContentView(
                authController: authController,
                extensionController: extensionController
            )
        }
        .defaultSize(width: 440, height: 560)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }

    // MARK: Private

    @State private var authController = AuthController { url in
        NSWorkspace.shared.open(url)
    }

    @State private var extensionController = SafariExtensionStatusController()

    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
}

// MARK: - CheckForUpdatesView

private struct CheckForUpdatesView: View {
    // MARK: Lifecycle

    init(updater: SPUUpdater) {
        _viewModel = State(initialValue: CheckForUpdatesViewModel(updater: updater))
    }

    // MARK: Internal

    var body: some View {
        Button("Check for Updates…", action: viewModel.updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }

    // MARK: Private

    @State private var viewModel: CheckForUpdatesViewModel
}

// MARK: - CheckForUpdatesViewModel

@Observable private final class CheckForUpdatesViewModel {
    // MARK: Lifecycle

    init(updater: SPUUpdater) {
        self.updater = updater
        cancellable = updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
    }

    // MARK: Internal

    let updater: SPUUpdater
    var canCheckForUpdates = false

    // MARK: Private

    private var cancellable: AnyCancellable?
}
