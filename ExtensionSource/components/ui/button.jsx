import React from "react";
import { Slot } from "@radix-ui/react-slot";
import { cn } from "../../lib/utils.js";

const VARIANT_CLASS_NAMES = {
    default: "bg-primary text-primary-foreground shadow-sm hover:bg-primary/92",
    ghost: "text-foreground hover:bg-accent hover:text-accent-foreground",
    outline: "border border-border bg-background hover:bg-accent hover:text-accent-foreground",
    secondary: "bg-secondary text-secondary-foreground hover:bg-secondary/82"
};

const SIZE_CLASS_NAMES = {
    default: "h-10 px-4 py-2 text-sm",
    sm: "h-8 rounded-full px-3 text-xs",
    icon: "size-8"
};

export const Button = React.forwardRef(function Button(
    { asChild = false, className, size = "default", type = "button", variant = "default", ...props },
    ref
) {
    const Comp = asChild ? Slot : "button";

    return (
        <Comp
            className={cn(
                "inline-flex shrink-0 items-center justify-center gap-2 rounded-full font-medium transition-colors outline-none focus-visible:ring-2 focus-visible:ring-ring/35 disabled:pointer-events-none disabled:opacity-50 [&_svg]:pointer-events-none [&_svg]:size-4",
                VARIANT_CLASS_NAMES[variant],
                SIZE_CLASS_NAMES[size],
                className
            )}
            ref={ref}
            type={type}
            {...props}
        />
    );
});
