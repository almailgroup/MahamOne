"use client";

import * as React from "react";
import * as TabsPrimitive from "@radix-ui/react-tabs";

import { cn } from "@/lib/utils";

const Tabs = TabsPrimitive.Root;

function TabsList({
  className,
  ...props
}: React.ComponentProps<typeof TabsPrimitive.List>) {
  return (
    <TabsPrimitive.List
      data-slot="tabs-list"
      className={cn(
        "inline-flex items-center justify-center gap-0.5 rounded-lg bg-slate-100 p-1 text-slate-600",
        className,
      )}
      {...props}
    />
  );
}

function TabsTrigger({
  className,
  ...props
}: React.ComponentProps<typeof TabsPrimitive.Trigger>) {
  return (
    <TabsPrimitive.Trigger
      data-slot="tabs-trigger"
      className={cn(
        "inline-flex items-center justify-center gap-1.5 whitespace-nowrap rounded-md px-3 py-1.5 text-sm font-medium transition-colors hover:text-slate-900 pointer-coarse:min-h-10",
        "hover:text-foreground focus-visible:outline-none",
        "disabled:pointer-events-none disabled:opacity-50",
        "data-[state=active]:bg-surface data-[state=active]:text-slate-900 data-[state=active]:shadow-sm",
        "[&_svg]:size-3.5 [&_svg]:shrink-0",
        className,
      )}
      {...props}
    />
  );
}

function TabsContent({
  className,
  ...props
}: React.ComponentProps<typeof TabsPrimitive.Content>) {
  return (
    <TabsPrimitive.Content
      data-slot="tabs-content"
      className={cn("mt-4 focus-visible:outline-none", className)}
      {...props}
    />
  );
}

export { Tabs, TabsList, TabsTrigger, TabsContent };
