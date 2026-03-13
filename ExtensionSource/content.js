const NAVI_ATTRIBUTE = "data-navi-id";
let nextElementID = 1;

browser.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    switch (message?.type) {
        case "navi:getSnapshot":
            sendResponse(buildSnapshot());
            return true;
        case "navi:performAction":
            sendResponse(executeAction(message.action));
            return true;
        default:
            return undefined;
    }
});

function buildSnapshot() {
    const interactives = collectInteractiveElements();
    const visibleText = normalizeText(document.body?.innerText || "").slice(0, 12000);
    const selectedText = normalizeText(window.getSelection?.().toString() || "");

    const snapshot = {
        url: location.href,
        title: document.title || location.href,
        selectedText: selectedText || null,
        visibleText: visibleText || "No readable text found on this page.",
        interactionSummary: `ScrollY=${Math.round(window.scrollY)} viewport=${window.innerWidth}x${window.innerHeight}`,
        interactives
    };

    // Round-trip through JSON to strip non-serializable values
    try {
        return JSON.parse(JSON.stringify(snapshot));
    } catch {
        return {
            url: location.href,
            title: document.title || location.href,
            selectedText: null,
            visibleText: "Navi could not serialize the page snapshot.",
            interactionSummary: "",
            interactives: []
        };
    }
}

function collectInteractiveElements() {
    const selector = [
        "a[href]",
        "button",
        "input",
        "textarea",
        "select",
        "[role='button']",
        "[contenteditable='true']",
        "[tabindex]"
    ].join(",");

    return Array.from(document.querySelectorAll(selector))
        .filter((element) => isVisible(element))
        .slice(0, 80)
        .map((element) => ({
            id: ensureElementID(element),
            kind: describeElementKind(element),
            text: elementText(element),
            hint: elementHint(element),
            href: (typeof element.href === "string" ? element.href : element.getAttribute("href")) || null,
            value: safeElementValue(element),
            isEditable: isEditable(element)
        }));
}

function executeAction(action) {
    switch (action?.kind) {
        case "click":
            return clickElement(action.targetID);
        case "type":
            return typeIntoElement(action.targetID, action.text || "", Boolean(action.submit));
        case "scroll":
            return scrollToElement(action.targetID);
        default:
            return { ok: false, error: `Unsupported action: ${action?.kind}` };
    }
}

function clickElement(targetID) {
    const element = findElement(targetID);
    if (!element) {
        return { ok: false, error: `Element ${targetID} was not found.` };
    }

    focusElement(element);
    element.scrollIntoView({ block: "center", inline: "center", behavior: "smooth" });
    flashElement(element);
    element.click();

    return { ok: true, summary: `Clicked ${targetID}` };
}

function typeIntoElement(targetID, text, submit) {
    const element = findElement(targetID);
    if (!element) {
        return { ok: false, error: `Element ${targetID} was not found.` };
    }

    if (!isEditable(element)) {
        return { ok: false, error: `Element ${targetID} is not editable.` };
    }

    focusElement(element);
    element.scrollIntoView({ block: "center", inline: "center", behavior: "smooth" });
    flashElement(element);

    if (element.isContentEditable) {
        element.textContent = text;
        element.dispatchEvent(new InputEvent("input", { bubbles: true, data: text, inputType: "insertText" }));
    } else {
        setElementValue(element, text);
        element.dispatchEvent(new Event("input", { bubbles: true }));
        element.dispatchEvent(new Event("change", { bubbles: true }));
    }

    if (submit) {
        if (element.form?.requestSubmit) {
            element.form.requestSubmit();
        } else {
            element.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", code: "Enter", bubbles: true }));
            element.dispatchEvent(new KeyboardEvent("keyup", { key: "Enter", code: "Enter", bubbles: true }));
        }
    }

    return { ok: true, summary: `Typed into ${targetID}` };
}

function scrollToElement(targetID) {
    const element = findElement(targetID);
    if (!element) {
        return { ok: false, error: `Element ${targetID} was not found.` };
    }

    element.scrollIntoView({ block: "center", inline: "nearest", behavior: "smooth" });
    flashElement(element);
    return { ok: true, summary: `Scrolled to ${targetID}` };
}

function findElement(id) {
    if (!id) {
        return null;
    }

    return document.querySelector(`[${NAVI_ATTRIBUTE}="${escapeAttribute(id)}"]`);
}

function ensureElementID(element) {
    if (!element.hasAttribute(NAVI_ATTRIBUTE)) {
        element.setAttribute(NAVI_ATTRIBUTE, `navi-${nextElementID}`);
        nextElementID += 1;
    }

    return element.getAttribute(NAVI_ATTRIBUTE);
}

function isVisible(element) {
    const style = window.getComputedStyle(element);
    const rect = element.getBoundingClientRect();
    return style.visibility !== "hidden" && style.display !== "none" && rect.width > 0 && rect.height > 0;
}

function isEditable(element) {
    return element.isContentEditable || ["INPUT", "TEXTAREA"].includes(element.tagName);
}

function describeElementKind(element) {
    if (element.isContentEditable) {
        return "contenteditable";
    }

    if (element.tagName === "INPUT") {
        return `input:${element.type || "text"}`;
    }

    return element.tagName.toLowerCase();
}

function elementText(element) {
    const parts = [
        normalizeText(element.innerText || ""),
        safeElementValue(element) || "",
        normalizeText(element.getAttribute("aria-label") || "")
    ].filter(Boolean);

    return parts.join(" | ").slice(0, 160) || element.tagName.toLowerCase();
}

function elementHint(element) {
    const hints = [
        normalizeText(element.placeholder || ""),
        normalizeText(element.getAttribute("title") || ""),
        normalizeText(findAssociatedLabel(element) || "")
    ].filter(Boolean);

    return hints.join(" | ").slice(0, 160) || null;
}

function findAssociatedLabel(element) {
    if (element.id) {
        const label = document.querySelector(`label[for="${escapeAttribute(element.id)}"]`);
        if (label) {
            return label.innerText;
        }
    }

    return element.closest("label")?.innerText || "";
}

function focusElement(element) {
    element.focus({ preventScroll: true });
}

function flashElement(element) {
    const previousOutline = element.style.outline;
    const previousOffset = element.style.outlineOffset;
    element.style.outline = "2px solid #b8511f";
    element.style.outlineOffset = "2px";
    setTimeout(() => {
        element.style.outline = previousOutline;
        element.style.outlineOffset = previousOffset;
    }, 1200);
}

function setElementValue(element, value) {
    const prototype = element.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    const descriptor = Object.getOwnPropertyDescriptor(prototype, "value");

    if (descriptor?.set) {
        descriptor.set.call(element, value);
    } else {
        element.value = value;
    }
}

function safeElementValue(element) {
    if (!("value" in element)) {
        return null;
    }

    if (element.tagName === "INPUT" && element.type === "password") {
        return null;
    }

    return normalizeText(element.value || "") || null;
}

function normalizeText(value) {
    return String(value || "")
        .replace(/\s+/g, " ")
        .trim();
}

function escapeAttribute(value) {
    return String(value).replace(/"/g, '\\"');
}
