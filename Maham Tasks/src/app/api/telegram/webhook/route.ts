import { NextResponse, type NextRequest } from "next/server";

import { createAdminClient } from "@/lib/supabase/admin";
import { isMissingFunction, isMissingTable } from "@/lib/supabase/missing";
import { parseQuickAdd } from "@/lib/telegram/quick-add";

/**
 * Telegram bot webhook: linking an account, and adding work from the chat.
 *
 * Linking: a user generates a code in their profile and sends "/start <code>"
 * to the bot. Telegram delivers the chat id here, which is the piece the app
 * cannot discover on its own. The code is single-use and is cleared once
 * redeemed, so a leaked code cannot be replayed to redirect someone's
 * reminders.
 *
 * Adding: once a chat is linked, anything else sent to the bot is added as
 * that person's — a task for a planner, an item in My List for a member
 * (add_from_chat, migration 42). Only a linked chat can add anything, and
 * only as the person who linked it.
 *
 * Telegram authenticates the webhook with a secret token header set when the
 * webhook is registered.
 */

export const dynamic = "force-dynamic";

type TelegramUpdate = {
  message?: {
    text?: string;
    chat?: { id?: number };
  };
};

const LINK_FIRST =
  "Open your profile in the Almailgroup Task Portal, choose Telegram reminders, and send me the code it shows.\n\n" +
  "افتح ملفك الشخصي في بوابة مهام Almailgroup، واختر تذكيرات تيليجرام، وأرسل لي الرمز الذي يظهر.";

const HELP =
  "Send me anything to add it to your list. The first line is the title; anything after it is the detail.\n" +
  "• Start with ! to make it high priority.\n" +
  "• End with today or tomorrow to set when it is due.\n\n" +
  "أرسل لي أي شيء لإضافته إلى قائمتك. السطر الأول هو العنوان، وما بعده تفاصيل.\n" +
  "• ابدأ بعلامة ! لأولوية عالية.\n" +
  "• اختم بكلمة اليوم أو باچر لتحديد موعد الاستحقاق.";

const NOT_YET = "Adding work from Telegram is not switched on yet: the database needs its latest update.";

export async function POST(request: NextRequest) {
  const expected = process.env.TELEGRAM_WEBHOOK_SECRET;
  const provided = request.headers.get("x-telegram-bot-api-secret-token");

  if (!expected || provided !== expected) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const update = (await request.json().catch(() => null)) as TelegramUpdate | null;
  const text = update?.message?.text?.trim() ?? "";
  const chatId = update?.message?.chat?.id;

  if (!chatId || !text) return NextResponse.json({ ok: true });

  const supabase = createAdminClient();

  const link = text.match(/^\/start\s+([A-Za-z0-9]{6,32})$/);
  if (link) {
    await linkChat(supabase, chatId, link[1]);
    return NextResponse.json({ ok: true });
  }

  // Any other command — /start, /help — is a question about what to do.
  if (text.startsWith("/")) {
    const { data: linked } = await supabase
      .from("notification_preferences")
      .select("user_id")
      .eq("telegram_chat_id", String(chatId))
      .maybeSingle();
    await reply(chatId, linked ? HELP : LINK_FIRST);
    return NextResponse.json({ ok: true });
  }

  const item = parseQuickAdd(text, new Date(), await upcomingHolidays(supabase));
  if (!item) {
    await reply(chatId, HELP);
    return NextResponse.json({ ok: true });
  }

  const { data, error } = await supabase.rpc("add_from_chat", {
    chat: String(chatId),
    item_title: item.title,
    item_detail: item.detail,
    item_priority: item.priority,
    due: item.dueAt,
  });

  if (error) {
    if (isMissingFunction(error)) {
      await reply(chatId, NOT_YET);
    } else {
      console.error(`[telegram] add_from_chat: ${error.message}`);
      await reply(chatId, "That could not be added just now. Try again in a moment.");
    }
    return NextResponse.json({ ok: true });
  }

  const added = data as { kind: "task" | "note"; id: string } | null;
  if (!added) {
    await reply(chatId, LINK_FIRST);
    return NextResponse.json({ ok: true });
  }

  const site = process.env.NEXT_PUBLIC_SITE_URL ?? "";
  const due = item.dueAt
    ? ` — due ${new Date(item.dueAt).toLocaleString("en-GB", {
        timeZone: "Asia/Kuwait",
        weekday: "short",
        day: "numeric",
        month: "short",
        hour: "2-digit",
        minute: "2-digit",
      })}`
    : "";
  await reply(
    chatId,
    added.kind === "task"
      ? `Added to your tasks: ${item.title}${due}${site ? `\n${site}/tasks?filter=all&task=${added.id}` : ""}`
      : `Added to My List: ${item.title}${site ? `\n${site}/my-list` : ""}`,
  );

  return NextResponse.json({ ok: true });
}

type Admin = ReturnType<typeof createAdminClient>;

async function linkChat(supabase: Admin, chatId: number, code: string) {
  const { data: profileRow } = await supabase
    .from("notification_preferences")
    .select("user_id")
    .eq("telegram_link_code", code)
    .maybeSingle();

  if (!profileRow) {
    await reply(chatId, "That code is not valid or has already been used.");
    return;
  }

  const { error } = await supabase
    .from("notification_preferences")
    .update({
      telegram_chat_id: String(chatId),
      telegram_enabled: true,
      telegram_link_code: null,
    })
    .eq("user_id", profileRow.user_id);

  await reply(
    chatId,
    error
      ? "Something went wrong linking this chat. Try generating a new code."
      : `Linked. You will get your task reminders here.\n\n${HELP}`,
  );
}

/** The next few weeks' company holidays, so "tomorrow" skips them. */
async function upcomingHolidays(supabase: Admin): Promise<Set<string>> {
  const from = new Date().toISOString().slice(0, 10);
  const to = new Date(Date.now() + 30 * 86_400_000).toISOString().slice(0, 10);
  const { data, error } = await supabase
    .from("company_holidays")
    .select("day")
    .gte("day", from)
    .lte("day", to);
  if (error && !isMissingTable(error)) console.error(`[telegram] holidays: ${error.message}`);
  return new Set((data ?? []).map((row) => row.day));
}

async function reply(chatId: number, text: string) {
  const token = process.env.TELEGRAM_BOT_TOKEN;
  if (!token) return;

  await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ chat_id: chatId, text }),
  }).catch(() => undefined);
}
