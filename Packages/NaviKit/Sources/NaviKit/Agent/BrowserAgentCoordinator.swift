import Foundation

// MARK: - BrowserAgentCoordinator

actor BrowserAgentCoordinator {
    // MARK: Lifecycle

    init(
        serviceStore: AssistantServiceStore = AssistantServiceStore(),
        transcriptLogger: TranscriptLogger = .shared,
        sessionStore: RunStore = RunStore()
    ) {
        self.serviceStore = serviceStore
        self.transcriptLogger = transcriptLogger
        self.sessionStore = sessionStore
    }

    // MARK: Internal

    static let shared = BrowserAgentCoordinator()

    func loadServiceState() throws -> AssistantServiceSnapshot {
        try serviceStore.loadSnapshot()
    }

    func startRun(prompt: String, conversation: [NativeConversationMessage] = []) async throws -> NativeRunSnapshot {
        await sessionStore.pruneCompletedRunsIfNeeded()

        let configuration = try await serviceStore.loadConfiguration()
        let runID = "\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.lowercased())"
        let promptText = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let transcriptPath = await transcriptLogger.transcriptPath(for: runID)

        await sessionStore.createSession(
            runID: runID,
            prompt: promptText,
            modelID: configuration.modelID,
            transcriptPath: transcriptPath
        )

        await transcriptLogger.log(
            runID: runID,
            kind: "run_start",
            payload: RunStartTranscript(
                prompt: promptText,
                modelID: configuration.modelID,
                conversationLength: conversation.count
            )
        )

        let toolExecutor = BridgedBrowserToolExecutor(
            runID: runID,
            sessionStore: sessionStore,
            transcriptLogger: transcriptLogger
        )
        let provider: any LLMProvider = switch configuration.provider {
        case .codex:
            CodexProvider(apiKey: configuration.apiKey, accountID: configuration.accountID ?? "")
        case .anthropic:
            ClaudeProvider(apiKey: configuration.apiKey)
        }
        let agentSession = LLMBrowserAgentSession(
            provider: provider,
            systemPrompt: Self.systemPrompt,
            conversation: conversation,
            tools: BrowserToolCatalog.definitions,
            toolExecutor: toolExecutor,
            runID: runID,
            modelID: configuration.modelID,
            thinkingBudget: 10000
        )

        await agentSession.setEventHandler { [weak self] event in
            await self?.handleAgentEvent(event, runID: runID, session: agentSession)
        }

        let task = Task { [weak self] in
            guard let self else { return }

            await sessionStore.setStatus("Thinking…", for: runID)

            do {
                try await agentSession.start(prompt: promptText)
                let snapshot = await agentSession.snapshot()
                await finishRun(runID: runID, snapshot: snapshot)
            } catch {
                await failRun(runID: runID, error: error)
            }
        }

        try await sessionStore.attachTask(task, to: runID)
        return try await sessionStore.snapshot(for: runID)
    }

    func getRun(runID: String) async throws -> NativeRunSnapshot {
        try await sessionStore.snapshot(for: runID)
    }

    func cancelRun(runID: String) async throws -> NativeRunSnapshot {
        try await sessionStore.cancel(runID: runID)
    }

    func submitToolResult(runID: String, callID: String, result: BrowserToolResult) async throws -> NativeRunSnapshot {
        await transcriptLogger.log(
            runID: runID,
            kind: "tool_result",
            payload: ToolResultTranscript(callID: callID, result: result)
        )

        return try await sessionStore.submitToolResult(runID: runID, callID: callID, result: result)
    }

    // MARK: Private

    private let serviceStore: AssistantServiceStore
    private let transcriptLogger: TranscriptLogger
    private let sessionStore: RunStore
}

private extension BrowserAgentCoordinator {
    struct RunStartTranscript: Codable, Sendable {
        var prompt: String
        var modelID: String
        var conversationLength: Int
    }

    struct ToolRequestTranscript: Codable, Sendable {
        var callID: String
        var toolName: String
        var input: [String: JSONValue]
    }

    struct ToolResultTranscript: Codable, Sendable {
        var callID: String
        var result: BrowserToolResult
    }

