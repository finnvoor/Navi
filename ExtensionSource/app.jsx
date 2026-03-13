import React, { useEffect, useMemo, useState } from "react";
import { AssistantRuntimeProvider, useLocalRuntime } from "@assistant-ui/react";
import { Thread } from "./components/assistant-ui/thread.jsx";
import { Button } from "./components/ui/button.jsx";
import { TooltipIconButton } from "./components/assistant-ui/tooltip-icon-button.jsx";
import { TooltipProvider } from "./components/ui/tooltip.jsx";
import { Sparkles, PlusBubble } from "./components/icons.jsx";

export function PopupApp() {
    const [readyState, setReadyState] = useState({
        status: "loading",
        error: "",
        tabId: null,
        pageTitle: "Connecting to Safari…",
        pageURL: "",
        initialState: null
    });

    useEffect(() => {
        let didCancel = false;

        void (async () => {
            try {
                const [{ id: tabId, title, url } = {}] = await browser.tabs.query({
                    active: true,
                    currentWindow: true
                });

                if (!tabId) {
                    throw new Error("No active tab was found.");
                }

                const response = await browser.runtime.sendMessage({
                    type: "app:init",
                    tabId
                });

                if (!response?.ok) {
                    throw new Error(response?.error ?? "Unable to load Navi.");
                }

                if (!didCancel) {
                    setReadyState({
                        status: "ready",
                        error: "",
                        tabId,
                        pageTitle: String(title || hostnameFromURL(url) || "Current tab"),
                        pageURL: String(url || ""),
                        initialState: response.state
                    });
                }
            } catch (error) {
                if (!didCancel) {
                    setReadyState({
                        status: "error",
                        error: error.message,
                        tabId: null,
                        pageTitle: "Unavailable",
                        pageURL: "",
                        initialState: null
                    });
                }
            }
        })();

        return () => {
            didCancel = true;
        };
    }, []);

    return (
        <main className="flex h-full min-h-0 flex-col overflow-hidden bg-background text-foreground">
            {readyState.status === "loading" ? (
                <StateCard title="Loading Navi" body="Connecting the popup to the current tab and native bridge." />
            ) : null}

            {readyState.status === "error" ? (
                <StateCard tone="error" title="Navi is unavailable" body={readyState.error} />
            ) : null}

            {readyState.status === "ready" ? (
                <ChatWorkspace
                    initialState={readyState.initialState}
                    pageTitle={readyState.pageTitle}
                    pageURL={readyState.pageURL}
                    tabId={readyState.tabId}
                />
            ) : null}
        </main>
    );
}

export function SidebarApp({ tabId: propTabId, pageTitle: propTitle, pageURL: propURL }) {
    const [readyState, setReadyState] = useState({
        status: "loading",
        error: "",
        tabId: null,
        pageTitle: "Connecting…",
        pageURL: "",
        initialState: null
    });

    useEffect(() => {
        let didCancel = false;

        void (async () => {
            try {
                const tabId = propTabId;
                if (!tabId) {
                    throw new Error("No tab ID was provided.");
                }

                const response = await browser.runtime.sendMessage({
                    type: "app:init",
                    tabId
                });

                if (!response?.ok) {
                    throw new Error(response?.error ?? "Unable to load Navi.");
                }

                if (!didCancel) {
                    setReadyState({
                        status: "ready",
                        error: "",
                        tabId,
                        pageTitle: String(propTitle || hostnameFromURL(propURL) || "Current tab"),
                        pageURL: String(propURL || ""),
                        initialState: response.state
                    });
                }
            } catch (error) {
                if (!didCancel) {
                    setReadyState({
                        status: "error",
                        error: error.message,
                        tabId: null,
                        pageTitle: "Unavailable",
                        pageURL: "",
                        initialState: null
                    });
                }
            }
        })();

        return () => {
            didCancel = true;
        };
    }, [propTabId, propTitle, propURL]);

    return (
        <main className="flex h-full min-h-0 flex-col overflow-hidden bg-background text-foreground">
            {readyState.status === "loading" ? (
                <StateCard title="Loading Navi" body="Connecting to the current tab." />
            ) : null}

            {readyState.status === "error" ? (
                <StateCard tone="error" title="Navi is unavailable" body={readyState.error} />
            ) : null}

            {readyState.status === "ready" ? (
                <ChatWorkspace
                    initialState={readyState.initialState}
                    pageTitle={readyState.pageTitle}
                    pageURL={readyState.pageURL}
                    tabId={readyState.tabId}
                />
            ) : null}
        </main>
    );
}

