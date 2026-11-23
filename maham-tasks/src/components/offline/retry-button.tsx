"use client";

import { RotateCw } from "lucide-react";

import { Button } from "@/components/ui/button";

/** Reloads whatever was being asked for. A link would be cached too. */
export function RetryButton({ label }: { label: string }) {
  return (
    <Button variant="outline" size="sm" onClick={() => window.location.reload()}>
      <RotateCw />
      {label}
    </Button>
  );
}
