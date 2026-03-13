import React from "react";
import { Tooltip, TooltipContent, TooltipTrigger } from "../ui/tooltip.jsx";
import { Button } from "../ui/button.jsx";
import { cn } from "../../lib/utils.js";

export const TooltipIconButton = React.forwardRef(function TooltipIconButton(
    { children, className, side = "bottom", tooltip, ...props },
    ref
) {
    return (
        <Tooltip>
            <TooltipTrigger asChild>
                <Button
                    className={cn("size-7 rounded-full p-0 text-muted-foreground", className)}
                    ref={ref}
                    size="icon"
                    variant="ghost"
                    {...props}
                >
                    {children}
                    <span className="sr-only">{tooltip}</span>
                </Button>
            </TooltipTrigger>
            <TooltipContent side={side}>{tooltip}</TooltipContent>
        </Tooltip>
    );
});