function ChatWorkspace({ initialState, pageTitle, pageURL, tabId }) {
    const [extensionState, setExtensionState] = useState(initialState);
    const [threadSeed, setThreadSeed] = useState(0);
    const pageHost = hostnameFromURL(pageURL);

    useEffect(() => {
        const handleRuntimeMessage = (message) => {
            if (message?.type !== "assistant:state" || message.tabId !== tabId) {
                return;
            }

            setExtensionState(message.state);
        };

        browser.runtime.onMessage.addListener(handleRuntimeMessage);
        return () => {
            browser.runtime.onMessage.removeListener(handleRuntimeMessage);
        };
    }, [tabId]);

    const suggestions = useMemo(() => {
        const label = pageTitle || pageHost || "this page";
        return [
            { prompt: `Summarize ${label}` },
            { prompt: `Explain the important details on ${label}` },
            { prompt: `What actions can I take on ${label}?` },
            { prompt: `Extract the key facts from ${label}` }
        ];
    }, [pageHost, pageTitle]);

    const serviceOK = Boolean(extensionState?.service?.ok);
    const statusBanner = buildStatusBanner(extensionState);

    const handleNewThread = async () => {
        const response = await browser.runtime.sendMessage({
            type: "assistant:newThread",
            tabId
        });

        if (!response?.ok) {
            throw new Error(response?.error ?? "Unable to start a new thread.");
        }

        setExtensionState(response.state);
        setThreadSeed((value) => value + 1);
    };

    return (
        <TooltipProvider>
            <section className="flex h-full min-h-0 flex-col overflow-hidden">
                <header className="border-b border-border/70 bg-background/95 px-4 pb-3 pt-3 backdrop-blur">
                    <div className="flex items-start justify-between gap-3">
                        <div className="min-w-0">
                            <div className="flex items-center gap-2">
                                <div className="flex size-8 shrink-0 items-center justify-center rounded-full border border-border bg-card text-primary shadow-sm">
                                    <Sparkles className="size-4" />
                                </div>
                                <div className="min-w-0">
                                    <h1 className="truncate text-[15px] font-semibold leading-none tracking-[-0.02em]">
                                        Navi
                                    </h1>
                                    <p className="mt-1 truncate text-xs text-muted-foreground">{pageTitle}</p>
                                </div>
                            </div>
                        </div>

                        <div className="flex shrink-0 items-center gap-1">
                            {extensionState?.updateAvailable ? (
                                <button
                                    onClick={() => {
                                        browser.runtime
                                            .sendNativeMessage("com.finnvoorhees.Navi", { action: "checkForUpdates" })
                                            .catch(() => {});
                                    }}
                                    className="rounded-full border border-blue-300/60 bg-blue-50 px-2.5 py-1 text-[11px] font-medium text-blue-900 transition-colors hover:bg-blue-100"
                                >
                                    Update available
                                </button>
                            ) : null}
                            <TooltipIconButton
                                onClick={() => {
                                    void handleNewThread().catch((error) => {
                                        setExtensionState((current) => ({
                                            ...current,
                                            error: error.message
                                        }));
                                    });
                                }}
                                className="size-8"
                                tooltip="New Thread"
                                side="bottom"
                            >
                                <PlusBubble className="size-[18px]" />
                            </TooltipIconButton>
                        </div>
                    </div>

                    {statusBanner ? (
                        <div
                            className={`mt-3 rounded-2xl border px-3 py-2 text-[12px] leading-5 ${statusBanner.className}`}
                        >
                            {statusBanner.text}
                        </div>
                    ) : null}
                </header>

                <div className="min-h-0 flex-1 overflow-hidden">
                    {serviceOK ? (
                        <ChatRuntimePanel
                            key={`thread-${tabId}-${threadSeed}`}
                            initialState={extensionState}
                            pageTitle={pageTitle}
                            suggestions={suggestions}
                            tabId={tabId}
                        />
                    ) : (
                        <StateCard
                            body={
                                extensionState?.service?.message ??
                                "Open the Navi app and sign in before using the extension."
                            }
                            title="Sign in required"
                        />
                    )}
                </div>
            </section>
        </TooltipProvider>
    );
}

