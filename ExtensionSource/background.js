import { cancelRun, createRun, fetchRun, loadServiceState, submitToolResult } from "./lib/native-bridge.js";
import { getPageSnapshot, performPageAction } from "./lib/page-bridge.js";

const POLL_INTERVAL_MS = 400;
const SIDEBAR_WIDTH = 420;
const APPCAST_URL = "https://raw.githubusercontent.com/finnvoor/Navi/main/appcast.xml";

const tabState = new Map();
const sidebarTabs = new Set();

let cachedUpdateAvailable = false;

const IS_IPHONE = /iPhone|iPod/.test(navigator.userAgent);

if (IS_IPHONE) {
    browser.action.setPopup({ popup: "popup.html" });
}

browser.action.onClicked.addListener(async (tab) => {
    if (tab?.id) {
        await injectSidebar(tab.id);
    }
});

browser.commands.onCommand.addListener(async (command) => {
    if (command === "toggle-sidebar") {
        const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
        if (tab?.id) {
            await injectSidebar(tab.id);
        }
    }
});

browser.tabs.onRemoved.addListener((tabId) => {
    sidebarTabs.delete(tabId);
    tabState.delete(tabId);
});

browser.tabs.onUpdated.addListener(async (tabId, changeInfo) => {
    if (changeInfo.status === "complete" && sidebarTabs.has(tabId)) {
        try {
            await openSidebar(tabId, { animate: false });
        } catch {}
    }
});

browser.runtime.onMessage.addListener((message, sender) => {
    if (message?.type === "sidebar:close") {
        const tabId = message.tabId || sender.tab?.id;
        if (tabId) {
            closeSidebar(tabId).catch(() => {});
        }
        return;
    }

    switch (message?.type) {
        case "app:init":
            return initializeApp(message.tabId);
        case "assistant:newThread":
            return startNewThread(message.tabId);
        case "assistant:run":
            return runPrompt(message.tabId, message.prompt, message.conversation);
        case "assistant:stop":
            return stopRun(message.tabId);
        default:
            return undefined;
    }
});

async function initializeApp(tabId) {
    if (!tabId) {
        return { ok: false, error: "No active tab is available." };
    }

    const state = ensureState(tabId);
    await refreshServiceState(state);
    checkForAppUpdate();
    return { ok: true, state: snapshotState(state) };
}

async function startNewThread(tabId) {
    if (!tabId) {
        return { ok: false, error: "No active tab is available." };
    }

    const state = ensureState(tabId);
    if (state.isRunning) {
        return { ok: false, error: "Wait for Navi to finish before starting a new thread." };
    }

    state.runID = null;
    state.statusText = "";
    state.contentParts = [];
    state.error = null;
    state.pendingTool = null;
    state.messages = [];
    state.recentActions = [];
    state.toolCallsInFlight.clear();
    broadcastState(tabId);

    return { ok: true, state: snapshotState(state) };
}

async function runPrompt(tabId, prompt, conversation = []) {
    const resolvedTabId = tabId ?? (await getActiveTabID());
    if (!resolvedTabId) {
        return { ok: false, error: "No active tab is available." };
    }

    const state = ensureState(resolvedTabId);
    if (state.isRunning) {
        return { ok: false, error: "Navi is already working." };
    }

    await refreshServiceState(state);
    if (!state.serviceState.isAuthenticated) {
        broadcastState(resolvedTabId);
        return { ok: false, error: "Open the Navi app and sign in before starting Navi." };
    }

    const promptText = String(prompt ?? "").trim();
    if (!promptText) {
        return { ok: false, error: "Navi needs a prompt." };
    }

    const seededConversation = sanitizeConversation(conversation);
    state.messages = [...seededConversation, { role: "user", content: promptText }];
    state.recentActions = [];
    state.pendingTool = null;
    state.contentParts = [];
    state.error = null;
    state.statusText = "Starting Navi…";
    state.isRunning = true;
    state.toolCallsInFlight.clear();
    broadcastState(resolvedTabId);

    void runAssistantLoop(resolvedTabId, promptText, seededConversation);
    return { ok: true, state: snapshotState(state) };
}

