(() => {
    const ID = "navi-sidebar-container";
    const WIDTH = window.__naviSidebarWidth || 420;
    const ANIMATE = window.__naviAnimate !== false;

    const existing = document.getElementById(ID);
    if (existing) {
        return;
    }

    const tabId = window.__naviTabId;
    if (!tabId) {
        return;
    }

    const host = document.createElement("div");
    host.id = ID;
    Object.assign(host.style, {
        position: "fixed",
        top: "0",
        right: "0",
        width: WIDTH + "px",
        height: "100vh",
        zIndex: "2147483647",
        transform: ANIMATE ? "translateX(100%)" : "translateX(0)",
        transition: ANIMATE ? "transform 0.3s cubic-bezier(0.4, 0, 0.2, 1)" : "none",
        margin: "0",
        padding: "0",
        border: "none",
        boxShadow: "-4px 0 24px rgba(0, 0, 0, 0.12)"
    });

    function syncHostFrame() {
        const viewport = window.visualViewport;
        const viewportTop = viewport?.offsetTop ?? 0;
        const viewportHeight = viewport?.height ?? window.innerHeight;

        host.style.top = `${viewportTop}px`;
        host.style.height = `${viewportHeight}px`;
    }

    const iframe = document.createElement("iframe");
    Object.assign(iframe.style, {
        width: "100%",
        height: "100%",
        border: "none",
        margin: "0",
        padding: "0",
        colorScheme: "light"
    });
    iframe.src = browser.runtime.getURL("sidebar.html");

    iframe.allow = "focus-without-user-activation";

    iframe.addEventListener("load", () => {
        try {
            iframe.contentWindow.postMessage(
                {
                    __navi: true,
                    init: true,
                    tabId,
                    shortcut: window.__naviShortcut || null,
                    pageTitle: document.title,
                    pageURL: location.href
                },
                "*"
            );
            iframe.contentWindow.focus();
        } catch {}
    });

    host.appendChild(iframe);
    syncHostFrame();

    const syncHostFrameBound = () => syncHostFrame();
    window.addEventListener("resize", syncHostFrameBound);
    window.visualViewport?.addEventListener("resize", syncHostFrameBound);
    window.visualViewport?.addEventListener("scroll", syncHostFrameBound);

    for (const evt of ["keydown", "keyup", "keypress"]) {
        host.addEventListener(evt, (e) => e.stopPropagation(), true);
    }

    document.body.appendChild(host);
    iframe.focus();

    if (ANIMATE) {
        requestAnimationFrame(() => {
            requestAnimationFrame(() => {
                host.style.transform = "translateX(0)";
            });
        });
    }
})();
