"use client";

import * as React from "react";
import { Check, CornerDownLeft, Loader2, Mic, RotateCcw, Sparkles, Square, X } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { cn } from "@/lib/utils";
import { useI18n } from "@/lib/i18n/client";
import { useSpeechInput } from "@/lib/speech/use-speech-input";
import { Elapsed, VoiceMeter } from "@/components/assistant/voice-meter";
import type { Assistant } from "@/components/assistant/use-assistant";
import type { AssistantAction, AssistantMessage } from "@/lib/assistant/types";

/** Openers that match what the assistant can actually answer today. */
const STARTERS = [
  "assistant.starter.overdue",
  "assistant.starter.today",
  "assistant.starter.next",
  "assistant.starter.review",
  "assistant.starter.summary",
] as const;

/**
 * The AI assistant, living in the sidebar rail rather than in a modal over
 * the board. The point is that you can read a task while you ask about it, so
 * this never covers the work.
 *
 * The thread is held by AppShell and passed in, so the rail and the mobile
 * drawer show one conversation rather than drifting apart, and closing the
 * panel keeps the history.
 *
 * Every answer comes from a Server Action that builds its own view of the
 * board under the caller's permissions: this component never holds task data
 * and never talks to a model directly.
 */
export function AssistantPanel({
  assistant,
  active,
  onClose,
}: {
  assistant: Assistant;
  /** True when this copy is the one on screen. */
  active: boolean;
  onClose: () => void;
}) {
  const { messages, draft, setDraft, pending, send, clear, confirm, dismiss, running } =
    assistant;
  const { t, tm } = useI18n();

  /**
   * Dictation appends to whatever is already in the box rather than replacing
   * it, so you can type half a question, speak the rest, and fix it by hand
   * before sending. Nothing is ever sent by voice alone: a transcript is a
   * guess, and it goes in front of you to approve like anything else would.
   */
  const voice = useSpeechInput(
    React.useCallback(
      (heard: string) =>
        // An updater, not `draft + heard`: the recogniser can settle two
        // phrases inside one tick, and both would read the same stale draft
        // and the second would eat the first.
        setDraft((current) => (current ? `${current.trimEnd()} ` : "") + heard),
      [setDraft],
    ),
  );

  // Stop the microphone the moment this copy leaves the screen — closing the
  // panel or crossing the breakpoint into the drawer should not leave it live.
  /** Set when the mic is pressed in a browser that cannot do this. */
  const [voiceNote, setVoiceNote] = React.useState(false);

  const { listening: hearing, stop: stopHearing } = voice;
  React.useEffect(() => {
    if (!active && hearing) stopHearing();
    // Not `[active, voice]`: the hook returns a fresh object every render, so
    // depending on it would re-run this on every keystroke.
  }, [active, hearing, stopHearing]);

  const scrollRef = React.useRef<HTMLDivElement>(null);
  const inputRef = React.useRef<HTMLTextAreaElement>(null);

  /**
   * Grow the box to the question.
   *
   * A one-row textarea scrolls its own content, so anything longer than a line
   * was written through a slot — the beginning of your own sentence out of
   * sight while you finished it. Height is reset before it is measured, or it
   * only ever ratchets upwards and never shrinks back when text is deleted.
   */
  React.useEffect(() => {
    const box = inputRef.current;
    // Both copies of the panel are mounted and one is `display: none`, where
    // `scrollHeight` is 0 — measuring there collapsed the field to nothing and
    // it stayed that way, because the height is only recomputed when the text
    // changes and there was no field left to type in.
    if (!box || box.offsetParent === null) return;
    box.style.height = "auto";
    box.style.height = `${box.scrollHeight}px`;
  }, [draft, active]);

  /** Only the copy actually rendered — the other is display:none. */
  const onScreen = () => inputRef.current?.offsetParent !== null;

  // Keep the newest turn in view as the thread grows.
  React.useEffect(() => {
    const node = scrollRef.current;
    if (node && node.offsetParent !== null) node.scrollTop = node.scrollHeight;
  }, [messages, pending, running, active]);

  // Opening used to drop focus on <body>: the launcher that was focused gets
  // display:none the moment the rail swaps, and nothing picked focus up.
  React.useEffect(() => {
    if (!active) return;
    const frame = requestAnimationFrame(() => {
      if (onScreen()) inputRef.current?.focus();
    });
    return () => cancelAnimationFrame(frame);
  }, [active]);

  return (
    <div className="flex h-full flex-col">
      <header className="flex items-start justify-between gap-2 px-3 py-2.5">
        <div className="flex min-w-0 items-center gap-2.5">
          <span
            aria-hidden
            className="flex size-7 shrink-0 items-center justify-center rounded-lg bg-primary text-primary-foreground"
          >
            <Sparkles className="size-3.5" />
          </span>
          <div className="min-w-0">
            <h2 className="text-sm font-semibold leading-tight tracking-tight">
              {t("nav.assistant")}
            </h2>
            <p className="truncate text-[0.6875rem] leading-tight text-muted-foreground">
              {t("assistant.subtitle")}
            </p>
          </div>
        </div>

        <div className="flex shrink-0 items-center gap-0.5">
          {messages.length > 0 && (
            <Button
              variant="ghost"
              size="icon-sm"
              onClick={clear}
              disabled={pending || running !== null}
              aria-label={t("assistant.clear")}
              title={t("assistant.clear")}
            >
              <RotateCcw />
            </Button>
          )}
          <Button
            variant="ghost"
            size="icon-sm"
            onClick={onClose}
            aria-label={t("assistant.close")}
            title={t("assistant.backToNav")}
          >
            <X />
          </Button>
        </div>
      </header>

      <div
        ref={scrollRef}
        className="scrollbar-thin min-h-0 flex-1 overflow-y-auto px-3 py-3"
      >
        {messages.length === 0 ? (
          <Welcome onPick={send} disabled={pending} />
        ) : (
          <div className="flex flex-col gap-3">
            {messages.map((message) => (
              <Bubble
                key={message.id}
                message={message}
                onConfirm={() => confirm(message.id)}
                onDismiss={() => dismiss(message.id)}
                running={running === message.id}
                // One proposal at a time: a second card's buttons go quiet
                // while the first is being written, so two confirmations
                // cannot race into the same board.
                blocked={running !== null && running !== message.id}
              />
            ))}
            {pending && <Thinking />}
          </div>
        )}
      </div>

      <form
        className="p-2.5"
        onSubmit={(event) => {
          event.preventDefault();
          voice.stop();
          send(draft);
        }}
      >
        {/* Above the box, not inside it: the interim transcript is the
            engine's current guess and it rewrites itself word by word.
            Putting that in the textarea would move the caret under anyone
            trying to correct what has already settled. */}
        {voice.listening && (
          <div className="mb-1.5 flex flex-col gap-1 rounded-[1.25rem] bg-muted/60 px-3.5 py-2.5">
            <div className="flex items-center gap-2 text-xs text-muted-foreground">
              <span
                aria-hidden
                className="size-1.5 shrink-0 animate-pulse rounded-full bg-warning-marker"
              />
              <VoiceMeter level={voice.level} />
              {voice.startedAt !== null && <Elapsed since={voice.startedAt} />}
            </div>

            {/* The transcript, updating as it is spoken and staying until the
                silence runs out or the stop button is pressed. Settled words
                have already gone into the box; this is the part still being
                decided, which is why it is here and not there. */}
            <p
              aria-live="polite"
              className="min-h-4 text-xs leading-snug text-foreground/90"
            >
              {voice.interim || (
                <span className="text-muted-foreground">
                  {t("voice.listening")}
                </span>
              )}
            </p>
          </div>
        )}

        {(voice.error || voiceNote) && (
          <p
            aria-live="polite"
            className="mb-1.5 px-1 text-xs leading-snug text-muted-foreground"
          >
            {voice.error ? tm(voice.error) : t("voice.unsupported")}
          </p>
        )}

        {/*
          * One field, not three controls in a row.
          *
          * The box and the two buttons each had their own border and their own
          * rounding, so the foot of the panel read as a pile of parts rather
          * than somewhere to type. The shape is on the container now and the
          * textarea inside it is bare; the whole thing lights up together when
          * the caret is in it, which is what makes it read as one control.
          *
          * The box's corners are deep, so the padding sets the first line well
          * clear of where the curve is still turning — text that starts there
          * looks crowded into it. The text also starts on the same line as the
          * microphone icon below it — 16px of padding, the button's -4px,
          * and the icon centred in its 36px — so the two read as one column.
          */}
        <div
          className={cn(
            "flex flex-col gap-1 rounded-3xl bg-card px-4 pt-3 pb-2 shadow-[var(--shadow-xs)]",
            // Lit as one control when the caret is in it: a soft glow of the
            // theme's colour round the whole box, nothing inside it. A glow, not
            // a ring: these boxes hold the caret for long stretches (the
            // assistant focuses its own the moment it opens), and a ring read as
            // an outline round the box the whole time.
            "transition-shadow duration-200",
            "focus-within:shadow-[0_6px_24px_-6px_color-mix(in_oklab,var(--primary)_45%,transparent)]",
            pending && "opacity-60",
          )}
        >
          <Textarea
            ref={inputRef}
            value={draft}
            onChange={(event) => setDraft(event.target.value)}
            onKeyDown={(event) => {
              // Enter sends; Shift+Enter is a newline, as in the comment box.
              if (event.key === "Enter" && !event.shiftKey) {
                event.preventDefault();
                send(draft);
              }
            }}
            placeholder={t("assistant.placeholder")}
            rows={1}
            maxLength={2000}
            className={cn(
              "max-h-40 min-h-0 resize-none overflow-y-auto rounded-none bg-transparent px-[7px] py-0",
              // Bold, and a size up: the one thing on the panel meant to be
              // read at a glance, typed or not.
              "text-[0.9375rem] leading-6 font-semibold placeholder:font-semibold",
              "hover:bg-transparent focus-visible:bg-transparent",
              // The container carries the focus affordance. Without this the
              // global focus ring drew a second rounded box inside the first.
              "shadow-none focus-visible:shadow-none",
              "focus-visible:ring-0 focus-visible:ring-offset-0",
            )}
            aria-label={t("assistant.ask")}
          />

          <div className="flex items-center justify-between gap-1">
            {/* Always rendered, never hidden. Hiding it where the browser has
                no recogniser meant the feature simply was not there on some
                machines and present on others, with nothing on screen to say
                why — which is a worse answer than a button that explains
                itself. */}
            <Button
              type="button"
              size="icon-sm"
              variant={voice.listening ? "default" : "ghost"}
              onClick={voice.supported ? voice.toggle : () => setVoiceNote(true)}
              disabled={pending}
              aria-pressed={voice.supported ? voice.listening : undefined}
              aria-label={t(
                !voice.supported
                  ? "voice.unsupported"
                  : voice.listening
                    ? "voice.stop"
                    : "voice.start",
              )}
              title={t(
                !voice.supported
                  ? "voice.unsupported"
                  : voice.listening
                    ? "voice.stop"
                    : "voice.start",
              )}
              className={cn("-ms-1", !voice.supported && "opacity-40")}
            >
              {voice.listening ? <Square /> : <Mic />}
            </Button>

            <div className="flex items-center gap-2">
              {/* Only near the limit, and only as a number: a counter that is
                  always there is noise on a box most questions never fill. */}
              {draft.length > 1600 && (
                <span
                  className={cn(
                    "text-[0.6875rem] tabular-nums",
                    draft.length >= 2000 ? "text-warning" : "text-muted-foreground",
                  )}
                >
                  {2000 - draft.length}
                </span>
              )}
              <Button
                type="submit"
                size="icon-sm"
                disabled={pending || !draft.trim()}
                aria-label={t("assistant.send")}
                className="-me-1"
              >
                {pending ? (
                  <Loader2 className="animate-spin" />
                ) : (
                  <CornerDownLeft className="rtl:-scale-x-100" />
                )}
              </Button>
            </div>
          </div>
        </div>
      </form>
    </div>
  );
}

