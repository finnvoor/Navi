import Foundation

// MARK: - BrowserAgentSessionEvent

enum BrowserAgentSessionEvent: Sendable {
    case thinking
    case responding(text: String, thinkingContent: String?)
    case runningTool(String)
    case error(String)
}

// MARK: - SessionContentPart

enum SessionContentPart: Sendable {
    case reasoning(String)
    case toolCall(id: String, name: String)
    case toolCallComplete(id: String, name: String, result: String, isError: Bool)
    case text(String)

    // MARK: Internal

    var isReasoning: Bool {
        if case .reasoning = self { return true }
        return false
    }

    var reasoningText: String {
        if case let .reasoning(text) = self { return text }
        return ""
    }

    var asNativePart: NativeContentPart {
        switch self {
        case let .reasoning(text):
            NativeContentPart(type: "reasoning", text: text)
        case let .toolCall(id, name):
            NativeContentPart(type: "tool-call", id: id, name: name, status: "running")
        case let .toolCallComplete(id, name, result, isError):
            NativeContentPart(type: "tool-call", id: id, name: name, status: "complete", result: result, isError: isError)
        case let .text(text):
            NativeContentPart(type: "text", text: text)
        }
    }
}

// MARK: - BrowserAgentSessionSnapshot

struct BrowserAgentSessionSnapshot: Sendable {
    var contentParts: [SessionContentPart] = []

    var errorMessage: String?

    var partialAnswer: String? {
        for part in contentParts.reversed() {
            if case let .text(text) = part { return text }
        }
        return nil
    }

    var finalAnswer: String? { partialAnswer }
}

// MARK: - BrowserAgentSession

protocol BrowserAgentSession: Sendable {
    func setEventHandler(_ handler: @escaping @Sendable (BrowserAgentSessionEvent) async -> Void) async
    func start(prompt: String) async throws
    func snapshot() async -> BrowserAgentSessionSnapshot
}
