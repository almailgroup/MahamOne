"use client";

import * as React from "react";

/** The limits the rail may be dragged between, as the shell currently sees them. */
export type ResizerBounds = { min: number; max: number; preferred: number };

/**
 * Drag handle for the sidebar.
 *
 * Sits in the 1px gap between the rail and the content with a wider invisible
 * hit area, so it is easy to grab without drawing a visible gutter. Exposed as
 * an ARIA separator, which is the role screen readers expect for a splitter,
 * and driveable from the keyboard — arrow keys nudge, Home and End jump to the
 * limits, Enter resets.
 *
 * The limits are passed in rather than looked up: the rail can be dragged
 * wider while it holds the assistant's conversation than while it holds
 * navigation, and the shell caps that against the window width.
 */
export function SidebarResizer({
  width,
  bounds,
  onChange,
  onCommit,
}: {
  width: number;
  bounds: ResizerBounds;
  onChange: (width: number) => void;
  onCommit: (width: number) => void;
}) {
  const [dragging, setDragging] = React.useState(false);
  const { min, max, preferred } = bounds;
  const clamp = React.useCallback(
    (value: number) => Math.min(max, Math.max(min, Math.round(value))),
    [min, max],
  );
  const latest = React.useRef(width);

  React.useEffect(() => {
    latest.current = width;
  }, [width]);

  React.useEffect(() => {
    if (!dragging) return;

    function onMove(event: PointerEvent) {
      const next = clamp(event.clientX);
      latest.current = next;
      onChange(next);
    }

    function onUp() {
      setDragging(false);
      onCommit(latest.current);
    }

    window.addEventListener("pointermove", onMove);
    window.addEventListener("pointerup", onUp);
    // While dragging, stop the pointer from selecting text across the page.
    const previousSelect = document.body.style.userSelect;
    const previousCursor = document.body.style.cursor;
    document.body.style.userSelect = "none";
    document.body.style.cursor = "col-resize";

    return () => {
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", onUp);
      document.body.style.userSelect = previousSelect;
      document.body.style.cursor = previousCursor;
    };
  }, [dragging, clamp, onChange, onCommit]);

  function onKeyDown(event: React.KeyboardEvent) {
    const step = event.shiftKey ? 32 : 8;
    let next: number | null = null;

    if (event.key === "ArrowLeft") next = width - step;
    else if (event.key === "ArrowRight") next = width + step;
    else if (event.key === "Home") next = min;
    else if (event.key === "End") next = max;
    else if (event.key === "Enter" || event.key === " ") next = preferred;

    if (next === null) return;
    event.preventDefault();
    const clamped = clamp(next);
    onChange(clamped);
    onCommit(clamped);
  }

  return (
    <div
      role="separator"
      aria-orientation="vertical"
      aria-label="Resize sidebar"
      aria-valuenow={width}
      aria-valuemin={min}
      aria-valuemax={max}
      tabIndex={0}
      onPointerDown={(event) => {
        event.preventDefault();
        setDragging(true);
      }}
      onDoubleClick={() => {
        onChange(preferred);
        onCommit(preferred);
      }}
      onKeyDown={onKeyDown}
      className="group absolute inset-y-0 -end-1.5 z-40 hidden w-3 cursor-col-resize touch-none lg:block"
      title="Drag to resize. Double-click to reset."
    >
      {/* The visible line is 2px and only appears on hover, focus or drag. */}
      <span
        aria-hidden
        className={
          "pointer-events-none absolute inset-y-0 left-1/2 w-0.5 -translate-x-1/2 rounded-full transition-colors " +
          (dragging
            ? "bg-foreground/40"
            : "bg-transparent group-hover:bg-foreground/20 group-focus-visible:bg-foreground/40")
        }
      />
    </div>
  );
}