function Welcome({
  onPick,
  disabled,
}: {
  onPick: (question: string) => void;
  disabled: boolean;
}) {
  const { t } = useI18n();
  return (
    <div className="flex flex-col gap-3 py-1">
      <p className="text-sm leading-relaxed text-muted-foreground">
        {t("assistant.welcome")}
      </p>

      <div className="flex flex-col items-start gap-1.5">
        {STARTERS.map((starter) => (
          <button
            key={starter}
            type="button"
            disabled={disabled}
            onClick={() => onPick(t(starter))}
            className={cn(
              "max-w-full rounded-full bg-foreground/[0.05] px-3 py-1.5 text-start text-xs transition-colors",
              "text-muted-foreground hover:bg-accent hover:text-foreground",
              "disabled:pointer-events-none disabled:opacity-50",
            )}
          >
            {t(starter)}
          </button>
        ))}
      </div>
    </div>
  );
}

function Bubble({
  message,
  onConfirm,
  onDismiss,
  running,
  blocked,
}: {
  message: AssistantMessage;
  onConfirm: () => void;
  onDismiss: () => void;
  running: boolean;
  blocked: boolean;
}) {
  const { t } = useI18n();
  const mine = message.role === "user";

  return (
    <div className={cn("flex gap-2", mine && "justify-end")}>
      {!mine && (
        <span
          aria-hidden
          className="mt-0.5 flex size-5 shrink-0 items-center justify-center rounded-xl bg-muted"
        >
          <Sparkles className="size-2.5" />
        </span>
      )}

      <div
        className={cn(
          "max-w-[88%] rounded-[1.25rem] px-3.5 py-2.5 text-[0.8125rem] leading-relaxed",
          mine
            ? "bg-primary text-primary-foreground"
            : "bg-card shadow-[var(--shadow-xs)]",
        )}
      >
        <span className="sr-only">
          {mine ? t("assistant.youAsked") : t("assistant.answered")}
        </span>
        <AnswerText text={message.text} />
        {message.action?.preview && (
          <Proposal
            action={message.action}
            outcome={message.outcome}
            onConfirm={onConfirm}
            onDismiss={onDismiss}
            running={running}
            blocked={blocked}
          />
        )}
      </div>
    </div>
  );
}

