import React from "react";
import { createRoot } from "react-dom/client";
import { PopupApp } from "./app.jsx";

document.documentElement.dataset.platform = "ios";

syncViewportHeight();
window.addEventListener("resize", syncViewportHeight);
window.visualViewport?.addEventListener("resize", syncViewportHeight);
window.visualViewport?.addEventListener("scroll", syncViewportHeight);

const container = document.getElementById("root");

if (!container) {
    throw new Error("Navi popup root was not found.");
}

createRoot(container).render(React.createElement(PopupApp));

function syncViewportHeight() {
    const viewport = window.visualViewport;
    const viewportWidth = viewport?.width ?? window.innerWidth;
    const viewportHeight = viewport?.height ?? window.innerHeight;
    const offsetTop = viewport?.offsetTop ?? 0;
    const offsetLeft = viewport?.offsetLeft ?? 0;

    document.documentElement.style.setProperty("--navi-popup-width", `${viewportWidth}px`);
    document.documentElement.style.setProperty("--navi-viewport-height", `${viewportHeight}px`);
    document.documentElement.style.setProperty("--navi-viewport-offset-top", `${offsetTop}px`);
    document.documentElement.style.setProperty("--navi-viewport-offset-left", `${offsetLeft}px`);

    if (window.scrollY !== 0 || window.scrollX !== 0) {
        window.scrollTo({ top: 0, left: 0, behavior: "instant" });
    }
}
