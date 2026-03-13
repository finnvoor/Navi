import Foundation
import Network
#if canImport(AppKit)
import AppKit
#endif

// MARK: - OAuthCallbackServer

actor OAuthCallbackServer {
    // MARK: Internal

    func start(port: UInt16 = 1455, expectedState: String?) async throws -> String {
        let params = NWParameters.tcp
        let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        self.listener = listener

        let code = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            self.continuation = cont

            listener.newConnectionHandler = { [weak self] connection in
                Task { await self?.handleConnection(connection, expectedState: expectedState) }
            }

            listener.stateUpdateHandler = { [weak self] state in
                if case let .failed(error) = state {
                    Task { await self?.fail(with: error) }
                }
            }

            listener.start(queue: .global())
        }

        return code
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    func cancel() {
        continuation?.resume(throwing: CancellationError())
        continuation = nil
        stop()
    }

    // MARK: Private

    private var listener: NWListener?
    private var continuation: CheckedContinuation<String, Error>?

    private func handleConnection(_ connection: NWConnection, expectedState: String?) {
        connection.start(queue: .global())
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            Task { await self?.processRequest(data: data, connection: connection, expectedState: expectedState) }
        }
    }

    private func processRequest(data: Data?, connection: NWConnection, expectedState: String?) {
        guard let data, let request = String(data: data, encoding: .utf8) else {
            sendResponse(connection: connection, status: "400 Bad Request", body: "Bad request.")
            return
        }

        guard let firstLine = request.split(separator: "\r\n").first,
              let path = firstLine.split(separator: " ").dropFirst().first,
              path.hasPrefix("/auth/callback")
        else {
            sendResponse(connection: connection, status: "404 Not Found", body: "Not found.")
            return
        }

        guard let url = URL(string: "http://localhost\(path)"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            sendResponse(connection: connection, status: "400 Bad Request", body: "Bad request.")
            return
        }

        let code = components.queryItems?.first { $0.name == "code" }?.value
        let state = components.queryItems?.first { $0.name == "state" }?.value

        if let expectedState, let state, state != expectedState {
            sendResponse(connection: connection, status: "400 Bad Request", body: "State mismatch.")
            return
        }

        guard let code, !code.isEmpty else {
            sendResponse(connection: connection, status: "400 Bad Request", body: "Missing authorization code.")
            return
        }

        sendResponse(connection: connection, status: "200 OK", body: "Authentication complete. You can close this window.")

        #if canImport(AppKit)
        Task { @MainActor in
            NSApp.activate()
        }
        #endif

        continuation?.resume(returning: code)
        continuation = nil
        stop()
    }

    private func sendResponse(connection: NWConnection, status: String, body: String) {
        let html = "<html><body style=\"font-family:system-ui;text-align:center;padding:60px\"><p>\(body)</p></body></html>"
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n\(html)"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func fail(with error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
        stop()
    }
}