/**
 * A change the assistant would like to make, and the decision about it.
 *
 * Nothing has happened when this renders. The model returned a proposal; the
 * portal resolved the ids in it to names on the server so that what is shown
 * is what will run. Pressing Confirm sends the arguments back to be validated
 * again and carried out through the same Server Action the ordinary buttons
 * call — so this card can never do more than the person reading it could.
 *
 * Once decided it stays on screen as a record of what was agreed, with the
 * buttons replaced by the outcome: a thread that silently rewrote itself
 * would leave no way to see what you had said yes to.
 */
function Proposal({
  action,
  outcome,
  onConfirm,
  onDismiss,
  running,
  blocked,
}: {
  action: AssistantAction;
  outcome: AssistantMessage["outcome"];
  onConfirm: () => void;
  onDismiss: () => void;
  running: boolean;
  blocked: boolean;
}) {
  const { t } = useI18n();
  const preview = action.preview;
  if (!preview) return null;

  return (
    <div className="mt-2.5 rounded-[1.25rem] bg-background p-3 shadow-[var(--shadow-xs)]">
      <p className="text-xs font-semibold leading-tight">{preview.heading}</p>

      <dl className="mt-2 flex flex-col gap-1">
        {preview.rows.map((row) => (
          <div key={row.label} className="flex gap-2 text-xs leading-snug">
            <dt className="w-20 shrink-0 text-muted-foreground">{row.label}</dt>
            <dd className="min-w-0 break-words">{row.value}</dd>
          </div>
        ))}
      </dl>

      {outcome ? (
        <p className="mt-2.5 flex items-center gap-1.5 text-xs text-muted-foreground">
          {outcome === "done" && <Check aria-hidden className="size-3.5" />}
          {t(outcome === "done" ? "assistant.done" : "assistant.dismissed")}
        </p>
      ) : (
        <div className="mt-2.5 flex items-center gap-1.5">
          <Button size="sm" onClick={onConfirm} disabled={running || blocked}>
            {running ? (
              <>
                <Loader2 className="animate-spin" />
                {t("assistant.working")}
              </>
            ) : (
              t("assistant.confirm")
            )}
          </Button>
          <Button
            size="sm"
            variant="ghost"
            onClick={onDismiss}
            disabled={running || blocked}
          >
            {t("assistant.dismiss")}
          </Button>
        </div>
      )}
    </div>
  );
}

