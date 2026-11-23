"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { BellRing, Loader2, Smartphone, X } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { forgetDevice, registerDevice } from "@/lib/data/push-actions";
import { useI18n } from "@/lib/i18n/client";
import type { PushDevice } from "@/lib/supabase/database.types";

/**
 * Notifications on the device you are holding.
 *
 * Push is per-device, not per-person: saying yes on the phone must not make
 * the laptop buzz, and turning the phone off must leave the laptop alone. So
 * this lists the devices rather than offering one switch, and the switch it
 * does offer is always about *this* one.
 *
 * On iOS none of this exists until the app is on the home screen — Safari
 * only grants push to an installed web app. Rather than showing a control
 * that silently does nothing, the reason is said out loud.
 */
export function PushDevices({
  devices,
  publicKey,
}: {
  devices: PushDevice[];
  publicKey: string | null;
}) {
  const router = useRouter();
  const { t, tm, tag } = useI18n();
  const [busy, setBusy] = React.useState(false);
  const [endpoint, setEndpoint] = React.useState<string | null>(null);
  const [supported, setSupported] = React.useState<boolean | null>(null);
  const [needsInstall, setNeedsInstall] = React.useState(false);

  // What this browser can do, and what it has already agreed to.
  React.useEffect(() => {
    const canPush =
      "serviceWorker" in navigator &&
      "PushManager" in window &&
      "Notification" in window;
    setSupported(canPush);

    // iOS grants push only to a web app that has been added to the home
    // screen. `standalone` is the flag for that, and it is Safari's own.
    const iOS = /iPad|iPhone|iPod/.test(navigator.userAgent);
    const standalone =
      window.matchMedia("(display-mode: standalone)").matches ||
      (window.navigator as { standalone?: boolean }).standalone === true;
    setNeedsInstall(iOS && !standalone);

    if (!canPush) return;
    navigator.serviceWorker.ready
      .then((registration) => registration.pushManager.getSubscription())
      .then((subscription) => setEndpoint(subscription?.endpoint ?? null))
      .catch(() => setEndpoint(null));
  }, []);

  const here = endpoint !== null && devices.some((device) => device.endpoint === endpoint);

  async function turnOn() {
    if (!publicKey) return;
    setBusy(true);
    try {
      const permission = await Notification.requestPermission();
      if (permission !== "granted") {
        toast.error(t("push.refused"));
        return;
      }

      const registration = await navigator.serviceWorker.ready;
      const subscription = await registration.pushManager.subscribe({
        // Every push shows a notification. Anything else is a site quietly
        // running code on somebody's phone, and browsers revoke permission
        // for it.
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(publicKey),
      });

      const keys = subscription.toJSON().keys ?? {};
      const outcome = await registerDevice({
        endpoint: subscription.endpoint,
        p256dh: keys.p256dh ?? "",
        auth: keys.auth ?? "",
        userAgent: navigator.userAgent,
      });

      if (!outcome.ok) {
        toast.error(tm(outcome.error));
        return;
      }

      setEndpoint(subscription.endpoint);
      toast.success(t("push.on"));
      router.refresh();
    } catch {
      toast.error(t("push.failed"));
    } finally {
      setBusy(false);
    }
  }

  async function forget(target: string) {
    setBusy(true);
    try {
      // Unsubscribing in the browser as well, when it is this one: leaving
      // the browser subscribed means it keeps a permission the app no longer
      // has a row for.
      if (target === endpoint) {
        const registration = await navigator.serviceWorker.ready;
        const subscription = await registration.pushManager.getSubscription();
        await subscription?.unsubscribe();
        setEndpoint(null);
      }

      const outcome = await forgetDevice(target);
      if (!outcome.ok) {
        toast.error(tm(outcome.error));
        return;
      }
      router.refresh();
    } catch {
      toast.error(t("push.failed"));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="rounded-2xl bg-foreground/[0.05] p-3">
      <div className="flex items-start gap-3">
        <span className="mt-0.5 text-muted-foreground [&_svg]:size-4">
          <BellRing />
        </span>
        <div className="flex min-w-0 flex-1 flex-col gap-2">
          <div>
            <p className="text-sm font-medium">{t("push.title")}</p>
            <p className="text-xs text-muted-foreground">{t("push.subtitle")}</p>
          </div>

          {devices.length > 0 && (
            <ul className="flex flex-col gap-1.5">
              {devices.map((device) => (
                <li
                  key={device.endpoint}
                  className="flex items-center justify-between gap-2 rounded-md bg-muted/50 px-2.5 py-1.5"
                >
                  <span className="flex min-w-0 items-center gap-2">
                    <Smartphone className="size-3.5 shrink-0 text-muted-foreground" />
                    <span className="min-w-0">
                      <span className="block truncate text-xs font-medium">
                        {describe(device.user_agent)}
                        {device.endpoint === endpoint && ` · ${t("push.thisDevice")}`}
                      </span>
                      <span className="block truncate text-[0.6875rem] text-muted-foreground">
                        {new Date(device.created_at).toLocaleDateString(tag, {
                          day: "numeric",
                          month: "long",
                          year: "numeric",
                        })}
                      </span>
                    </span>
                  </span>
                  <Button
                    type="button"
                    variant="ghost"
                    size="icon-sm"
                    disabled={busy}
                    onClick={() => forget(device.endpoint)}
                    aria-label={t("push.forget")}
                  >
                    <X />
                  </Button>
                </li>
              ))}
            </ul>
          )}

          {supported === false ? (
            <p className="text-xs text-muted-foreground">{t("push.unsupported")}</p>
          ) : needsInstall ? (
            <p className="text-xs text-muted-foreground">{t("push.installFirst")}</p>
          ) : !publicKey ? (
            <p className="text-xs text-muted-foreground">{t("push.unavailable")}</p>
          ) : here ? (
            <p className="text-xs text-muted-foreground">{t("push.alreadyOn")}</p>
          ) : (
            <Button
              type="button"
              variant="outline"
              size="sm"
              className="self-start"
              disabled={busy || supported === null}
              onClick={turnOn}
            >
              {busy && <Loader2 className="animate-spin" />}
              {t("push.turnOn")}
            </Button>
          )}
        </div>
      </div>
    </div>
  );
}

/** Something a person recognises, out of a user-agent string. */
function describe(userAgent: string | null): string {
  if (!userAgent) return "Device";
  if (/iPhone/.test(userAgent)) return "iPhone";
  if (/iPad/.test(userAgent)) return "iPad";
  if (/Android/.test(userAgent)) return "Android";
  if (/Macintosh/.test(userAgent)) return "Mac";
  if (/Windows/.test(userAgent)) return "Windows";
  if (/Linux/.test(userAgent)) return "Linux";
  return "Device";
}

/**
 * The key, as `pushManager.subscribe` wants it.
 *
 * VAPID keys travel as base64url; the API takes bytes. Padding has to be put
 * back before decoding, and the two URL-safe characters swapped out.
 */
function urlBase64ToUint8Array(base64: string): ArrayBuffer {
  const padded = base64.padEnd(base64.length + ((4 - (base64.length % 4)) % 4), "=");
  const standard = padded.replace(/-/g, "+").replace(/_/g, "/");
  const raw = atob(standard);
  const buffer = new ArrayBuffer(raw.length);
  const output = new Uint8Array(buffer);
  for (let i = 0; i < raw.length; i += 1) output[i] = raw.charCodeAt(i);
  return buffer;
}
