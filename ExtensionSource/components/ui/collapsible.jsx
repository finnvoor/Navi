import React from "react";
import * as CollapsiblePrimitive from "@radix-ui/react-collapsible";

export const Collapsible = React.forwardRef(function Collapsible(props, ref) {
    return <CollapsiblePrimitive.Root ref={ref} {...props} />;
});

export const CollapsibleTrigger = React.forwardRef(function CollapsibleTrigger(props, ref) {
    return <CollapsiblePrimitive.Trigger ref={ref} {...props} />;
});

export const CollapsibleContent = React.forwardRef(function CollapsibleContent(props, ref) {
    return <CollapsiblePrimitive.Content ref={ref} {...props} />;
});