async function stopRun(tabId) {
    if (!tabId) {
        return { ok: false, error: "No active tab is available." };
    }

    const state = ensureState(tabId);
    if (!state.isRunning || !state.runID) {
        return { ok: true, state: snapshotState(state) };
    }

    state.statusText = "Stopping…";
    broadcastState(tabId);

    try {
        const response = await cancelRun(state.runID);
        const runState = response.run;
        applyRunSnapshot(state, runState);
        if (state.partialAnswer) {
            upsertAssistantMessage(state, state.partialAnswer);
        }
        if (!runState.isComplete) {
            state.isRunning = false;
            state.runID = null;
            state.statusText = "";
        }
        broadcastState(tabId);
        return { ok: true, state: snapshotState(state) };
    } catch (error) {
        return { ok: false, error: error.message };
    }
}

async function runAssistantLoop(tabId, prompt, conversation) {
    const state = ensureState(tabId);

    try {
        const response = await createRun(prompt, conversation);
        applyRunSnapshot(state, response.run);
        state.service = { ok: true, message: "Connected." };
        broadcastState(tabId);

        while (state.isRunning && state.runID) {
            const nextResponse = await fetchRun(state.runID);
            const runState = nextResponse.run;
            applyRunSnapshot(state, runState);

            if (runState.pendingTool && !state.toolCallsInFlight.has(runState.pendingTool.callID)) {
                state.toolCallsInFlight.add(runState.pendingTool.callID);
                void handleToolCall(tabId, state, runState.pendingTool);
            }

            if (runState.error) {
                throw new Error(runState.error);
            }

            if (runState.isComplete) {
                if (state.partialAnswer) {
                    upsertAssistantMessage(state, state.partialAnswer);
                }
                state.isRunning = false;
                state.runID = null;
                state.statusText = "";
                state.pendingTool = null;
                broadcastState(tabId);
                return;
            }

            broadcastState(tabId);
            await delay(POLL_INTERVAL_MS);
        }
    } catch (error) {
        state.error = error.message;
        upsertAssistantMessage(state, `I hit an error: ${error.message}`);
    } finally {
        state.isRunning = false;
        state.runID = null;
        state.pendingTool = null;
        state.statusText = "";
        state.toolCallsInFlight.clear();
        broadcastState(tabId);
    }
}

async function handleToolCall(tabId, state, pendingTool) {
    try {
        let result;

        switch (pendingTool.name) {
            case "read_page":
                {
                    const snapshot = await getPageSnapshot(tabId);
                    result = {
                        ok: true,
                        snapshot,
                        summary: `Read ${snapshot.title || "the current page"}.`
                    };
                }
                break;
            case "click":
                result = await performPageAction(tabId, {
                    kind: "click",
                    targetID: pendingTool.input.targetID
                });
                break;
            case "type":
                result = await performPageAction(tabId, {
                    kind: "type",
                    targetID: pendingTool.input.targetID,
                    text: pendingTool.input.text,
                    submit: Boolean(pendingTool.input.submit)
                });
                break;
            case "scroll":
                result = await performPageAction(tabId, {
                    kind: "scroll",
                    targetID: pendingTool.input.targetID
                });
                break;
            case "navigate":
                result = await performPageAction(tabId, {
                    kind: "navigate",
                    url: pendingTool.input.url
                });
                break;
            case "wait":
                result = await performPageAction(tabId, {
                    kind: "wait",
                    durationMs: pendingTool.input.durationMs
                });
                break;
            default:
                result = { ok: false, error: `Unsupported tool: ${pendingTool.name}` };
                break;
        }

        state.recentActions.push({
            callID: pendingTool.callID,
            name: pendingTool.name,
            input: pendingTool.input,
            summary: result.summary || "Completed.",
            error: result.error || null
        });
        state.recentActions = state.recentActions.slice(-20);

        await submitToolResult(state.runID, pendingTool.callID, result);
    } catch (error) {
        state.recentActions.push({
            callID: pendingTool.callID,
            name: pendingTool.name,
            input: pendingTool.input,
            summary: null,
            error: error.message
        });
        state.recentActions = state.recentActions.slice(-20);

        await submitToolResult(state.runID, pendingTool.callID, {
            ok: false,
            error: error.message
        }).catch(() => {});
    } finally {
        state.toolCallsInFlight.delete(pendingTool.callID);
        broadcastState(tabId);
    }
}

async function refreshServiceState(state) {
    const serviceState = await loadServiceState();
    state.serviceState = serviceState;
    state.service = {
        ok: true,
        message: serviceState.isAuthenticated ? "Connected." : "Open the Navi app and sign in first."
    };
}

