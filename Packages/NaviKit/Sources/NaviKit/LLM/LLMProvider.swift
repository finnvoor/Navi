import Foundation

// MARK: - LLMProvider

protocol LLMProvider: Sendable {
    func stream(request: LLMRequest) -> AsyncThrowingStream<LLMEvent, Error>
}

// MARK: - LLMRequest

struct LLMRequest: Sendable {
    var model: String
    var systemPrompt: String
    var messages: [LLMMessage]
    var tools: [LLMToolDefinition]
    var maxTokens: Int
    var thinkingBudget: Int?
}

// MARK: - LLMMessage

struct LLMMessage: Sendable {
    enum Role: String, Sendable {
        case user
        case assistant
    }

    var role: Role
    var content: [LLMContentBlock]
}

// MARK: - LLMContentBlock

enum LLMContentBlock: Sendable {
    case text(String)
    case thinking(text: String, signature: String?)
    case toolCall(id: String, name: String, arguments: [String: JSONValue])
    case toolResult(toolCallId: String, content: String, isError: Bool)
}

// MARK: - LLMToolDefinition

struct LLMToolDefinition: Sendable {
    var name: String
    var description: String
    var parameters: JSONValue
}

// MARK: - LLMEvent

enum LLMEvent: Sendable {
    case thinkingDelta(String)
    case thinkingComplete(signature: String?)
    case textDelta(String)
    case toolCall(id: String, name: String, arguments: [String: JSONValue])
    case done(stopReason: LLMStopReason)
    case usage(input: Int, output: Int)
}

// MARK: - LLMStopReason

enum LLMStopReason: String, Sendable {
    case endTurn = "end_turn"
    case toolUse = "tool_use"
    case maxTokens = "max_tokens"
}
