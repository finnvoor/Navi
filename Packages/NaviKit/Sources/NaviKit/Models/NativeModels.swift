import Foundation

// MARK: - JSONValue

public enum JSONValue: Codable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    // MARK: Lifecycle

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value.")
        }
    }

    public init(any value: Any) throws {
        switch value {
        case is NSNull:
            self = .null
        case let value as String:
            self = .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else {
                self = .number(value.doubleValue)
            }
        case let value as [String: Any]:
            self = try .object(value.mapValues(JSONValue.init(any:)))
        case let value as [Any]:
            self = try .array(value.map(JSONValue.init(any:)))
        default:
            throw JSONValueError.unsupportedType(String(describing: type(of: value)))
        }
    }

    // MARK: Public

    public var anyValue: Any {
        switch self {
        case let .string(value):
            value
        case let .number(value):
            value
        case let .bool(value):
            value
        case let .object(value):
            value.mapValues(\.anyValue)
        case let .array(value):
            value.map(\.anyValue)
        case .null:
            NSNull()
        }
    }

    public var stringValue: String? {
        guard case let .string(value) = self else {
            return nil
        }

        return value
    }

    public var boolValue: Bool? {
        guard case let .bool(value) = self else {
            return nil
        }

        return value
    }

    public var intValue: Int? {
        guard case let .number(value) = self else {
            return nil
        }

        return Int(value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

// MARK: - NaviProvider

public enum NaviProvider: String, Codable, Sendable, CaseIterable, Identifiable {
    case codex
    case anthropic

    // MARK: Public

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .anthropic: "Claude"
        case .codex: "Codex"
        }
    }

    public var defaultModelID: String {
        switch self {
        case .anthropic: "claude-sonnet-4-5"
        case .codex: "gpt-5.4-mini"
        }
    }

    // MARK: Internal

    var oauthProviderID: String { rawValue }
}

// MARK: - AssistantServiceSnapshot

public struct AssistantServiceSnapshot: Codable, Sendable {
    // MARK: Lifecycle

    public init(provider: NaviProvider, modelID: String, isAuthenticated: Bool) {
        self.provider = provider
        self.modelID = modelID
        self.isAuthenticated = isAuthenticated
    }

    // MARK: Public

    public var provider: NaviProvider
    public var modelID: String
    public var isAuthenticated: Bool
}

// MARK: - NativeConversationMessage

public struct NativeConversationMessage: Codable, Sendable {
    // MARK: Lifecycle

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }

    // MARK: Public

    public var role: String
    public var content: String
}

// MARK: - BrowserInteractiveElement

public struct BrowserInteractiveElement: Codable, Sendable {
    // MARK: Lifecycle

    public init(id: String, kind: String, text: String, hint: String?, href: String?, value: String?, isEditable: Bool) {
        self.id = id
        self.kind = kind
        self.text = text
        self.hint = hint
        self.href = href
        self.value = value
        self.isEditable = isEditable
    }

    // MARK: Public

    public var id: String
    public var kind: String
    public var text: String
    public var hint: String?
    public var href: String?
    public var value: String?
    public var isEditable: Bool
}

// MARK: - BrowserPageSnapshot

public struct BrowserPageSnapshot: Codable, Sendable {
    // MARK: Lifecycle

    public init(url: String, title: String, selectedText: String?, visibleText: String, interactionSummary: String, interactives: [BrowserInteractiveElement]) {
        self.url = url
        self.title = title
        self.selectedText = selectedText
        self.visibleText = visibleText
        self.interactionSummary = interactionSummary
        self.interactives = interactives
    }

    // MARK: Public

    public var url: String
    public var title: String
    public var selectedText: String?
    public var visibleText: String
    public var interactionSummary: String
    public var interactives: [BrowserInteractiveElement]
}

// MARK: - BrowserToolResult

public struct BrowserToolResult: Codable, Sendable {
    // MARK: Lifecycle

    public init(ok: Bool, summary: String?, error: String?, snapshot: BrowserPageSnapshot?) {
        self.ok = ok
        self.summary = summary
        self.error = error
        self.snapshot = snapshot
    }

    // MARK: Public

    public var ok: Bool
    public var summary: String?
    public var error: String?
    public var snapshot: BrowserPageSnapshot?
}

// MARK: - NativePendingTool

public struct NativePendingTool: Codable, Sendable {
    // MARK: Lifecycle

    public init(callID: String, name: String, input: [String: JSONValue]) {
        self.callID = callID
        self.name = name
        self.input = input
    }

    // MARK: Public

    public var callID: String
    public var name: String
    public var input: [String: JSONValue]
}

// MARK: - NativeRunSnapshot

public struct NativeRunSnapshot: Codable, Sendable {
    public var runID: String
    public var isComplete: Bool
    public var statusText: String
    public var contentParts: [NativeContentPart]
    public var error: String?
    public var pendingTool: NativePendingTool?
    public var transcriptPath: String

    public var partialAnswer: String? {
        for part in contentParts.reversed() {
            if part.type == "text" { return part.text }
        }
        return nil
    }

    public var finalAnswer: String? { partialAnswer }
}

// MARK: - NativeContentPart

public struct NativeContentPart: Codable, Sendable {
    public var type: String
    public var text: String?
    public var id: String?
    public var name: String?
    public var status: String?
    public var result: String?
    public var isError: Bool?
}

// MARK: - AuthBridgeState

public struct AuthBridgeState: Codable, Sendable {
    // MARK: Lifecycle

    public init(
        isAuthenticated: Bool,
        isWorking: Bool,
        statusMessage: String,
        errorMessage: String?,
        codePrompt: String?,
        authorizationURL: String?
    ) {
        self.isAuthenticated = isAuthenticated
        self.isWorking = isWorking
        self.statusMessage = statusMessage
        self.errorMessage = errorMessage
        self.codePrompt = codePrompt
        self.authorizationURL = authorizationURL
    }

    // MARK: Public

    public var isAuthenticated: Bool
    public var isWorking: Bool
    public var statusMessage: String
    public var errorMessage: String?
    public var codePrompt: String?
    public var authorizationURL: String?
}

// MARK: - JSONValueError

private enum JSONValueError: LocalizedError {
    case unsupportedType(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .unsupportedType(name):
            "Unsupported JSON value type: \(name)"
        }
    }
}