function applyRunSnapshot(state, runState) {
    state.isRunning = !runState.isComplete;
    state.runID = runState.isComplete ? null : runState.runID;
    state.statusText = runState.statusText || "";
    state.error = runState.error || null;
    state.contentParts = runState.contentParts || [];
    state.pendingTool = runState.pendingTool ?? null;
    state.partialAnswer = extractTextFromParts(runState.contentParts);
}

function extractTextFromParts(parts) {
    if (!parts) return "";
    for (let i = parts.length - 1; i >= 0; i--) {
        if (parts[i].type === "text" && parts[i].text) return parts[i].text;
    }
    return "";
}

function sanitizeConversation(conversation) {
    return (conversation ?? [])
        .filter((message) => message && (message.role === "user" || message.role === "assistant"))
        .map((message) => ({
            role: message.role,
            content: String(message.content ?? "").trim()
        }))
        .filter((message) => message.content.length > 0);
}

function upsertAssistantMessage(state, content) {
    const text = String(content ?? "").trim();
    if (!text) return;

    const lastMessage = state.messages.at(-1);
    if (lastMessage?.role === "assistant") {
        lastMessage.content = text;
        return;
    }

    state.messages.push({ role: "assistant", content: text });
}

async function getActiveTabID() {
    const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
    return tab?.id ?? null;
}

function ensureState(tabId) {
    if (!tabState.has(tabId)) {
        tabState.set(tabId, {
            isRunning: false,
            runID: null,
            statusText: "",
            contentParts: [],
            partialAnswer: "",
            error: null,
            pendingTool: null,
            messages: [],
            recentActions: [],
            service: { ok: true, message: "Loading Navi settings…" },
            serviceState: { isAuthenticated: false },
            toolCallsInFlight: new Set()
        });
    }

    return tabState.get(tabId);
}

function snapshotState(state) {
    return {
        isRunning: state.isRunning,
        runID: state.runID,
        statusText: state.statusText,
        contentParts: state.contentParts,
        error: state.error,
        pendingTool: state.pendingTool,
        messages: state.messages,
        recentActions: state.recentActions,
        service: state.service,
        serviceState: state.serviceState,
        updateAvailable: cachedUpdateAvailable
    };
}

function checkForAppUpdate() {
    const currentVersion = browser.runtime.getManifest().version;

    fetch(APPCAST_URL)
        .then((r) => r.text())
        .then((xml) => {
            const match = xml.match(/sparkle:shortVersionString="([^"]+)"/);
            if (!match) return;
            const latest = match[1];
            cachedUpdateAvailable = compareVersions(latest, currentVersion) > 0;
        })
        .catch(() => {});
}

function compareVersions(a, b) {
    const pa = a.split(".").map(Number);
    const pb = b.split(".").map(Number);
    for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
        const diff = (pa[i] || 0) - (pb[i] || 0);
        if (diff !== 0) return diff;
    }
    return 0;
}

function broadcastState(tabId) {
    const message = { type: "assistant:state", tabId, state: snapshotState(ensureState(tabId)) };
    browser.runtime.sendMessage(message).catch(() => {});
}

async function injectSidebar(tabId) {
    try {
        if (sidebarTabs.has(tabId)) {
            await closeSidebar(tabId);
        } else {
            await openSidebar(tabId);
        }
    } catch {}
}

async function openSidebar(tabId, { animate = true } = {}) {
    sidebarTabs.add(tabId);

    let shortcut = null;
    try {
        const commands = await browser.commands.getAll();
        shortcut = commands.find((c) => c.name === "toggle-sidebar")?.shortcut || null;
    } catch {}

    await browser.scripting.executeScript({
        target: { tabId },
        func: (id, width, sc, anim) => {
            window.__naviTabId = id;
            window.__naviSidebarWidth = width;
            window.__naviShortcut = sc;
            window.__naviAnimate = anim;
        },
        args: [tabId, SIDEBAR_WIDTH, shortcut, animate]
    });
    await browser.scripting.executeScript({
        target: { tabId },
        files: ["sidebar-inject.js"]
    });
}

async function closeSidebar(tabId) {
    sidebarTabs.delete(tabId);

    await browser.scripting.executeScript({
        target: { tabId },
        func: () => {
            const el = document.getElementById("navi-sidebar-container");
            if (!el) return;
            el.style.transition = "transform 0.3s cubic-bezier(0.4, 0, 0.2, 1)";
            el.style.transform = "translateX(100%)";
            setTimeout(() => el.remove(), 400);
        }
    });
}

function delay(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}
