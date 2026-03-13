import Foundation
import SafariServices

// MARK: - SafariExtensionMessageBridge

public enum SafariExtensionMessageBridge {
    public static func handle(context: NSExtensionContext) async -> [String: Any] {
        do {
            let message = try requestPayload(from: context)
            return await NativeMessageRouter.handle(message: message)
        } catch {
            return [
                "ok": false,
                "error": displayMessage(for: error),
            ]
        }
    }

    public static func responseItem(for payload: [String: Any]) -> NSExtensionItem {
        let response = NSExtensionItem()

        if #available(iOS 15.0, macOS 11.0, *) {
            response.userInfo = [SFExtensionMessageKey: payload]
        } else {
            response.userInfo = ["message": payload]
        }

        return response
    }
}

private extension SafariExtensionMessageBridge {
    static func requestPayload(from context: NSExtensionContext) throws -> [String: Any] {
        guard
            let item = context.inputItems.first as? NSExtensionItem,
            let userInfo = item.userInfo,
            let message = userInfo[SFExtensionMessageKey] as? [String: Any]
        else {
            throw NativeBridgeError.invalidRequest("Safari did not deliver a native message payload.")
        }

        return message
    }

    static func displayMessage(for error: Error) -> String {
        if let bridgeError = error as? NativeBridgeError {
            return bridgeError.localizedDescription
        }

        return error.localizedDescription
    }
}
