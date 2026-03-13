import React, { memo, useCallback, useRef, useState } from "react";
import { cva } from "class-variance-authority";
import { Brain, ChevronDown } from "../icons.jsx";
import { useScrollLock, useAuiState } from "@assistant-ui/react";
import { MarkdownText } from "./markdown-text.jsx";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "../ui/collapsible.jsx";
import { cn } from "../../lib/utils.js";

const ANIMATION_DURATION = 200;

const reasoningVariants = cva("aui-reasoning-root mb-4 w-full", {
    variants: {
        variant: {
            outline: "rounded-lg border px-3 py-2",
            ghost: "",
            muted: "rounded-lg bg-muted/50 px-3 py-2"
        }
    },
    defaultVariants: { variant: "outline" }
});

function ReasoningRoot({
    className,
    variant,
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
            className={cn("group/reasoning-root", reasoningVariants({ variant, className }))}
            style={{ "--animation-duration": `${ANIMATION_DURATION}ms` }}
            {...props}
        >
            {children}
        </Collapsible>
    );
}

function ReasoningFade({ className, ...props }) {
    return (
        <div
            className={cn(
                "aui-reasoning-fade pointer-events-none absolute inset-x-0 bottom-0 z-10 h-8",
                "bg-[linear-gradient(to_top,var(--color-background),transparent)]",
                "group-data-[variant=muted]/reasoning-root:bg-[linear-gradient(to_top,hsl(var(--muted)/0.5),transparent)]",
                "fade-in-0 animate-in",
                "group-data-[state=open]/collapsible-content:animate-out",
                "group-data-[state=open]/collapsible-content:fade-out-0",
                "group-data-[state=open]/collapsible-content:delay-[calc(var(--animation-duration)*0.75)]",
                "group-data-[state=open]/collapsible-content:fill-mode-forwards",
                "duration-(--animation-duration)",
                "group-data-[state=open]/collapsible-content:duration-(--animation-duration)",
                className
            )}
            {...props}
        />
    );
}

function ReasoningTrigger({ active, duration, className, ...props }) {
    const durationText = duration ? ` (${duration}s)` : "";
    return (
        <CollapsibleTrigger
            className={cn(
                "aui-reasoning-trigger group/trigger flex max-w-[75%] items-center gap-2 py-1 text-sm text-muted-foreground transition-colors hover:text-foreground",
                className
            )}
            {...props}
        >
            <Brain className="aui-reasoning-trigger-icon size-4 shrink-0" />
            <span className="relative leading-none">
                <span>Reasoning{durationText}</span>
                {active ? (
                    <span
                        aria-hidden
                        className="shimmer pointer-events-none absolute inset-0 motion-reduce:animate-none"
                    >
                        Reasoning{durationText}
                    </span>
                ) : null}
            </span>
            <ChevronDown
                className={cn(
                    "mt-0.5 size-4 shrink-0 transition-transform duration-(--animation-duration) ease-out",
                    "group-data-[state=closed]/trigger:-rotate-90",
                    "group-data-[state=open]/trigger:rotate-0"
                )}
            />
        </CollapsibleTrigger>
    );
}

function ReasoningContent({ className, children, ...props }) {
    return (
        <CollapsibleContent
            className={cn(
                "aui-reasoning-content relative overflow-hidden text-sm text-muted-foreground outline-none",
                "group/collapsible-content ease-out",
                "data-[state=closed]:animate-collapsible-up data-[state=open]:animate-collapsible-down",
                "data-[state=closed]:fill-mode-forwards data-[state=closed]:pointer-events-none",
                "data-[state=open]:duration-(--animation-duration) data-[state=closed]:duration-(--animation-duration)",
                className
            )}
            {...props}
        >
            {children}
            <ReasoningFade />
        </CollapsibleContent>
    );
}

function ReasoningText({ className, children, ...props }) {
    return (
        <div
            className={cn(
                "aui-reasoning-text relative z-0 max-h-64 overflow-y-auto pt-2 pb-2 pl-6 leading-relaxed",
                "transform-gpu transition-[transform,opacity]",
                "group-data-[state=open]/collapsible-content:animate-in group-data-[state=closed]/collapsible-content:animate-out",
                "group-data-[state=open]/collapsible-content:fade-in-0 group-data-[state=closed]/collapsible-content:fade-out-0",
                "group-data-[state=open]/collapsible-content:slide-in-from-top-4 group-data-[state=closed]/collapsible-content:slide-out-to-top-4",
                "group-data-[state=open]/collapsible-content:duration-(--animation-duration) group-data-[state=closed]/collapsible-content:duration-(--animation-duration)",
                className
            )}
            {...props}
        >
            {children}
        </div>
    );
}

const ReasoningImpl = () => <MarkdownText />;

const ReasoningGroupImpl = ({ children, startIndex, endIndex }) => {
    const isReasoningStreaming = useAuiState((s) => {
        if (s.message.status?.type !== "running") return false;
        const lastIndex = s.message.parts.length - 1;
        if (lastIndex < 0) return false;
        const lastType = s.message.parts[lastIndex]?.type;
        if (lastType !== "reasoning") return false;
        return lastIndex >= startIndex && lastIndex <= endIndex;
    });

    return (
        <ReasoningRoot defaultOpen={isReasoningStreaming}>
            <ReasoningTrigger active={isReasoningStreaming} />
            <ReasoningContent aria-busy={isReasoningStreaming}>
                <ReasoningText>{children}</ReasoningText>
            </ReasoningContent>
        </ReasoningRoot>
    );
};

export const Reasoning = memo(ReasoningImpl);
Reasoning.displayName = "Reasoning";
Reasoning.Root = ReasoningRoot;
Reasoning.Trigger = ReasoningTrigger;
Reasoning.Content = ReasoningContent;
Reasoning.Text = ReasoningText;
Reasoning.Fade = ReasoningFade;

export const ReasoningGroup = memo(ReasoningGroupImpl);
ReasoningGroup.displayName = "ReasoningGroup";
