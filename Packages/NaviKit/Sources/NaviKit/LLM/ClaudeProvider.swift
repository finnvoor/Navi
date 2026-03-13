import Foundation

// MARK: - ClaudeProvider

struct ClaudeProvider: LLMProvider {
    var apiKey: String
    var baseURL: String = "https://api.anthropic.com"

    func stream(request: LLMRequest) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await performStream(request: request, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Streaming

private extension ClaudeProvider {
    func performStream(request: LLMRequest, continuation: AsyncThrowingStream<LLMEvent, Error>.Continuation) async throws {
        let httpRequest = try buildHTTPRequest(from: request)
        let (bytes, response) = try await URLSession.shared.bytes(for: httpRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            var body = ""
            for try await line in bytes.lines {
                body += line
            }
            throw ClaudeError.apiError(status: httpResponse.statusCode, body: body)
        }

        var contentBlocks: [ContentBlockState] = []

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let json = String(line.dropFirst(6))
            guard json != "[DONE]",
                  let data = json.data(using: .utf8),
                  let event = try? JSONDecoder().decode(SSEEvent.self, from: data)
            else { continue }

            switch event.type {
            case "content_block_start":
                guard let block = event.content_block else { break }
                contentBlocks.append(ContentBlockState(type: block.type, id: block.id, name: block.name))

            case "content_block_delta":
                guard let delta = event.delta else { break }
                switch delta.type {
                case "text_delta":
                    if let text = delta.text {
                        continuation.yield(.textDelta(text))
                    }
                case "thinking_delta":
                    if let thinking = delta.thinking {
                        continuation.yield(.thinkingDelta(thinking))
                    }
                case "input_json_delta":
                    if let index = event.index, index < contentBlocks.count {
                        contentBlocks[index].jsonBuffer += (delta.partial_json ?? "")
                    }
                case "signature_delta":
                    if let index = event.index, index < contentBlocks.count {
                        contentBlocks[index].signature = (contentBlocks[index].signature ?? "") + (delta.signature ?? "")
                    }
                default:
                    break
                }

            case "content_block_stop":
                guard let index = event.index, index < contentBlocks.count else { break }
                let block = contentBlocks[index]
                if block.type == "tool_use", let id = block.id, let name = block.name {
                    let args = parseJSON(block.jsonBuffer)
                    continuation.yield(.toolCall(id: id, name: name, arguments: args))
                } else if block.type == "thinking" {
                    continuation.yield(.thinkingComplete(signature: block.signature))
                }

            case "message_delta":
                if let delta = event.delta, let reason = delta.stop_reason {
                    if let usage = event.usage {
                        continuation.yield(.usage(input: usage.input_tokens ?? 0, output: usage.output_tokens ?? 0))
                    }
                    let stopReason = LLMStopReason(rawValue: reason) ?? .endTurn
                    continuation.yield(.done(stopReason: stopReason))
                    continuation.finish()
                    return
                }

            case "message_start":
                if let usage = event.message?.usage {
                    continuation.yield(.usage(input: usage.input_tokens ?? 0, output: usage.output_tokens ?? 0))
                }

            default:
                break
            }
        }

        continuation.finish()
    }
}

// MARK: - Request Building

private extension ClaudeProvider {
    func buildHTTPRequest(from request: LLMRequest) throws -> URLRequest {
        let url = URL(string: "\(baseURL)/v1/messages")!
        var httpRequest = URLRequest(url: url)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let isOAuth = apiKey.hasPrefix("sk-ant-oat")

        if isOAuth {
            httpRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            httpRequest.setValue("claude-cli/2.1.75 (external, cli)", forHTTPHeaderField: "user-agent")
            httpRequest.setValue("cli", forHTTPHeaderField: "x-app")
        } else {
            httpRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }

        var betaFeatures: [String] = []
        if isOAuth {
            betaFeatures.append("claude-code-20250219")
            betaFeatures.append("oauth-2025-04-20")
        }
        betaFeatures.append("fine-grained-tool-streaming-2025-05-14")
        betaFeatures.append("interleaved-thinking-2025-05-14")
        httpRequest.setValue(betaFeatures.joined(separator: ","), forHTTPHeaderField: "anthropic-beta")

        let body = buildRequestBody(from: request)
        httpRequest.httpBody = try JSONEncoder().encode(body)
        return httpRequest
    }

