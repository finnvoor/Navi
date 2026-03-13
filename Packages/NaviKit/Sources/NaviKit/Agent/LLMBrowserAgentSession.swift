import Foundation

// MARK: - LLMBrowserAgentSession

actor LLMBrowserAgentSession: BrowserAgentSession {
    // MARK: Lifecycle

    init(
        provider: any LLMProvider,
        systemPrompt: String,
        conversation: [NativeConversationMessage],
        tools: [LLMToolDefinition],
        toolExecutor: any BrowserToolExecuting,
        runID: String,
        modelID: String,
        thinkingBudget: Int?
    ) {
        self.provider = provider
        self.systemPrompt = systemPrompt
        self.tools = tools
        self.toolExecutor = toolExecutor
        self.runID = runID
        self.modelID = modelID
        self.thinkingBudget = thinkingBudget

        messages = conversation.compactMap { msg in
            let text = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return LLMMessage(
                role: msg.role == "user" ? .user : .assistant,
                content: [.text(text)]
            )
        }
    }

    // MARK: Internal

    func setEventHandler(_ handler: @escaping @Sendable (BrowserAgentSessionEvent) async -> Void) {
        eventHandler = handler
    }

    func start(prompt: String) async throws {
        messages.append(LLMMessage(role: .user, content: [.text(prompt)]))
        await eventHandler?(.thinking)

        var turnCount = 0
        let maxTurns = 25

        while turnCount < maxTurns {
            turnCount += 1
            let request = LLMRequest(
                model: modelID,
                systemPrompt: systemPrompt,
                messages: messages,
                tools: tools,
                maxTokens: 16384,
                thinkingBudget: thinkingBudget
            )

            // Track this turn's content in arrival order
            var turnParts: [TurnPart] = []
            var thinkingSignature: String?
            var stopReason: LLMStopReason = .endTurn

            for try await event in provider.stream(request: request) {
                switch event {
                case let .thinkingDelta(delta):
                    appendOrUpdateTurnPart(&turnParts, kind: .thinking, delta: delta)
                    syncStreamingParts(turnParts)
                    await eventHandler?(.responding(
                        text: currentText(turnParts),
                        thinkingContent: currentThinking(turnParts)
                    ))

                case let .textDelta(delta):
                    appendOrUpdateTurnPart(&turnParts, kind: .text, delta: delta)
                    syncStreamingParts(turnParts)
                    await eventHandler?(.responding(
                        text: currentText(turnParts),
                        thinkingContent: currentThinking(turnParts)
                    ))

                case let .toolCall(id, name, arguments):
                    turnParts.append(.toolCall(id: id, name: name, arguments: arguments))
                    syncStreamingParts(turnParts)
                    await eventHandler?(.runningTool(name))

                case let .thinkingComplete(signature):
                    thinkingSignature = signature

                case let .done(reason):
                    stopReason = reason

                case .usage:
                    break
                }
            }

            // Commit this turn's parts
            commitTurnParts(turnParts)

            // Build the LLM conversation message
            var assistantContent: [LLMContentBlock] = []
            for part in turnParts {
                switch part {
                case let .thinking(text):
                    assistantContent.append(.thinking(text: text, signature: thinkingSignature))
                case let .text(text):
                    assistantContent.append(.text(text))
                case let .toolCall(id, name, arguments):
                    assistantContent.append(.toolCall(id: id, name: name, arguments: arguments))
                }
            }
            messages.append(LLMMessage(role: .assistant, content: assistantContent))

            if stopReason == .toolUse {
                let toolCallParts = turnParts.compactMap { part -> (id: String, name: String, arguments: [String: JSONValue])? in
                    if case let .toolCall(id, name, arguments) = part { return (id, name, arguments) }
                    return nil
                }

                var toolResults: [LLMContentBlock] = []
                for call in toolCallParts {
                    let input = call.arguments.compactMapValues { $0 }
                    do {
                        let result = try await toolExecutor.execute(
                            runID: runID, callID: call.id, toolName: call.name, input: input
                        )
                        let text = BrowserToolCatalog.describeResult(result, toolName: call.name)
                        updateToolResult(callID: call.id, result: text, isError: !result.ok)
                        toolResults.append(.toolResult(toolCallId: call.id, content: text, isError: !result.ok))
                    } catch {
                        updateToolResult(callID: call.id, result: error.localizedDescription, isError: true)
                        toolResults.append(.toolResult(toolCallId: call.id, content: error.localizedDescription, isError: true))
                    }
                }
                messages.append(LLMMessage(role: .user, content: toolResults))
                await eventHandler?(.thinking)
                continue
            }

            return
        }
    }

    func snapshot() -> BrowserAgentSessionSnapshot {
        BrowserAgentSessionSnapshot(contentParts: contentParts)
    }

    // MARK: Private

    // MARK: - Turn Part Tracking

    /// A content block from the current turn, in the order it arrived from the stream.
    private enum TurnPart {
        case thinking(String)
        case text(String)
        case toolCall(id: String, name: String, arguments: [String: JSONValue])
    }

    private enum TurnPartKind { case thinking, text }

    private let provider: any LLMProvider
    private let systemPrompt: String
    private let tools: [LLMToolDefinition]
    private let toolExecutor: any BrowserToolExecuting
    private let runID: String
    private let modelID: String
    private let thinkingBudget: Int?

    private var messages: [LLMMessage] = []
    private var eventHandler: (@Sendable (BrowserAgentSessionEvent) async -> Void)?
    private var contentParts: [SessionContentPart] = []
    private var committedCount: Int = 0

    /// Append a delta to the last part of the matching kind, or start a new part.
    private func appendOrUpdateTurnPart(_ parts: inout [TurnPart], kind: TurnPartKind, delta: String) {
        switch kind {
        case .thinking:
            if case var .thinking(existing) = parts.last {
                existing += delta
                parts[parts.count - 1] = .thinking(existing)
            } else {
                parts.append(.thinking(delta))
            }
        case .text:
            if case var .text(existing) = parts.last {
                existing += delta
                parts[parts.count - 1] = .text(existing)
            } else {
                parts.append(.text(delta))
            }
        }
    }

    /// Replace streaming parts with current turn's content (preserving order).
    private func syncStreamingParts(_ turnParts: [TurnPart]) {
        contentParts.removeSubrange(committedCount...)
        for part in turnParts {
            switch part {
            case let .thinking(text): contentParts.append(.reasoning(text))
            case let .text(text): contentParts.append(.text(text))
            case let .toolCall(id, name, _): contentParts.append(.toolCall(id: id, name: name))
            }
        }
    }

    /// Commit the current turn's parts so they persist across turns.
    private func commitTurnParts(_ turnParts: [TurnPart]) {
        syncStreamingParts(turnParts)
        committedCount = contentParts.count
    }

    private func updateToolResult(callID: String, result: String, isError: Bool) {
        if let index = contentParts.firstIndex(where: {
            if case let .toolCall(id, _) = $0 { return id == callID }
            return false
        }) {
            if case let .toolCall(id, name) = contentParts[index] {
                contentParts[index] = .toolCallComplete(id: id, name: name, result: result, isError: isError)
            }
        }
    }

    private func currentText(_ parts: [TurnPart]) -> String {
        parts.compactMap { if case let .text(t) = $0 { t } else { nil } }.joined()
    }

    private func currentThinking(_ parts: [TurnPart]) -> String {
        parts.compactMap { if case let .thinking(t) = $0 { t } else { nil } }.joined()
    }
}