function ChatRuntimePanel({ initialState, pageTitle, suggestions, tabId }) {
    const chatModel = useMemo(() => createNaviChatModel(tabId), [tabId]);
    const suggestionAdapter = useMemo(
        () => ({
            async generate() {
                return suggestions;
            }
        }),
        [suggestions]
    );

    const runtime = useLocalRuntime(chatModel, {
        initialMessages: convertInitialMessages(initialState),
        adapters: {
            suggestion: suggestionAdapter
        }
    });

    // If we mounted while a run is in progress (reconnection after navigation),
    // trigger startRun so the chat model attaches to the existing background run.
    useEffect(() => {
        if (initialState?.isRunning) {
            const lastMessage = initialState.messages?.at(-1);
            const parentId = lastMessage
                ? `seed-${initialState.messages.indexOf(lastMessage)}-${lastMessage.role}`
                : null;
            runtime.thread.startRun({ parentId });
        }
    }, []); // eslint-disable-line react-hooks/exhaustive-deps

    return (
        <AssistantRuntimeProvider runtime={runtime}>
            <Thread
                welcomeSubtitle={`Ask Navi to read ${pageTitle || "the current page"}, explain it, or drive the tab for you.`}
                welcomeTitle="What should Navi do?"
            />
        </AssistantRuntimeProvider>
    );
}

function StateCard({ title, body, tone = "default" }) {
    return (
        <section className="flex min-h-0 flex-1 items-center justify-center px-5 py-6">
            <div
                className={`w-full max-w-sm rounded-[28px] border bg-card/90 p-5 shadow-sm ${tone === "error" ? "border-destructive/25 text-destructive" : "border-border text-foreground"}`}
            >
                <h2 className="text-sm font-semibold">{title}</h2>
                <p
                    className={`mt-2 text-sm leading-6 ${tone === "error" ? "text-destructive/90" : "text-muted-foreground"}`}
                >
                    {body}
                </p>
            </div>
        </section>
    );
}

function buildStatusBanner(extensionState) {
    if (extensionState?.service?.ok === false) {
        return {
            className: "border-yellow-300/40 bg-yellow-50 text-yellow-900",
            text: extensionState.service.message
        };
    }

    return null;
}

function createNaviChatModel(tabId) {
    return {
        async *run({ abortSignal, messages }) {
            const stateStream = createStateStream(tabId);
            let cancelled = false;

            const handleAbort = () => {
                cancelled = true;
                void browser.runtime.sendMessage({ type: "assistant:stop", tabId }).catch(() => {});
            };

            abortSignal.addEventListener("abort", handleAbort, { once: true });

            try {
                // Check if there's already a run in progress (reconnection after navigation)
                const currentState = await browser.runtime.sendMessage({ type: "app:init", tabId });

                if (currentState?.ok && currentState.state?.isRunning) {
                    stateStream.push(currentState.state);
                    const content = mapContentParts(currentState.state.contentParts);
                    if (content.length > 0) {
                        yield { content };
                    }
                    yield { status: { type: "running" } };
                } else {
                    const request = buildRunRequest(messages);
                    if (!request) {
                        throw new Error("Navi could not find a user message to send.");
                    }

                    const response = await browser.runtime.sendMessage({
                        type: "assistant:run",
                        tabId,
                        prompt: request.prompt,
                        conversation: request.conversation
                    });

                    if (!response?.ok) {
                        throw new Error(response?.error ?? "Navi could not start the run.");
                    }

                    stateStream.push(response.state);
                    yield { status: { type: "running" } };
                }

                while (true) {
                    const state = await stateStream.next();
                    if (!state) break;

                    if (state.error) {
                        throw new Error(state.error);
                    }

                    const content = mapContentParts(state.contentParts);

                    if (!state.isRunning) {
                        if (content.length > 0) {
                            yield { content };
                        }
                        yield {
                            status: cancelled
                                ? { type: "incomplete", reason: "cancelled" }
                                : { type: "complete", reason: "stop" }
                        };
                        return;
                    }

                    if (content.length > 0) {
                        yield { content };
                    }
                }

                yield {
                    status: cancelled
                        ? { type: "incomplete", reason: "cancelled" }
                        : {
                              type: "incomplete",
                              reason: "other",
                              error: "The Navi run ended unexpectedly."
                          }
                };
            } finally {
                abortSignal.removeEventListener("abort", handleAbort);
                stateStream.close();
            }
        }
    };
}

