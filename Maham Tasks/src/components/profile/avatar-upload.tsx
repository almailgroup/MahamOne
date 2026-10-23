"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { Camera, Loader2, Trash2 } from "lucide-react";
import { toast } from "sonner";

import {
  Avatar,
  AvatarFallback,
  AvatarImage,
} from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { initialsFrom } from "@/lib/initials";
import { setOwnAvatar } from "@/lib/data/profile-actions";
import {
  AVATAR_BUCKET,
  AVATAR_MIME_TYPES,
  MAX_AVATAR_BYTES,
  avatarPath,
} from "@/lib/positions";
import { createClient } from "@/lib/supabase/client";
import { useI18n } from "@/lib/i18n/client";
import type { Profile } from "@/lib/supabase/database.types";

/**
 * Profile picture upload.
 *
 * The image goes straight from the browser to the public `avatars` bucket, and
 * only the resulting URL is written to the profile. The bucket is public
 * because avatars are rendered in lists throughout the app and signing each
 * one per request would be pure overhead for images carrying nothing sensitive.
 * Writes are still restricted to the owner's own folder.
 */
export function AvatarUpload({ profile }: { profile: Profile }) {
  const router = useRouter();
  const { t, tm } = useI18n();
  const supabase = React.useMemo(() => createClient(), []);
  const input = React.useRef<HTMLInputElement>(null);

  const [url, setUrl] = React.useState(profile.avatar_url);
  const [busy, setBusy] = React.useState(false);

  async function onPick(event: React.ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    event.target.value = ""; // Allow re-picking the same file after a failure.
    if (!file) return;

    if (!AVATAR_MIME_TYPES.includes(file.type)) {
      toast.error(t("avatar.badType"));
      return;
    }
    if (file.size > MAX_AVATAR_BYTES) {
      toast.error(t("avatar.tooBig"));
      return;
    }

    setBusy(true);
    const path = avatarPath(profile.id, file.name);

    const { error: uploadError } = await supabase.storage
      .from(AVATAR_BUCKET)
      .upload(path, file, { upsert: true, cacheControl: "3600" });

    if (uploadError) {
      setBusy(false);
      toast.error(t("avatar.uploadFailed"));
      return;
    }

    const {
      data: { publicUrl },
    } = supabase.storage.from(AVATAR_BUCKET).getPublicUrl(path);

    const outcome = await setOwnAvatar(publicUrl);
    setBusy(false);

    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }

    setUrl(publicUrl);
    toast.success(t("avatar.updated"));
    router.refresh();
  }

  async function onRemove() {
    setBusy(true);
    const outcome = await setOwnAvatar("");
    setBusy(false);

    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }

    setUrl(null);
    toast.success(t("avatar.removed"));
    router.refresh();
  }

  return (
    <div className="flex items-center gap-4">
      <Avatar className="size-16">
        {url && <AvatarImage src={url} alt="" />}
        <AvatarFallback className="text-base">
          {initialsFrom(profile.full_name, profile.email)}
        </AvatarFallback>
      </Avatar>

      <div className="flex flex-col gap-2">
        <div className="flex flex-wrap gap-2">
          <input
            ref={input}
            type="file"
            accept={AVATAR_MIME_TYPES.join(",")}
            hidden
            onChange={onPick}
          />
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={() => input.current?.click()}
            disabled={busy}
          >
            {busy ? <Loader2 className="animate-spin" /> : <Camera />}
            {url ? t("avatar.change") : t("avatar.upload")}
          </Button>

          {url && (
            <Button
              type="button"
              variant="ghost"
              size="sm"
              onClick={onRemove}
              disabled={busy}
            >
              <Trash2 />
              {t("avatar.remove")}
            </Button>
          )}
        </div>
        <p className="text-xs text-muted-foreground">
          {t("avatar.hint")}
        </p>
      </div>
    </div>
  );
}
