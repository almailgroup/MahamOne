"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { ChevronDown, Loader2, Megaphone, Trash2 } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import {
  postStatusUpdate,
  withdrawStatusUpdate,
} from "@/lib/data/project-status-actions";
import { formatDateTime, relativeDay } from "@/lib/dates";
import { useI18n } from "@/lib/i18n/client";
import { cn } from "@/lib/utils";
import type {
  ProjectStatus,
  ProjectStatusUpdateWithAuthor,
} from "@/lib/supabase/database.types";

const STATUSES: ProjectStatus[] = ["on_track", "at_risk", "off_track"];

/**
 * How the project is going, in the words of whoever runs it.
 *
 * The pulse below this says what the board says. This says what the person
 * responsible says — and the two disagreeing is itself worth seeing, which
 * is why they sit next to each other.
 *
 * Monochrome on track, amber otherwise. Amber in this app means "late or
 * urgent work" and nothing else, and a project its owner calls at risk is
 * exactly that; one that is on track is not news.
 */
export function ProjectStatus({
  projectId,
  updates,
  canPost,
  meId,
  isAdmin,
}: {
  projectId: string;
  /** Null when they could not be loaded, which is not the same as none. */
  updates: ProjectStatusUpdateWithAuthor[] | null;
  /** A manager or admin on a live project. */
  canPost: boolean;
  meId: string;
  isAdmin: boolean;
}) {
  const i18n = useI18n();
  const { t } = i18n;
  const router = useRouter();

  const [writing, setWriting] = React.useState(false);
  const [status, setStatus] = React.useState<ProjectStatus>("on_track");
  const [body, setBody] = React.useState("");
  const [busy, setBusy] = React.useState(false);
  const [showEarlier, setShowEarlier] = React.useState(false);

  if (updates === null) {
    return (
      <p className="rounded-3xl bg-card shadow-[var(--shadow-xs)] px-4 py-3 text-xs text-muted-foreground">
        {t("health.unavailable")}
      </p>
    );
  }

  const [latest, ...earlier] = updates;

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (!body.trim() || busy) return;
    setBusy(true);
    const outcome = await postStatusUpdate(projectId, { status, body });
    setBusy(false);
    if (!outcome.ok) {
      toast.error(i18n.tm(Object.values(outcome.fieldErrors ?? {})[0] ?? outcome.error));
      return;
    }
    toast.success(t("health.posted"));
    setWriting(false);
    setBody("");
    router.refresh();
  }

  async function withdraw(id: string) {
    const outcome = await withdrawStatusUpdate(id, projectId);
    if (!outcome.ok) {
      toast.error(i18n.tm(outcome.error));
      return;
    }
    toast.success(t("health.withdrawn"));
    router.refresh();
  }

  const byline = (update: ProjectStatusUpdateWithAuthor) =>
    t("health.by", {
      name: update.author?.full_name ?? update.author?.email ?? "—",
      when: relativeDay(update.created_at, i18n),
    });

  const canWithdraw = (update: ProjectStatusUpdateWithAuthor) =>
    isAdmin || update.author_id === meId;

  return (
    <section
      aria-label={t("health.title")}
      className="flex flex-col gap-3 rounded-[1.75rem] bg-card px-5 py-4 shadow-[var(--shadow-xs)]"
    >
      <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
        <span className="text-xs font-medium text-muted-foreground">
          {t("health.title")}
        </span>
        {latest && <StatusPill status={latest.status} />}
        {latest && (
          <time
            dateTime={latest.created_at}
            title={formatDateTime(latest.created_at, i18n.tag, i18n.timeZone)}
            className="text-xs text-muted-foreground"
          >
            {byline(latest)}
          </time>
        )}
        {canPost && !writing && (
          <Button
            type="button"
            variant="outline"
            size="sm"
            className="ms-auto"
            onClick={() => setWriting(true)}
          >
            <Megaphone />
            {t("health.post")}
          </Button>
        )}
      </div>

      {latest ? (
        <UpdateBody
          update={latest}
          onWithdraw={canWithdraw(latest) ? () => withdraw(latest.id) : undefined}
        />
      ) : (
        !writing && (
          <p className="text-sm text-muted-foreground">
            {t("health.none")}
            {canPost && (
              <span className="mt-0.5 block text-xs">{t("health.noneHint")}</span>
            )}
          </p>
        )
      )}

      {writing && (
        <form onSubmit={submit} className="flex flex-col gap-2 pt-3">
          <div
            role="radiogroup"
            aria-label={t("health.pick")}
            className="flex flex-wrap gap-1.5"
          >
            {STATUSES.map((option) => (
              <button
                key={option}
                type="button"
                role="radio"
                aria-checked={status === option}
                onClick={() => setStatus(option)}
                className={cn(
                  "rounded-full px-3 py-1.5 text-xs font-medium transition-colors",
                  "pointer-coarse:min-h-10",
                  status === option
                    ? option === "on_track"
                      ? "bg-foreground text-background"
                      : option === "at_risk"
                        ? "bg-warning-surface text-warning"
                        : "bg-warning text-background"
                    : "bg-foreground/[0.06] text-muted-foreground hover:bg-accent hover:text-foreground",
                )}
              >
                {t(`health.${option}`)}
              </button>
            ))}
          </div>
          <Textarea
            value={body}
            onChange={(event) => setBody(event.target.value)}
            placeholder={t("health.placeholder")}
            aria-label={t("health.placeholder")}
            maxLength={2000}
            rows={3}
            autoFocus
          />
          <div className="flex justify-end gap-2">
            <Button
              type="button"
              variant="ghost"
              size="sm"
              onClick={() => {
                setWriting(false);
                setBody("");
              }}
            >
              {t("common.cancel")}
            </Button>
            <Button type="submit" size="sm" disabled={busy || !body.trim()}>
              {busy && <Loader2 className="animate-spin" />}
              {t("health.submit")}
            </Button>
          </div>
        </form>
      )}

      {earlier.length > 0 && (
        <div className="pt-2">
          <button
            type="button"
            onClick={() => setShowEarlier((open) => !open)}
            aria-expanded={showEarlier}
            className="flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground"
          >
            <ChevronDown
              className={cn("size-3.5 transition-transform", showEarlier && "rotate-180")}
            />
            {t("health.earlier", { n: earlier.length })}
          </button>
          {showEarlier && (
            <ol className="mt-2 flex flex-col gap-3">
              {earlier.map((update) => (
                <li key={update.id} className="flex flex-col gap-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <StatusPill status={update.status} />
                    <time
                      dateTime={update.created_at}
                      title={formatDateTime(update.created_at, i18n.tag, i18n.timeZone)}
                      className="text-xs text-muted-foreground"
                    >
                      {byline(update)}
                    </time>
                  </div>
                  <UpdateBody
                    update={update}
                    onWithdraw={canWithdraw(update) ? () => withdraw(update.id) : undefined}
                  />
                </li>
              ))}
            </ol>
          )}
        </div>
      )}
    </section>
  );
}

