import Foundation

// MARK: - CodexProvider

struct CodexProvider: LLMProvider {
    var apiKey: String
    var accountID: String
    var baseURL: String = "https://chatgpt.com/backend-api"

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

private extension CodexProvider {
    func performStream(request: LLMRequest, continuation: AsyncThrowingStream<LLMEvent, Error>.Continuation) async throws {
        let httpRequest = try buildHTTPRequest(from: request)
        let (bytes, response) = try await URLSession.shared.bytes(for: httpRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CodexError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            var body = ""
            for try await line in bytes.lines {
                body += line
            }
            throw CodexError.apiError(status: httpResponse.statusCode, body: body)
        }

        var outputItems: [OutputItemState] = []
        var inputTokens = 0
        var outputTokens = 0

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let json = String(line.dropFirst(6))
            guard json != "[DONE]",
                  let data = json.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String
            else { continue }

            switch type {
            case "response.output_item.added":
                if let item = event["item"] as? [String: Any] {
                    let itemType = item["type"] as? String ?? ""
                    let itemID = item["id"] as? String
                    let callID = item["call_id"] as? String
                    let name = item["name"] as? String
                    outputItems.append(OutputItemState(type: itemType, id: itemID, callID: callID, name: name))
                }

            case "response.output_text.delta":
                if let delta = event["delta"] as? String {
                    continuation.yield(.textDelta(delta))
                }

            case "response.reasoning_summary_text.delta",
                 "response.reasoning.delta":
                if let delta = event["delta"] as? String {
                    continuation.yield(.thinkingDelta(delta))
                }

            case "response.function_call_arguments.delta":
                if let delta = event["delta"] as? String,
                   let itemID = event["item_id"] as? String,
                   let idx = outputItems.firstIndex(where: { $0.id == itemID }) {
                    outputItems[idx].argumentsBuffer += delta
                }

            case "response.output_item.done":
                if let item = event["item"] as? [String: Any] {
                    let itemType = item["type"] as? String ?? ""
                    if itemType == "function_call" {
                        let id = item["call_id"] as? String ?? item["id"] as? String ?? ""
                        let name = item["name"] as? String ?? ""
                        let argsString = item["arguments"] as? String ?? ""
                        let args = parseJSON(argsString)
                        continuation.yield(.toolCall(id: id, name: name, arguments: args))
                    } else if itemType == "reasoning" {
                        continuation.yield(.thinkingComplete(signature: nil))
                    }
                }

            case "response.completed", "response.done":
                if let resp = event["response"] as? [String: Any] {
                    if let usage = resp["usage"] as? [String: Any] {
                        inputTokens = usage["input_tokens"] as? Int ?? 0
                        outputTokens = usage["output_tokens"] as? Int ?? 0
                        continuation.yield(.usage(input: inputTokens, output: outputTokens))
                    }

                    let status = resp["status"] as? String ?? "completed"
                    let stopReason: LLMStopReason = switch status {
                    case "incomplete": .maxTokens
                    default:
                        outputItems.contains(where: { $0.type == "function_call" }) ? .toolUse : .endTurn
                    }
                    continuation.yield(.done(stopReason: stopReason))
                    continuation.finish()
                    return
                }

            case "response.failed":
                let msg = (event["response"] as? [String: Any])?["error"] as? [String: Any]
                let message = msg?["message"] as? String ?? "Codex response failed"
                throw CodexError.apiError(status: 0, body: message)

            case "error":
                let message = event["message"] as? String ?? "Unknown error"
                throw CodexError.apiError(status: 0, body: message)

            default:
                break
            }
        }

        continuation.finish()
    }
}

// MARK: - Request Building

private extension CodexProvider {
    func buildHTTPRequest(from request: LLMRequest) throws -> URLRequest {
        let url = URL(string: "\(baseURL)/codex/responses")!
        var httpRequest = URLRequest(url: url)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        httpRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        httpRequest.setValue(accountID, forHTTPHeaderField: "chatgpt-account-id")
        httpRequest.setValue("navi", forHTTPHeaderField: "originator")
        httpRequest.setValue("responses=experimental", forHTTPHeaderField: "OpenAI-Beta")

        #if os(macOS)
        httpRequest.setValue("navi (macOS)", forHTTPHeaderField: "User-Agent")
        #else
        httpRequest.setValue("navi (iOS)", forHTTPHeaderField: "User-Agent")
        #endif

        let body = buildRequestBody(from: request)
        httpRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return httpRequest
    }

