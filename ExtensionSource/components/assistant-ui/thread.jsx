import React from "react";
import { MarkdownText } from "./markdown-text.jsx";
import { Reasoning, ReasoningGroup } from "./reasoning.jsx";
import { ToolFallback } from "./tool-fallback.jsx";
import { TooltipIconButton } from "./tooltip-icon-button.jsx";
import { Button } from "../ui/button.jsx";
import { cn } from "../../lib/utils.js";
import {
    ActionBarPrimitive,
    AuiIf,
    BranchPickerPrimitive,
    ComposerPrimitive,
    ErrorPrimitive,
    MessagePrimitive,
    SuggestionPrimitive,
    ThreadPrimitive
} from "@assistant-ui/react";
import {
    ArrowDown,
    ArrowUpCircleFill,
    Checkmark,
    ChevronLeft,
    ChevronRight,
    Copy,
    Pencil,
    ArrowClockwise,
    StopFill
} from "../icons.jsx";

export function Thread({ welcomeTitle, welcomeSubtitle }) {
    return (
        <ThreadPrimitive.Root
            className="aui-root aui-thread-root flex h-full flex-col bg-background"
            style={{ "--thread-max-width": "44rem" }}
        >
            <ThreadPrimitive.Viewport className="aui-thread-viewport flex flex-1 flex-col overflow-y-scroll scroll-smooth px-4 pt-4">
                <AuiIf condition={(s) => s.thread.isEmpty}>
                    <ThreadWelcome title={welcomeTitle} subtitle={welcomeSubtitle} />
                </AuiIf>

                <ThreadPrimitive.Messages components={{ UserMessage, AssistantMessage, EditComposer }} />

                <ThreadPrimitive.ViewportFooter className="aui-thread-viewport-footer sticky bottom-0 mx-auto mt-auto flex w-full max-w-(--thread-max-width) flex-col gap-4 overflow-visible rounded-t-3xl bg-background pb-4">
                    <ThreadScrollToBottom />
                    <Composer />
                </ThreadPrimitive.ViewportFooter>
            </ThreadPrimitive.Viewport>
        </ThreadPrimitive.Root>
    );
}

function ThreadScrollToBottom() {
    return (
        <ThreadPrimitive.ScrollToBottom asChild>
            <TooltipIconButton
                tooltip="Scroll to bottom"
                variant="outline"
                className="aui-thread-scroll-to-bottom absolute -top-12 z-10 self-center rounded-full disabled:invisible"
            >
                <ArrowDown />
            </TooltipIconButton>
        </ThreadPrimitive.ScrollToBottom>
    );
}

function ThreadWelcome({ title, subtitle }) {
    return (
        <div className="aui-thread-welcome-root mx-auto my-auto flex w-full max-w-(--thread-max-width) grow flex-col">
            <div className="flex w-full grow flex-col items-center justify-center px-4">
                <h1 className="fade-in slide-in-from-bottom-1 animate-in fill-mode-both text-2xl font-semibold duration-200">
                    {title || "Hello there!"}
                </h1>
                <p className="fade-in slide-in-from-bottom-1 animate-in fill-mode-both text-xl text-muted-foreground delay-75 duration-200">
                    {subtitle || "How can I help you today?"}
                </p>
            </div>
            <div className="grid w-full gap-2 pb-4 @md:grid-cols-2">
                <ThreadPrimitive.Suggestions>{() => <ThreadSuggestionItem />}</ThreadPrimitive.Suggestions>
            </div>
        </div>
    );
}

function ThreadSuggestionItem() {
    return (
        <div className="fade-in slide-in-from-bottom-2 animate-in fill-mode-both duration-200 @md:nth-[n+3]:block nth-[n+3]:hidden">
            <SuggestionPrimitive.Trigger send asChild>
                <Button
                    variant="ghost"
                    className="h-auto w-full flex-wrap items-start justify-start gap-1 rounded-3xl border bg-background px-4 py-3 text-left text-sm transition-colors hover:bg-muted @md:flex-col"
                >
                    <SuggestionPrimitive.Title className="font-medium" />
                    <SuggestionPrimitive.Description className="text-muted-foreground empty:hidden" />
                </Button>
            </SuggestionPrimitive.Trigger>
        </div>
    );
}

function Composer() {
    return (
        <ComposerPrimitive.Root className="aui-composer-root relative flex w-full flex-col rounded-3xl border bg-background p-2.5 transition-shadow focus-within:border-ring/75 focus-within:ring-2 focus-within:ring-ring/20">
            <ComposerPrimitive.Input
                placeholder="Message Navi…"
                className="aui-composer-input max-h-32 min-h-10 w-full resize-none bg-transparent px-2 py-1 text-sm outline-none placeholder:text-muted-foreground/80"
                rows={1}
                autoFocus
                aria-label="Message Navi"
            />
            <ComposerAction />
        </ComposerPrimitive.Root>
    );
}

function ComposerAction() {
    return (
        <div className="flex items-center justify-end">
            <AuiIf condition={(s) => !s.thread.isRunning}>
                <ComposerPrimitive.Send asChild>
                    <button
                        className="size-7 text-foreground transition-opacity hover:opacity-80 disabled:opacity-30"
                        type="submit"
                    >
                        <ArrowUpCircleFill className="size-7" />
                    </button>
                </ComposerPrimitive.Send>
            </AuiIf>
            <AuiIf condition={(s) => s.thread.isRunning}>
                <ComposerPrimitive.Cancel asChild>
                    <Button className="size-8 rounded-full" size="icon" aria-label="Stop generating">
                        <StopFill className="size-3 fill-current" />
                    </Button>
                </ComposerPrimitive.Cancel>
            </AuiIf>
        </div>
    );
}

