export async function getPageSnapshot(tabId) {
    const snapshot = await sendTabMessage(tabId, { type: "navi:getSnapshot" });

    if (!isPageSnapshot(snapshot)) {
        throw new Error("Navi could not read the current page. Reload the tab and try again.");
    }

    return snapshot;
}

export async function performPageAction(tabId, action) {
    if (action.kind === "navigate") {
        await browser.tabs.update(tabId, { url: action.url });
        await delay(1200);
        return { ok: true, summary: `Navigated to ${action.url}` };
    }

    if (action.kind === "wait") {
        await delay(action.durationMs ?? 1000);
        return { ok: true, summary: `Waited ${action.durationMs ?? 1000}ms` };
    }

    return sendTabMessage(tabId, { type: "navi:performAction", action });
}

async function sendTabMessage(tabId, message) {
    try {
        return await trySendTabMessage(tabId, message);
    } catch (error) {
        throw new Error(`The current page is not available to Navi: ${error.message}`);
    }
}

async function trySendTabMessage(tabId, message) {
    const initialResponse = await browser.tabs.sendMessage(tabId, message).catch(() => null);
    if (initialResponse != null) {
        return initialResponse;
    }

    await ensureContentScript(tabId);

    const retriedResponse = await browser.tabs.sendMessage(tabId, message).catch(() => null);
    if (retriedResponse == null) {
        throw new Error("The page did not return a response.");
    }

    return retriedResponse;
}

async function ensureContentScript(tabId) {
    if (browser.scripting?.executeScript) {
        await browser.scripting.executeScript({
            target: { tabId },
            files: ["content.js"]
        });
        return;
    }

    if (browser.tabs?.executeScript) {
        await browser.tabs.executeScript(tabId, {
            file: "content.js"
        });
        return;
    }

    throw new Error("Safari could not attach Navi to the current page.");
}

function isPageSnapshot(value) {
    return Boolean(
        value &&
            typeof value === "object" &&
            typeof value.url === "string" &&
            typeof value.title === "string" &&
            typeof value.visibleText === "string" &&
            typeof value.interactionSummary === "string" &&
            Array.isArray(value.interactives)
    );
}

function delay(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}