function UpdateBody({
  update,
  onWithdraw,
}: {
  update: ProjectStatusUpdateWithAuthor;
  onWithdraw?: () => void;
}) {
  const { t } = useI18n();
  return (
    <div className="group flex items-start gap-2">
      <p className="min-w-0 flex-1 whitespace-pre-wrap break-words text-sm leading-relaxed">
        {update.body}
      </p>
      {onWithdraw && (
        <Button
          type="button"
          variant="ghost"
          size="icon-sm"
          onClick={onWithdraw}
          aria-label={t("health.withdraw")}
          title={t("health.withdraw")}
          className="shrink-0 opacity-0 transition-opacity focus-visible:opacity-100 group-hover:opacity-100 pointer-coarse:opacity-100"
        >
          <Trash2 />
        </Button>
      )}
    </div>
  );
}

/**
 * On track is grey on purpose. The one colour in this palette is for late
 * and urgent work; at risk is that, and off track is more of it.
 */
export function StatusPill({
  status,
  className,
}: {
  status: ProjectStatus;
  className?: string;
}) {
  const { t } = useI18n();
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-medium",
        status === "on_track" && "bg-muted text-foreground",
        status === "at_risk" &&" bg-warning-surface text-warning",
        status === "off_track" && "bg-warning text-background",
        className,
      )}
    >
      <span
        aria-hidden
        className={cn(
          "size-1.5 rounded-full",
          status === "on_track" && "bg-foreground/50",
          status === "at_risk" && "bg-warning",
          status === "off_track" && "bg-background",
        )}
      />
      {t(`health.${status}`)}
    </span>
  );
}
