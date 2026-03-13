import Foundation

// MARK: - NativeBridgeRequest

enum NativeBridgeRequest: Sendable {
    case loadServiceState
    case startRun(prompt: String, conversation: [NativeConversationMessage])
    case getRun(runID: String)
    case cancelRun(runID: String)
    case submitToolResult(runID: String, callID: String, result: BrowserToolResult)
    case checkForUpdates

    // MARK: Lifecycle

    init(message: [String: Any]) throws {
        let action = try NativeBridgeCodec.requiredString("action", in: message)

        switch action {
        case "loadServiceState", "loadSettings":
            self = .loadServiceState
        case "checkForUpdates":
            self = .checkForUpdates
        case "startRun":
            self = try .startRun(
                prompt: NativeBridgeCodec.requiredString("prompt", in: message),
                conversation: NativeBridgeCodec.decodeIfPresent([NativeConversationMessage].self, forKey: "conversation", in: message) ?? []
            )
        case "getRun":
            self = try .getRun(runID: NativeBridgeCodec.requiredString("runID", in: message))
        case "cancelRun":
            self = try .cancelRun(runID: NativeBridgeCodec.requiredString("runID", in: message))
        case "submitToolResult":
            self = try .submitToolResult(
                runID: NativeBridgeCodec.requiredString("runID", in: message),
                callID: NativeBridgeCodec.requiredString("callID", in: message),
                result: NativeBridgeCodec.decode(BrowserToolResult.self, forKey: "result", in: message)
            )
        default:
            throw NativeBridgeError.invalidRequest("Unsupported action: \(action)")
        }
    }
}

// MARK: - NativeBridgeResponse

enum NativeBridgeResponse: Sendable {
    case serviceState(AssistantServiceSnapshot)
    case run(NativeRunSnapshot)
    case ok

    // MARK: Internal

    func dictionary() throws -> [String: Any] {
        switch self {
        case let .serviceState(snapshot):
            try NativeBridgeCodec.successPayload(["serviceState": NativeBridgeCodec.dictionary(from: snapshot)])
        case let .run(run):
            try NativeBridgeCodec.successPayload(["run": NativeBridgeCodec.dictionary(from: run)])
        case .ok:
            try NativeBridgeCodec.successPayload()
        }
    }
}

// MARK: - NativeBridgeError

enum NativeBridgeError: LocalizedError {
    case invalidRequest(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .invalidRequest(message):
            message
        }
    }
}

// MARK: - NativeBridgeCodec

enum NativeBridgeCodec {
    static func successPayload(_ fields: [String: Any] = [:]) throws -> [String: Any] {
        var payload = fields
        payload["ok"] = true
        return payload
    }

    static func requiredString(_ key: String, in dictionary: [String: Any]) throws -> String {
        guard let value = dictionary[key] as? String else {
            throw NativeBridgeError.invalidRequest("Missing string field '\(key)'.")
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NativeBridgeError.invalidRequest("Field '\(key)' was empty.")
        }

        return trimmed
    }

    static func decode<T: Decodable>(_ type: T.Type, forKey key: String, in dictionary: [String: Any]) throws -> T {
        guard let value = dictionary[key] else {
            throw NativeBridgeError.invalidRequest("Missing '\(key)' payload.")
        }

        let data = try JSONSerialization.data(withJSONObject: value)
        return try JSONDecoder().decode(type, from: data)
    }

    static func decodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: String, in dictionary: [String: Any]) throws -> T? {
        guard let value = dictionary[key] else {
            return nil
        }

        let data = try JSONSerialization.data(withJSONObject: value)
        return try JSONDecoder().decode(type, from: data)
    }

    static func dictionary(from value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: data)

        guard let dictionary = object as? [String: Any] else {
            throw NativeBridgeError.invalidRequest("Native response could not be serialized.")
        }

        return dictionary
    }
}
