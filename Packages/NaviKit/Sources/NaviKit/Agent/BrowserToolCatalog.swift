import Foundation

// MARK: - BrowserToolExecuting

protocol BrowserToolExecuting: Sendable {
    func execute(runID: String, callID: String, toolName: String, input: [String: JSONValue]) async throws -> BrowserToolResult
}

// MARK: - BrowserToolCatalog

enum BrowserToolCatalog {
    // MARK: Internal

    static let definitions: [LLMToolDefinition] = [
        LLMToolDefinition(
            name: "read_page",
            description: "Read the current page text, metadata, and interactive elements.",
            parameters: objectSchema(properties: [:], required: [])
        ),
        LLMToolDefinition(
            name: "click",
            description: "Click a visible interactive element by its page element ID.",
            parameters: objectSchema(
                properties: [
                    "targetID": propertySchema(type: "string", description: "The element ID from read_page.")
                ],
                required: ["targetID"]
            )
        ),
        LLMToolDefinition(
            name: "type",
            description: "Type text into an editable element by its page element ID.",
            parameters: objectSchema(
                properties: [
                    "targetID": propertySchema(type: "string", description: "The element ID from read_page."),
                    "text": propertySchema(type: "string", description: "Text to type into the field."),
                    "submit": propertySchema(type: "boolean", description: "Whether to submit the field after typing.")
                ],
                required: ["targetID", "text"]
            )
        ),
        LLMToolDefinition(
            name: "scroll",
            description: "Scroll the page so a specific element is visible and centered on screen. Use this to show the user where something is on the page.",
            parameters: objectSchema(
                properties: [
                    "targetID": propertySchema(type: "string", description: "The data-navi-id of the element to scroll to.")
                ],
                required: ["targetID"]
            )
        ),
        LLMToolDefinition(
            name: "navigate",
            description: "Navigate the active tab to a new URL.",
            parameters: objectSchema(
                properties: [
                    "url": propertySchema(type: "string", description: "The absolute URL to load.")
                ],
                required: ["url"]
            )
        ),
        LLMToolDefinition(
            name: "wait",
            description: "Pause briefly so the page can settle after a navigation or action.",
            parameters: objectSchema(
                properties: [
                    "durationMs": propertySchema(type: "number", description: "How long to wait in milliseconds.")
                ],
                required: ["durationMs"]
            )
        ),
    ]

    static func describeResult(_ result: BrowserToolResult, toolName: String) -> String {
        if toolName == "read_page", let snapshot = result.snapshot {
            return describe(snapshot: snapshot)
        }
        return result.summary ?? "Completed."
    }

    // MARK: Private

    // MARK: - Schema Helpers

    private static func objectSchema(properties: [String: JSONValue], required: [String]) -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.map { .string($0) })
        ])
    }

    private static func propertySchema(type: String, description: String) -> JSONValue {
        .object([
            "type": .string(type),
            "description": .string(description)
        ])
    }

    private static func describe(snapshot: BrowserPageSnapshot) -> String {
        var lines = [
            "Page title: \(snapshot.title)",
            "URL: \(snapshot.url)",
            "View: \(snapshot.interactionSummary)",
        ]

        if let selectedText = snapshot.selectedText, !selectedText.isEmpty {
            lines.append("Selected text: \(selectedText)")
        }

        lines.append("Visible text:")
        lines.append(snapshot.visibleText)

        if !snapshot.interactives.isEmpty {
            lines.append("Interactive elements:")

            for element in snapshot.interactives {
                var parts = ["[\(element.id)] \(element.kind)", element.text]
                if let hint = element.hint, !hint.isEmpty { parts.append("hint: \(hint)") }
                if let href = element.href, !href.isEmpty { parts.append("href: \(href)") }
                if let value = element.value, !value.isEmpty { parts.append("value: \(value)") }
                if element.isEditable { parts.append("editable") }
                lines.append("- " + parts.joined(separator: " | "))
            }
        }

        return lines.joined(separator: "\n")
    }
}