    struct RunCompletionTranscript: Codable, Sendable {
        var finalAnswer: String?
        var contentParts: [NativeContentPart]?
        var error: String?
    }

    static let systemPrompt = """
    You are Navi, an AI assistant that can read and control the active Safari tab.

    Use the provided browser tools to inspect the page, click elements, type into fields, scroll, navigate, and wait.
    When a request depends on page contents or controls, call read_page before answering unless the context is already current.
    After actions that change the page, call read_page again before making claims about the new page state.
    Refer to interactive elements by the IDs returned from read_page.
    Do not take destructive or high-risk actions like purchases, account deletion, or form submission unless the user explicitly asked for that exact action.
    Keep the final answer concise and describe what you learned or changed in the browser.
    """

    func handleAgentEvent(_ event: BrowserAgentSessionEvent, runID: String, session: any BrowserAgentSession) async {
        // Sync content parts from the session to the store on every event
        let snapshot = await session.snapshot()
        await sessionStore.setContentParts(snapshot.contentParts.map(\.asNativePart), for: runID)

        switch event {
        case .thinking:
            await sessionStore.setStatus("Thinking…", for: runID)

        case let .responding(text, _):
            if !text.isEmpty {
                await sessionStore.setStatus("Responding…", for: runID)
            }

        case let .runningTool(toolName):
            await sessionStore.setStatus("Running \(toolName)…", for: runID)

        case let .error(errorMessage):
            await sessionStore.setError(errorMessage, for: runID)
        }
    }

    func finishRun(runID: String, snapshot: BrowserAgentSessionSnapshot) async {
        await sessionStore.complete(runID: runID, snapshot: snapshot)

        await transcriptLogger.log(
            runID: runID,
            kind: "run_complete",
            payload: RunCompletionTranscript(
                finalAnswer: snapshot.finalAnswer,
                contentParts: snapshot.contentParts.map(\.asNativePart),
                error: snapshot.errorMessage
            )
        )
    }

    func failRun(runID: String, error: Error) async {
        guard let session = await sessionStore.fail(runID: runID, error: error) else {
            return
        }

        let message = session.wasCancelled ? nil : error.localizedDescription
        await transcriptLogger.log(
            runID: runID,
            kind: session.wasCancelled ? "run_cancelled" : "run_failed",
            payload: RunCompletionTranscript(
                finalAnswer: session.contentParts.last(where: { $0.type == "text" })?.text,
                contentParts: session.contentParts,
                error: message
            )
        )
    }
}

// MARK: - BridgedBrowserToolExecutor

private struct BridgedBrowserToolExecutor: BrowserToolExecuting {
    // MARK: Internal

    let runID: String
    let sessionStore: RunStore
    let transcriptLogger: TranscriptLogger

    func execute(runID: String, callID: String, toolName: String, input: [String: JSONValue]) async throws -> BrowserToolResult {
        let pendingTool = NativePendingTool(callID: callID, name: toolName, input: input)

        await transcriptLogger.log(
            runID: runID,
            kind: "tool_request",
            payload: BrowserAgentCoordinator.ToolRequestTranscript(
                callID: callID,
                toolName: toolName,
                input: input
            )
        )

        let result = try await sessionStore.queueToolInvocation(
            runID: runID,
            pendingTool: pendingTool,
            statusText: toolStatusText(for: toolName, input: input)
        )

        if result.ok {
            return result
        }

        throw BrowserToolExecutionError.toolFailed(result.error ?? "Browser action failed.")
    }

    // MARK: Private

    private func toolStatusText(for name: String, input: [String: JSONValue]) -> String {
        switch name {
        case "read_page":
            "Reading the page…"
        case "click":
            "Clicking \(input["targetID"]?.stringValue ?? "element")…"
        case "type":
            "Typing into \(input["targetID"]?.stringValue ?? "field")…"
        case "scroll":
            "Scrolling to element…"
        case "navigate":
            "Navigating…"
        case "wait":
            "Waiting…"
        default:
            "Running \(name)…"
        }
    }
}

// MARK: - BrowserToolExecutionError

private enum BrowserToolExecutionError: LocalizedError {
    case toolFailed(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .toolFailed(message):
            message
        }
    }
}
