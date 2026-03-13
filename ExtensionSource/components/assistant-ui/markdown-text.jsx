import React, { memo, useState } from "react";
import {
    MarkdownTextPrimitive,
    unstable_memoizeMarkdownComponents as memoizeMarkdownComponents,
    useIsMarkdownCodeBlock
} from "@assistant-ui/react-markdown";
import { Checkmark, Copy } from "../icons.jsx";
import remarkGfm from "remark-gfm";
import { TooltipIconButton } from "./tooltip-icon-button.jsx";
import { cn } from "../../lib/utils.js";

function MarkdownTextImpl() {
    return (
        <MarkdownTextPrimitive
            className="aui-md text-[15px] leading-7"
            components={defaultComponents}
            remarkPlugins={[remarkGfm]}
        />
    );
}

export const MarkdownText = memo(MarkdownTextImpl);

function CodeHeader({ code, language }) {
    const { copyToClipboard, isCopied } = useCopyToClipboard();

    return (
        <div className="mt-3 flex items-center justify-between rounded-t-2xl border border-border/80 border-b-0 bg-muted/70 px-3 py-2 text-[11px] text-muted-foreground">
            <span className="font-medium lowercase">{language}</span>
            <TooltipIconButton onClick={() => copyToClipboard(code)} tooltip="Copy">
                {isCopied ? <Checkmark /> : <Copy />}
            </TooltipIconButton>
        </div>
    );
}

function useCopyToClipboard({ copiedDuration = 2000 } = {}) {
    const [isCopied, setIsCopied] = useState(false);

    const copyToClipboard = (value) => {
        if (!value || isCopied) {
            return;
        }

        navigator.clipboard
            .writeText(value)
            .then(() => {
                setIsCopied(true);
                setTimeout(() => {
                    setIsCopied(false);
                }, copiedDuration);
            })
            .catch(() => {});
    };

    return { isCopied, copyToClipboard };
}

const defaultComponents = memoizeMarkdownComponents({
    h1: ({ className, ...props }) => (
        <h1
            className={cn(
                "mb-3 scroll-m-20 text-base font-semibold tracking-[-0.02em] first:mt-0 last:mb-0",
                className
            )}
            {...props}
        />
    ),
    h2: ({ className, ...props }) => (
        <h2 className={cn("mb-2 mt-5 scroll-m-20 text-sm font-semibold first:mt-0 last:mb-0", className)} {...props} />
    ),
    h3: ({ className, ...props }) => (
        <h3 className={cn("mb-2 mt-4 text-sm font-semibold first:mt-0 last:mb-0", className)} {...props} />
    ),
    p: ({ className, ...props }) => <p className={cn("my-3 leading-7 first:mt-0 last:mb-0", className)} {...props} />,
    a: ({ className, ...props }) => (
        <a
            className={cn(
                "text-foreground underline decoration-border underline-offset-4 hover:decoration-foreground",
                className
            )}
            rel="noreferrer"
            target="_blank"
            {...props}
        />
    ),
    blockquote: ({ className, ...props }) => (
        <blockquote
            className={cn("my-3 border-l-2 border-border/80 pl-4 text-muted-foreground italic", className)}
            {...props}
        />
    ),
    ul: ({ className, ...props }) => (
        <ul className={cn("my-3 ml-5 list-disc space-y-1.5 marker:text-muted-foreground", className)} {...props} />
    ),
    ol: ({ className, ...props }) => (
        <ol className={cn("my-3 ml-5 list-decimal space-y-1.5 marker:text-muted-foreground", className)} {...props} />
    ),
    li: ({ className, ...props }) => <li className={cn("leading-7", className)} {...props} />,
    hr: ({ className, ...props }) => <hr className={cn("my-4 border-border/70", className)} {...props} />,
    table: ({ className, ...props }) => (
        <table
            className={cn(
                "my-3 w-full border-separate border-spacing-0 overflow-hidden rounded-2xl border border-border/80 text-sm",
                className
            )}
            {...props}
        />
    ),
    th: ({ className, ...props }) => (
        <th
            className={cn(
                "bg-muted/70 px-3 py-2 text-left font-medium [[align=center]]:text-center [[align=right]]:text-right",
                className
            )}
            {...props}
        />
    ),
    td: ({ className, ...props }) => (
        <td
            className={cn(
                "border-t border-border/70 px-3 py-2 align-top [[align=center]]:text-center [[align=right]]:text-right",
                className
            )}
            {...props}
        />
    ),
    tr: ({ className, ...props }) => <tr className={cn("m-0 p-0", className)} {...props} />,
    pre: ({ className, ...props }) => (
        <pre
            className={cn(
                "overflow-x-auto rounded-b-2xl border border-border/80 border-t-0 bg-muted/50 p-3 text-xs leading-6",
                className
            )}
            {...props}
        />
    ),
    code: function Code({ className, ...props }) {
        const isCodeBlock = useIsMarkdownCodeBlock();

        return (
            <code
                className={cn(
                    !isCodeBlock &&
                        "rounded-md border border-border/80 bg-muted/60 px-1.5 py-0.5 font-mono text-[0.85em]",
                    className
                )}
                {...props}
            />
        );
    },
    CodeHeader
});