    func buildRequestBody(from request: LLMRequest) -> [String: Any] {
        var body: [String: Any] = [
            "model": request.model,
            "store": false,
            "stream": true,
            "tool_choice": "auto",
            "parallel_tool_calls": false,
            "text": ["verbosity": "medium"],
            "include": ["reasoning.encrypted_content"],
        ]

        if !request.systemPrompt.isEmpty {
            body["instructions"] = request.systemPrompt
        }

        if let budget = request.thinkingBudget, budget > 0 {
            body["reasoning"] = ["effort": "medium", "summary": "auto"]
        }

        body["input"] = buildInputItems(from: request.messages)

        if !request.tools.isEmpty {
            body["tools"] = request.tools.map { tool -> [String: Any] in
                var def: [String: Any] = [
                    "type": "function",
                    "name": tool.name,
                    "description": tool.description,
                ]
                if let params = tool.parameters.asJSONObject() {
                    def["parameters"] = params
                }
                return def
            }
        }

        return body
    }

    func buildInputItems(from messages: [LLMMessage]) -> [Any] {
        var items: [Any] = []
        var msgIndex = 0

        for message in messages {
            switch message.role {
            case .user:
                var content: [[String: Any]] = []
                for block in message.content {
                    switch block {
                    case let .text(text):
                        content.append(["type": "input_text", "text": text])
                    case let .toolResult(toolCallId, resultContent, _):
                        // Tool results are top-level items
                        items.append([
                            "type": "function_call_output",
                            "call_id": toolCallId,
                            "output": resultContent,
                        ] as [String: Any])
                    default:
                        break
                    }
                }
                if !content.isEmpty {
                    items.append(["type": "message", "role": "user", "content": content] as [String: Any])
                }

            case .assistant:
                // Each assistant block is a separate top-level item
                for block in message.content {
                    switch block {
                    case let .text(text):
                        items.append([
                            "type": "message",
                            "role": "assistant",
                            "content": [["type": "output_text", "text": text, "annotations": []] as [String: Any]],
                            "status": "completed",
                            "id": "msg_\(msgIndex)",
                        ] as [String: Any])
                    case let .toolCall(id, name, arguments):
                        let argsData = try? JSONSerialization.data(withJSONObject: arguments.mapValues { $0.asJSONObject() ?? NSNull() })
                        let argsString = argsData.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                        items.append([
                            "type": "function_call",
                            "call_id": id,
                            "name": name,
                            "arguments": argsString,
                        ] as [String: Any])
                    case .thinking:
                        break
                    default:
                        break
                    }
                }
            }
            msgIndex += 1
        }

        return items
    }
}

// MARK: - Helpers

private func parseJSON(_ string: String) -> [String: JSONValue] {
    guard let data = string.data(using: .utf8),
          let obj = try? JSONDecoder().decode([String: JSONValue].self, from: data)
    else { return [:] }
    return obj
}

private extension JSONValue {
    func asJSONObject() -> Any? {
        switch self {
        case let .string(v): v
        case let .number(v): v
        case let .bool(v): v
        case .null: NSNull()
        case let .array(v): v.map { $0.asJSONObject() ?? NSNull() }
        case let .object(v): v.mapValues { $0.asJSONObject() ?? NSNull() }
        }
    }
}

// MARK: - OutputItemState

private struct OutputItemState {
    var type: String
    var id: String?
    var callID: String?
    var name: String?
    var argumentsBuffer: String = ""
}

// MARK: - CodexError

enum CodexError: LocalizedError {
    case invalidResponse
    case apiError(status: Int, body: String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Invalid response from Codex API."
        case let .apiError(status, body):
            status > 0 ? "Codex API error (\(status)): \(body.prefix(500))" : "Codex error: \(body.prefix(500))"
        }
    }
}
