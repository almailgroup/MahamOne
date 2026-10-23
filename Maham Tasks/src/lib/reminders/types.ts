/** One queued message, as the dispatcher sees it. */
export type QueuedReminder = {
  id: string;
  user_id: string;
  task_id: string | null;
  channel: "email" | "telegram" | "whatsapp" | "push";
  kind: "assigned" | "due_soon" | "overdue" | "follow_up" | "summary";
  recipient: string;
  subject: string | null;
  body: string;
  attempts: number;
};

/**
 * What a provider reports back.
 *
 * `retryable` separates a transient failure (rate limit, provider down) from a
 * permanent one (bad number, template rejected). Only the first is worth
 * another attempt; retrying the second forever would just fill the queue.
 */
export type DeliveryResult =
  | { ok: true; detail?: string }
  /**
   * `gone` is the third answer, and only push gives it: the push service
   * saying this device no longer exists. An address that bounces might come
   * back; a device that has been wiped will not, and the row for it should
   * go rather than sit in the queue being retried.
   */
  | { ok: false; error: string; retryable: boolean; gone?: boolean };

export type Channel = QueuedReminder["channel"];
