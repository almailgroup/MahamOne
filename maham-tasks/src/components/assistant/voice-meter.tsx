"use client";

import * as React from "react";

/** How many bars the trace holds. At ~60fps this is about a second of sound. */
const BARS = 28;
/** Bars never collapse to nothing, so the trace reads as a line when silent. */
const FLOOR = 0.12;

/**
 * The level meter, drawn the way a voice note draws one: a row of bars that
 * scrolls, newest at the leading edge, each one the loudness at the moment it
 * was taken.
 *
 * It renders once. Everything after that is written straight to the bars'
 * `transform` inside an animation frame — sixty React renders a second, of a
 * panel that contains the whole conversation, to move some bars would be a
 * poor trade. `level` is a ref for the same reason.
 *
 * The history shifts on a timer rather than every frame: at 60fps a 28-bar
 * trace would scroll past in under half a second, too fast to read as the
 * shape of what you just said.
 */
export function VoiceMeter({ level }: { level: React.RefObject<number> }) {
  const bars = React.useRef<(HTMLSpanElement | null)[]>([]);

  React.useEffect(() => {
    const history = new Array<number>(BARS).fill(0);
    let frame = 0;
    let lastShift = 0;
    let peak = 0;

    const draw = (now: number) => {
      // The loudest moment since the last shift, so a syllable that lands
      // between two samples still shows up.
      peak = Math.max(peak, level.current ?? 0);

      if (now - lastShift > 55) {
        history.push(peak);
        history.shift();
        peak = 0;
        lastShift = now;
      }

      for (let i = 0; i < BARS; i += 1) {
        const node = bars.current[i];
        if (!node) continue;
        // Older samples fade towards the trailing edge, as a voice note does.
        const age = i / (BARS - 1);
        const height = FLOOR + (1 - FLOOR) * history[i];
        node.style.transform = `scaleY(${height.toFixed(3)})`;
        node.style.opacity = (0.35 + 0.65 * age).toFixed(2);
      }
      frame = requestAnimationFrame(draw);
    };

    frame = requestAnimationFrame(draw);
    return () => cancelAnimationFrame(frame);
  }, [level]);

  return (
    <span
      aria-hidden
      className="flex h-5 shrink-0 items-center gap-[2px] overflow-hidden"
    >
      {Array.from({ length: BARS }, (_, i) => (
        <span
          key={i}
          ref={(node) => {
            bars.current[i] = node;
          }}
          data-bar
          className="h-full w-[2px] shrink-0 origin-center rounded-full bg-foreground/80"
          style={{ transform: `scaleY(${FLOOR})` }}
        />
      ))}
    </span>
  );
}

/** mm:ss since dictation began, ticking once a second. */
export function Elapsed({ since }: { since: number }) {
  const [now, setNow] = React.useState(() => Date.now());

  React.useEffect(() => {
    const tick = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(tick);
  }, []);

  const seconds = Math.max(0, Math.floor((now - since) / 1000));
  // Latin digits in both languages: this sits beside a waveform, not in a
  // sentence, and it should not change width as it counts.
  return (
    <span className="shrink-0 tabular-nums">
      {String(Math.floor(seconds / 60)).padStart(2, "0")}:
      {String(seconds % 60).padStart(2, "0")}
    </span>
  );
}
