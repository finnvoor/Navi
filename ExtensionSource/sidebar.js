import React from "react";
import { createRoot } from "react-dom/client";
import { SidebarApp } from "./app.jsx";

syncViewportHeight();
window.addEventListener("resize", syncViewportHeight);
window.visualViewport?.addEventListener("resize", syncViewportHeight);
window.visualViewport?.addEventListener("scroll", syncViewportHeight);

// Wait for init data from the content script
window.addEventListener(
    "message",
    (e) => {
        const msg = e.data;
        if (!msg || typeof msg !== "object" || !msg.__navi || !msg.init) return;
        boot(msg);
    },
    { once: true }
);

function boot(initData) {
    const container = document.getElementById("root");
    if (!container) return;

    const { tabId, pageTitle, pageURL } = initData;

    function closeSidebar() {
        browser.runtime.sendMessage({ type: "sidebar:close", tabId }).catch(() => {});
    }

    // Mirror the toggle shortcut since browser.commands doesn't fire in iframes
    if (initData.shortcut) {
        const parts = initData.shortcut.toLowerCase().split("+");
        const key = parts.pop();
        const mods = new Set(parts);

        document.addEventListener("keydown", (e) => {
            if (
                e.key.toLowerCase() === key &&
                e.ctrlKey === (mods.has("ctrl") || mods.has("macctrl")) &&
                e.shiftKey === mods.has("shift") &&
                e.altKey === mods.has("alt") &&
                e.metaKey === mods.has("command")
            ) {
                e.preventDefault();
                closeSidebar();
            }
        });
    }

    createRoot(container).render(
        React.createElement(SidebarApp, {
            tabId,
            pageTitle: pageTitle || "Current tab",
            pageURL: pageURL || ""
        })
    );

    // Focus the composer textarea once React renders it
    const observer = new MutationObserver(() => {
        const input = container.querySelector("textarea");
        if (input) {
            observer.disconnect();
            setTimeout(() => {
                window.focus();
                input.focus();
            }, 150);
        }
    });
    observer.observe(container, { childList: true, subtree: true });
}

function syncViewportHeight() {
    const viewport = window.visualViewport;
    const viewportHeight = viewport?.height ?? window.innerHeight;

    document.documentElement.style.setProperty("--navi-viewport-height", `${viewportHeight}px`);
}
