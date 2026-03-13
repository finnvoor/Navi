import React, { memo, useCallback, useRef, useState } from "react";
import { Checkmark, ChevronDown, ExclamationTriangle, Spinner, XmarkCircle } from "../icons.jsx";
import { useScrollLock } from "@assistant-ui/react";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "../ui/collapsible.jsx";
import { cn } from "../../lib/utils.js";

const ANIMATION_DURATION = 200;

const STATUS_ICONS = {
    running: Spinner,
    complete: Checkmark,
    incomplete: XmarkCircle,
    "requires-action": ExclamationTriangle
};

function ToolFallbackRoot({
    className,
    open: controlledOpen,
    onOpenChange: controlledOnOpenChange,
    defaultOpen = false,
    children,
    ...props
}) {
    const collapsibleRef = useRef(null);
    const [uncontrolledOpen, setUncontrolledOpen] = useState(defaultOpen);
    const lockScroll = useScrollLock(collapsibleRef, ANIMATION_DURATION);
    const isControlled = controlledOpen !== undefined;
    const isOpen = isControlled ? controlledOpen : uncontrolledOpen;

    const handleOpenChange = useCallback(
        (open) => {
            if (!open) lockScroll();
            if (!isControlled) setUncontrolledOpen(open);
            controlledOnOpenChange?.(open);
        },
        [lockScroll, isControlled, controlledOnOpenChange]
    );

    return (
        <Collapsible
            ref={collapsibleRef}
            open={isOpen}
            onOpenChange={handleOpenChange}
            className={cn(
                "aui-tool-fallback-root group/tool-fallback-root w-full rounded-lg border px-3 py-3",
                className
            )}
            style={{ "--animation-duration": `${ANIMATION_DURATION}ms` }}
            {...props}
        >
            {children}
        </Collapsible>
    );
}

function ToolFallbackTrigger({ toolName, status, className, ...props }) {
    const statusType = status?.type ?? "complete";
    const isRunning = statusType === "running";
    const isCancelled = status?.type === "incomplete" && status.reason === "cancelled";
    const Icon = STATUS_ICONS[statusType];
    const label = isCancelled ? "Cancelled tool" : "Used tool";

    return (
        <CollapsibleTrigger
            className={cn(
                "aui-tool-fallback-trigger group/trigger flex w-full items-center gap-2 text-sm transition-colors",
                className
            )}
            {...props}
        >
            <Icon
                className={cn("size-4 shrink-0", isCancelled && "text-muted-foreground", isRunning && "animate-spin")}
            />
            <span
                className={cn(
                    "relative grow text-left leading-none",
                    isCancelled && "text-muted-foreground line-through"
                )}
            >
                <span>
                    {label}: <b>{toolName}</b>
                </span>
                {isRunning ? (
                    <span aria-hidden className="shimmer pointer-events-none absolute inset-0">
                        {label}: <b>{toolName}</b>
                    </span>
                ) : null}
            </span>
            <ChevronDown
                className={cn(
                    "size-4 shrink-0 transition-transform duration-(--animation-duration) ease-out",
                    "group-data-[state=closed]/trigger:-rotate-90 group-data-[state=open]/trigger:rotate-0"
                )}
            />
        </CollapsibleTrigger>
    );
}

function ToolFallbackContent({ className, children, ...props }) {
    return (
        <CollapsibleContent
            className={cn(
                "aui-tool-fallback-content relative overflow-hidden text-sm outline-none",
                "group/collapsible-content ease-out",
                "data-[state=closed]:animate-collapsible-up data-[state=open]:animate-collapsible-down",
                "data-[state=closed]:fill-mode-forwards data-[state=closed]:pointer-events-none",
                "data-[state=open]:duration-(--animation-duration) data-[state=closed]:duration-(--animation-duration)",
                className
            )}
            {...props}
        >
            <div className="mt-3 flex flex-col gap-2 border-t pt-2">{children}</div>
        </CollapsibleContent>
    );
}

function ToolFallbackArgs({ argsText, className, ...props }) {
    if (!argsText) return null;
    return (
        <div className={cn("aui-tool-fallback-args", className)} {...props}>
            <pre className="whitespace-pre-wrap">{argsText}</pre>
        </div>
    );
}

function ToolFallbackResult({ result, className, ...props }) {
    if (result === undefined) return null;
    return (
        <div className={cn("aui-tool-fallback-result border-t border-dashed pt-2", className)} {...props}>
            <p className="font-semibold">Result:</p>
            <pre className="whitespace-pre-wrap">
                {typeof result === "string" ? result : JSON.stringify(result, null, 2)}
            </pre>
        </div>
    );
}

function ToolFallbackError({ status, className, ...props }) {
    if (status?.type !== "incomplete") return null;
    const error = status.error;
    const errorText = error ? (typeof error === "string" ? error : JSON.stringify(error)) : null;
    if (!errorText) return null;

    return (
        <div className={cn("aui-tool-fallback-error", className)} {...props}>
            <p className="font-semibold text-muted-foreground">
                {status.reason === "cancelled" ? "Cancelled reason:" : "Error:"}
            </p>
            <p className="text-muted-foreground">{errorText}</p>
        </div>
    );
}

function ToolFallbackImpl({ toolName, argsText, result, status }) {
    const isCancelled = status?.type === "incomplete" && status.reason === "cancelled";
    return (
        <ToolFallbackRoot className={cn(isCancelled && "border-muted-foreground/30 bg-muted/30")}>
            <ToolFallbackTrigger toolName={toolName} status={status} />
            <ToolFallbackContent>
                <ToolFallbackError status={status} />
                <ToolFallbackArgs argsText={argsText} className={cn(isCancelled && "opacity-60")} />
                {!isCancelled ? <ToolFallbackResult result={result} /> : null}
            </ToolFallbackContent>
        </ToolFallbackRoot>
    );
}

export const ToolFallback = memo(ToolFallbackImpl);
ToolFallback.displayName = "ToolFallback";
ToolFallback.Root = ToolFallbackRoot;
ToolFallback.Trigger = ToolFallbackTrigger;
ToolFallback.Content = ToolFallbackContent;
ToolFallback.Args = ToolFallbackArgs;
ToolFallback.Result = ToolFallbackResult;
ToolFallback.Error = ToolFallbackError;