    func buildRequestBody(from request: LLMRequest) -> ClaudeMessagesRequest {
        let messages = request.messages.map { msg in
            ClaudeMessage(
                role: msg.role.rawValue,
                content: msg.content.map { block -> ClaudeContentBlock in
                    switch block {
                    case let .text(text):
                        return .text(text)
                    case let .thinking(text, signature):
                        // Thinking blocks require a valid signature to send back.
                        // If missing (e.g. aborted stream), fall back to plain text.
                        if let sig = signature, !sig.isEmpty {
                            return .thinking(text: text, signature: sig)
                        } else {
                            return .text(text)
                        }
                    case let .toolCall(id, name, arguments):
                        return .toolUse(id: id, name: name, input: arguments)
                    case let .toolResult(toolCallId, content, isError):
                        return .toolResult(tool_use_id: toolCallId, content: content, is_error: isError ? true : nil)
                    }
                }
            )
        }

        let tools = request.tools.map { tool in
            ClaudeTool(name: tool.name, description: tool.description, input_schema: tool.parameters)
        }

        var thinking: ClaudeThinking?
        if let budget = request.thinkingBudget, budget > 0 {
            thinking = ClaudeThinking(type: "enabled", budget_tokens: budget)
        }

        var system: [ClaudeSystemBlock] = []
        if apiKey.hasPrefix("sk-ant-oat") {
            system.append(ClaudeSystemBlock(type: "text", text: "You are Claude Code, Anthropic's official CLI for Claude."))
        }
        if !request.systemPrompt.isEmpty {
            system.append(ClaudeSystemBlock(type: "text", text: request.systemPrompt))
        }

        return ClaudeMessagesRequest(
            model: request.model,
            max_tokens: request.maxTokens,
            system: system.isEmpty ? nil : system,
            messages: messages,
            tools: tools.isEmpty ? nil : tools,
            stream: true,
            thinking: thinking
        )
    }
}

// MARK: - JSON Parsing

private func parseJSON(_ string: String) -> [String: JSONValue] {
    guard let data = string.data(using: .utf8),
          let obj = try? JSONDecoder().decode([String: JSONValue].self, from: data)
    else { return [:] }
    return obj
}

// MARK: - ClaudeMessagesRequest

private struct ClaudeMessagesRequest: Encodable {
    var model: String
    var max_tokens: Int
    var system: [ClaudeSystemBlock]?
    var messages: [ClaudeMessage]
    var tools: [ClaudeTool]?
    var stream: Bool
    var thinking: ClaudeThinking?
}

// MARK: - ClaudeSystemBlock

private struct ClaudeSystemBlock: Encodable {
    var type: String
    var text: String
}

// MARK: - ClaudeMessage

private struct ClaudeMessage: Encodable {
    var role: String
    var content: [ClaudeContentBlock]
}

// MARK: - ClaudeContentBlock

private enum ClaudeContentBlock: Encodable {
    case text(String)
    case thinking(text: String, signature: String?)
    case toolUse(id: String, name: String, input: [String: JSONValue])
    case toolResult(tool_use_id: String, content: String, is_error: Bool?)

    // MARK: Internal

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .thinking(text, signature):
            try container.encode("thinking", forKey: .type)
            try container.encode(text, forKey: .thinking)
            try container.encodeIfPresent(signature, forKey: .signature)
        case let .toolUse(id, name, input):
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
        case let .toolResult(toolUseId, content, isError):
            try container.encode("tool_result", forKey: .type)
            try container.encode(toolUseId, forKey: .tool_use_id)
            try container.encode(content, forKey: .content)
            try container.encodeIfPresent(isError, forKey: .is_error)
        }
    }

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
        case type, text, thinking, signature, id, name, input, tool_use_id, content, is_error
    }
}

// MARK: - ClaudeTool

private struct ClaudeTool: Encodable {
    var name: String
    var description: String
    var input_schema: JSONValue
}

// MARK: - ClaudeThinking

private struct ClaudeThinking: Encodable {
    var type: String
    var budget_tokens: Int
}

// MARK: - SSEEvent

private struct SSEEvent: Decodable {
    var type: String
    var index: Int?
    var content_block: SSEContentBlock?
    var delta: SSEDelta?
    var message: SSEMessage?
    var usage: SSEUsage?
}

// MARK: - SSEContentBlock

private struct SSEContentBlock: Decodable {
    var type: String
    var id: String?
    var name: String?
}

// MARK: - SSEDelta

private struct SSEDelta: Decodable {
    var type: String?
    var text: String?
    var thinking: String?
    var partial_json: String?
    var signature: String?
    var stop_reason: String?
}

// MARK: - SSEMessage

private struct SSEMessage: Decodable {
    var usage: SSEUsage?
}

// MARK: - SSEUsage

private struct SSEUsage: Decodable {
    var input_tokens: Int?
    var output_tokens: Int?
}

// MARK: - ContentBlockState

private struct ContentBlockState {
    var type: String
    var id: String?
    var name: String?
    var jsonBuffer: String = ""
    var signature: String?
}

// MARK: - ClaudeError

enum ClaudeError: LocalizedError {
    case invalidResponse
    case apiError(status: Int, body: String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Invalid response from Claude API."
        case let .apiError(status, body):
            "Claude API error (\(status)): \(body.prefix(500))"
        }
    }
}
