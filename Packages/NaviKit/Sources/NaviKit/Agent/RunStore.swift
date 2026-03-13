import Foundation

// MARK: - RunStore

actor RunStore {
    // MARK: Internal

    struct Session {
        var runID: String
        var prompt: String
        var modelID: String
        var transcriptPath: String
        var statusText: String = ""
        var contentParts: [NativeContentPart] = []
        var error: String?
        var isComplete = false
        var wasCancelled = false
        var pendingTool: NativePendingTool?
        var pendingToolContinuation: CheckedContinuation<BrowserToolResult, Error>?
        var task: Task<Void, Never>?
        var updatedAt = Date()
    }

    func pruneCompletedRunsIfNeeded(maxCount: Int = 24, retentionInterval: TimeInterval = 900) {
        guard sessions.count >= maxCount else {
            return
        }

        let cutoff = Date().addingTimeInterval(-retentionInterval)
        sessions = sessions.filter { _, session in
            !session.isComplete || session.updatedAt > cutoff
        }
    }

    func createSession(runID: String, prompt: String, modelID: String, transcriptPath: String) {
        sessions[runID] = Session(
            runID: runID,
            prompt: prompt,
            modelID: modelID,
            transcriptPath: transcriptPath
        )
    }

    func attachTask(_ task: Task<Void, Never>, to runID: String) throws {
        guard var session = sessions[runID] else {
            throw RunStoreError.missingRun
        }

        session.task = task
        session.updatedAt = Date()
        sessions[runID] = session
    }

    func snapshot(for runID: String) throws -> NativeRunSnapshot {
        guard let session = sessions[runID] else {
            throw RunStoreError.missingRun
        }

        return NativeRunSnapshot(
            runID: session.runID,
            isComplete: session.isComplete,
            statusText: session.statusText,
            contentParts: session.contentParts,
            error: session.error,
            pendingTool: session.pendingTool,
            transcriptPath: session.transcriptPath
        )
    }

    func cancel(runID: String) throws -> NativeRunSnapshot {
        guard var session = sessions[runID] else {
            throw RunStoreError.missingRun
        }

        if session.isComplete {
            return try snapshot(for: runID)
        }

        session.wasCancelled = true
        session.statusText = "Stopping…"
        session.pendingTool = nil
        session.pendingToolContinuation?.resume(throwing: CancellationError())
        session.pendingToolContinuation = nil
        session.updatedAt = Date()
        session.task?.cancel()
        sessions[runID] = session

        return try snapshot(for: runID)
    }

    func submitToolResult(runID: String, callID: String, result: BrowserToolResult) throws -> NativeRunSnapshot {
        guard var session = sessions[runID] else {
            throw RunStoreError.missingRun
        }

        guard session.pendingTool?.callID == callID else {
            throw RunStoreError.mismatchedToolResult
        }

        let continuation = session.pendingToolContinuation
        session.pendingTool = nil
        session.pendingToolContinuation = nil
        session.statusText = "Thinking…"
        session.updatedAt = Date()
        sessions[runID] = session

        continuation?.resume(returning: result)
        return try snapshot(for: runID)
    }

    func setStatus(_ status: String, for runID: String) {
        guard var session = sessions[runID] else {
            return
        }

        session.statusText = status
        session.updatedAt = Date()
        sessions[runID] = session
    }

    func setContentParts(_ parts: [NativeContentPart], for runID: String) {
        guard var session = sessions[runID] else {
            return
        }

        session.contentParts = parts
        session.updatedAt = Date()
        sessions[runID] = session
    }

    func setError(_ errorMessage: String, for runID: String) {
        guard var session = sessions[runID] else {
            return
        }

        session.error = errorMessage
        session.updatedAt = Date()
        sessions[runID] = session
    }

    func complete(runID: String, snapshot: BrowserAgentSessionSnapshot) {
        guard var session = sessions[runID] else {
            return
        }

        session.contentParts = snapshot.contentParts.map(\.asNativePart)
        session.error = snapshot.errorMessage ?? session.error
        session.isComplete = true
        session.statusText = ""
        session.pendingTool = nil
        session.pendingToolContinuation = nil
        session.updatedAt = Date()
        sessions[runID] = session
    }

    func fail(runID: String, error: Error) -> Session? {
        guard var session = sessions[runID] else {
            return nil
        }

        let message = session.wasCancelled ? nil : error.localizedDescription
        session.error = message
        session.isComplete = true
        session.statusText = ""
        session.pendingTool = nil
        if !session.wasCancelled {
            session.pendingToolContinuation?.resume(throwing: error)
        }
        session.pendingToolContinuation = nil
        session.updatedAt = Date()
        sessions[runID] = session
        return session
    }

    func queueToolInvocation(
        runID: String,
        pendingTool: NativePendingTool,
        statusText: String
    ) async throws -> BrowserToolResult {
        guard var session = sessions[runID] else {
            throw RunStoreError.missingRun
        }

        if session.pendingTool != nil {
            throw RunStoreError.toolAlreadyPending
        }

        return try await withCheckedThrowingContinuation { continuation in
            session.pendingTool = pendingTool
            session.pendingToolContinuation = continuation
            session.statusText = statusText
            session.updatedAt = Date()
            sessions[runID] = session
        }
    }

    // MARK: Private

    private var sessions: [String: Session] = [:]
}

// MARK: - RunStoreError

enum RunStoreError: LocalizedError {
    case missingRun
    case mismatchedToolResult
    case toolAlreadyPending

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .missingRun:
            "That Navi run is no longer available."
        case .mismatchedToolResult:
            "Safari returned a tool result for the wrong tool call."
        case .toolAlreadyPending:
            "Navi was already waiting for a browser tool result."
        }
    }
}
