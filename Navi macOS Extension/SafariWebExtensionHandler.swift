import Foundation
import NaviKit
import os.log
import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    // MARK: Internal

    func beginRequest(with context: NSExtensionContext) {
        Task {
            let payload = await SafariExtensionMessageBridge.handle(context: context)
            if let action = ((context.inputItems.first as? NSExtensionItem)?.userInfo?[SFExtensionMessageKey] as? [String: Any])?["action"] as? String {
                logger.debug("Received native message action: \(action, privacy: .public)")
            }

            let response = SafariExtensionMessageBridge.responseItem(for: payload)
            context.completeRequest(returningItems: [response], completionHandler: nil)
        }
    }

    // MARK: Private

    private let logger = Logger(subsystem: "com.finnvoorhees.Navi.Extension", category: "NativeMessaging")
}