/**
 * Renders an answer's plain text.
 *
 * The assistant writes lists as "• " lines. Rendering those as real list items rather
 * than as one pre-wrapped block is what gives a wrapped task title a hanging
 * indent instead of starting again under the bullet — which matters more here
 * than it did in a wide modal.
 */
function AnswerText({ text }: { text: string }) {
  const blocks: React.ReactNode[] = [];
  let bullets: string[] = [];
  let lines: string[] = [];

  // Consecutive plain lines become one paragraph, so a run of short facts sits
  // on tight leading instead of being spaced apart like separate answers.
  const flushLines = () => {
    if (lines.length === 0) return;
    blocks.push(
      <p key={`p-${blocks.length}`} className="whitespace-pre-wrap">
        {lines.join("\n")}
      </p>,
    );
    lines = [];
  };

  const flushBullets = () => {
    if (bullets.length === 0) return;
    blocks.push(
      <ul key={`list-${blocks.length}`} className="flex flex-col gap-1">
        {bullets.map((item, index) => (
          <li key={index} className="flex gap-1.5">
            <span aria-hidden className="select-none text-muted-foreground">
              •
            </span>
            <span className="min-w-0">{item}</span>
          </li>
        ))}
      </ul>,
    );
    bullets = [];
  };

  for (const line of text.split("\n")) {
    if (line.startsWith("• ")) {
      flushLines();
      bullets.push(line.slice(2));
      continue;
    }
    flushBullets();
    if (line.trim() === "") {
      flushLines();
      continue;
    }
    lines.push(line);
  }
  flushBullets();
  flushLines();

  return <div className="flex flex-col gap-2">{blocks}</div>;
}

function Thinking() {
  const { t } = useI18n();
  return (
    <div className="flex items-center gap-2" aria-live="polite">
      <span
        aria-hidden
        className="flex size-5 shrink-0 items-center justify-center rounded-xl bg-muted"
      >
        <Sparkles className="size-2.5" />
      </span>
      <span className="flex items-center gap-1 rounded-3xl bg-card shadow-[var(--shadow-xs)] px-3.5 py-3">
        {[0, 1, 2].map((dot) => (
          <span
            key={dot}
            className="size-1.5 animate-pulse rounded-full bg-muted-foreground"
            style={{ animationDelay: `${dot * 160}ms` }}
          />
        ))}
        <span className="sr-only">{t("assistant.thinking")}</span>
      </span>
    </div>
  );
}