function AssistantMessage() {
    return (
        <MessagePrimitive.Root
            className="aui-assistant-message-root fade-in slide-in-from-bottom-1 relative mx-auto w-full max-w-(--thread-max-width) animate-in py-3 duration-150"
            data-role="assistant"
        >
            <div className="wrap-break-word px-2 leading-relaxed text-foreground">
                <MessagePrimitive.Parts
                    components={{
                        Text: MarkdownText,
                        Reasoning: Reasoning,
                        ReasoningGroup: ReasoningGroup,
                        tools: { Fallback: ToolFallback }
                    }}
                />
                <MessageError />
            </div>
            <div className="mt-1 ml-2 flex min-h-6 items-center">
                <BranchPicker />
                <AssistantActionBar />
            </div>
        </MessagePrimitive.Root>
    );
}

function AssistantActionBar() {
    return (
        <ActionBarPrimitive.Root hideWhenRunning autohide="always" className="flex gap-1 text-muted-foreground">
            <ActionBarPrimitive.Copy asChild>
                <TooltipIconButton tooltip="Copy">
                    <AuiIf condition={(s) => s.message.isCopied}>
                        <Checkmark />
                    </AuiIf>
                    <AuiIf condition={(s) => !s.message.isCopied}>
                        <Copy />
                    </AuiIf>
                </TooltipIconButton>
            </ActionBarPrimitive.Copy>
            <ActionBarPrimitive.Reload asChild>
                <TooltipIconButton tooltip="Retry">
                    <ArrowClockwise />
                </TooltipIconButton>
            </ActionBarPrimitive.Reload>
        </ActionBarPrimitive.Root>
    );
}

function UserMessage() {
    return (
        <MessagePrimitive.Root
            className="aui-user-message-root fade-in slide-in-from-bottom-1 mx-auto grid w-full max-w-(--thread-max-width) animate-in auto-rows-auto grid-cols-[minmax(72px,1fr)_auto] content-start gap-y-2 px-2 py-3 duration-150 [&:where(>*)]:col-start-2"
            data-role="user"
        >
            <div className="relative col-start-2 min-w-0">
                <div className="wrap-break-word rounded-2xl bg-muted px-4 py-2.5 text-foreground">
                    <MessagePrimitive.Parts />
                </div>
                <div className="absolute left-0 top-1/2 -translate-x-full -translate-y-1/2 pr-2">
                    <UserActionBar />
                </div>
            </div>
            <BranchPicker className="col-span-full col-start-1 row-start-3 -mr-1 justify-end" />
        </MessagePrimitive.Root>
    );
}

function UserActionBar() {
    return (
        <ActionBarPrimitive.Root hideWhenRunning autohide="always" className="flex flex-col items-end">
            <ActionBarPrimitive.Edit asChild>
                <TooltipIconButton tooltip="Edit">
                    <Pencil />
                </TooltipIconButton>
            </ActionBarPrimitive.Edit>
        </ActionBarPrimitive.Root>
    );
}

function EditComposer() {
    return (
        <MessagePrimitive.Root className="mx-auto flex w-full max-w-(--thread-max-width) flex-col px-2 py-3">
            <ComposerPrimitive.Root className="ml-auto flex w-full max-w-[85%] flex-col rounded-2xl bg-muted">
                <ComposerPrimitive.Input
                    className="min-h-14 w-full resize-none bg-transparent p-4 text-sm text-foreground outline-none"
                    autoFocus
                />
                <div className="mx-3 mb-3 flex items-center gap-2 self-end">
                    <ComposerPrimitive.Cancel asChild>
                        <Button variant="ghost" size="sm">
                            Cancel
                        </Button>
                    </ComposerPrimitive.Cancel>
                    <ComposerPrimitive.Send asChild>
                        <Button size="sm">Update</Button>
                    </ComposerPrimitive.Send>
                </div>
            </ComposerPrimitive.Root>
        </MessagePrimitive.Root>
    );
}

function MessageError() {
    return (
        <MessagePrimitive.Error>
            <ErrorPrimitive.Root className="mt-2 rounded-md border border-destructive bg-destructive/10 p-3 text-sm text-destructive">
                <ErrorPrimitive.Message className="line-clamp-2" />
            </ErrorPrimitive.Root>
        </MessagePrimitive.Error>
    );
}

function BranchPicker({ className, ...props }) {
    return (
        <BranchPickerPrimitive.Root
            hideWhenSingleBranch
            className={cn("mr-2 -ml-2 inline-flex items-center text-xs text-muted-foreground", className)}
            {...props}
        >
            <BranchPickerPrimitive.Previous asChild>
                <TooltipIconButton tooltip="Previous">
                    <ChevronLeft />
                </TooltipIconButton>
            </BranchPickerPrimitive.Previous>
            <span className="font-medium">
                <BranchPickerPrimitive.Number /> / <BranchPickerPrimitive.Count />
            </span>
            <BranchPickerPrimitive.Next asChild>
                <TooltipIconButton tooltip="Next">
                    <ChevronRight />
                </TooltipIconButton>
            </BranchPickerPrimitive.Next>
        </BranchPickerPrimitive.Root>
    );
}