function createStateStream(tabId) {
    const queue = [];
    let resolver = null;
    let closed = false;

    const handleMessage = (message) => {
        if (closed || message?.type !== "assistant:state" || message.tabId !== tabId) {
            return;
        }

        push(message.state);
    };

    browser.runtime.onMessage.addListener(handleMessage);

    function push(state) {
        if (closed) {
            return;
        }

        if (resolver) {
            const currentResolver = resolver;
            resolver = null;
            currentResolver(state);
            return;
        }

        queue.push(state);
    }

    async function next() {
        if (queue.length > 0) {
            return queue.shift();
        }

        if (closed) {
            return null;
        }

        return new Promise((resolve) => {
            resolver = resolve;
        });
    }

    function close() {
        closed = true;
        browser.runtime.onMessage.removeListener(handleMessage);
        if (resolver) {
            resolver(null);
            resolver = null;
        }
    }

    return {
        push,
        next,
        close
    };
}

function mapContentParts(parts) {
    if (!parts || !Array.isArray(parts)) return [];
    return parts
        .map((part) => {
            switch (part.type) {
                case "reasoning":
                    return { type: "reasoning", text: part.text ?? "" };
                case "tool-call":
                    return {
                        type: "tool-call",
                        toolCallId: part.id ?? "",
                        toolName: part.name ?? "",
                        ...(part.status === "complete"
                            ? {
                                  result: part.isError ? { error: part.result } : { summary: part.result },
                                  argsText: ""
                              }
                            : { argsText: "" })
                    };
                case "text":
                    return { type: "text", text: part.text ?? "" };
                default:
                    return null;
            }
        })
        .filter(Boolean);
}

function convertInitialMessages(state) {
    const msgs = (state?.messages ?? [])
        .filter((message) => message?.role === "user" || message?.role === "assistant")
        .map((message, index) => ({
            id: `seed-${index}-${message.role}`,
            role: message.role,
            content: String(message.content ?? "")
        }))
        .filter((message) => message.content.trim().length > 0);

    // If the last message is from the assistant and we have contentParts,
    // replace it with the rich content (reasoning + tool calls + text)
    const parts = state?.contentParts;
    if (parts?.length > 0 && msgs.length > 0 && msgs[msgs.length - 1].role === "assistant") {
        const richContent = mapContentParts(parts);
        if (richContent.length > 0) {
            msgs[msgs.length - 1] = {
                ...msgs[msgs.length - 1],
                content: richContent
            };
        }
    }

    return msgs;
}

function buildRunRequest(messages) {
    const conversation = messages
        .filter((message) => message?.role === "user" || message?.role === "assistant")
        .map((message) => ({
            role: message.role,
            content: flattenMessageText(message)
        }))
        .filter((message) => message.content.length > 0);

    const promptIndex = findLastUserIndex(conversation);
    if (promptIndex < 0) {
        return null;
    }

    return {
        prompt: conversation[promptIndex].content,
        conversation: conversation.slice(0, promptIndex)
    };
}

function findLastUserIndex(messages) {
    for (let index = messages.length - 1; index >= 0; index -= 1) {
        if (messages[index]?.role === "user") {
            return index;
        }
    }

    return -1;
}

function flattenMessageText(message) {
    if (!message) {
        return "";
    }

    if (typeof message.content === "string") {
        return message.content.trim();
    }

    if (!Array.isArray(message.content)) {
        return "";
    }

    return message.content
        .map((part) => {
            if (part?.type === "text" || part?.type === "reasoning") {
                return String(part.text ?? "");
            }

            if (part?.type === "tool-call") {
                return "";
            }

            return "";
        })
        .join("\n")
        .trim();
}

function hostnameFromURL(url) {
    if (!url) {
        return "";
    }

    try {
        return new URL(url).hostname.replace(/^www\./, "");
    } catch {
        return "";
    }
}
