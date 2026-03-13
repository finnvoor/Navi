import React from "react";
import * as TooltipPrimitive from "@radix-ui/react-tooltip";
import { cn } from "../../lib/utils.js";

export function TooltipProvider({ children }) {
    return <TooltipPrimitive.Provider delayDuration={120}>{children}</TooltipPrimitive.Provider>;
}

export function Tooltip({ children, ...props }) {
    return <TooltipPrimitive.Root {...props}>{children}</TooltipPrimitive.Root>;
}

export function TooltipTrigger(props) {
    return <TooltipPrimitive.Trigger {...props} />;
}

export const TooltipContent = React.forwardRef(function TooltipContent({ className, sideOffset = 8, ...props }, ref) {
    return (
        <TooltipPrimitive.Portal>
            <TooltipPrimitive.Content
                className={cn(
                    "z-50 overflow-hidden rounded-xl border border-border bg-card px-2.5 py-1.5 text-[11px] text-foreground shadow-xl data-[state=delayed-open]:animate-in data-[state=closed]:animate-out",
                    className
                )}
                ref={ref}
                sideOffset={sideOffset}
                {...props}
            />
        </TooltipPrimitive.Portal>
    );
});
