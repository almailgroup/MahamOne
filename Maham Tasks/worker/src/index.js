/**
 * The assistant's language model, kept off the app server.
 *
 * The portal sends the question and a snapshot of the board the asker is
 * allowed to see; this forwards both to Gemini and returns the answer. It
 * exists for one reason: the Gemini key lives here, as a Cloudflare secret,
 * and never goes near Vercel — where anything is one `NEXT_PUBLIC_` typo away
 * from the browser.
 *
 * It is server-to-server only. There is deliberately no CORS header, so a page
 * cannot call it directly even if somebody learns the address.
 *
 * Plain JavaScript, and nothing is imported, so this file is exactly what goes
 * into Cloudflare's browser editor — copy it whole. The types below are JSDoc,
 * which is a comment at runtime and still checked against the portal's own
 * definitions by `npm run typecheck`.
 *
 * @typedef {import("../../src/lib/assistant/types").AssistantMessage} AssistantMessage
 * @typedef {import("../../src/lib/assistant/types").AssistantSnapshot} AssistantSnapshot
 *
 * @typedef {object} Env
 * @property {string}  GEMINI_API_KEY  From Google AI Studio. A secret.
 * @property {string} [SHARED_SECRET]  Shared with the portal. A secret.
 * @property {string} [GEMINI_MODEL]   Plain text; model names come and go.
 */

/**
 * Overridden by the GEMINI_MODEL variable. A Flash model, because those are
 * the ones the free tier carries; `models?key=…` will list what a given key
 * can see, though seeing a model is not the same as it being free.
 */
const DEFAULT_MODEL = "gemini-3.8-flash";

/**
 * What the assistant may propose.
 *
 * "Propose" is the whole design: this Worker has no database, no Supabase
 * credentials and no way to reach either. A tool call comes back here as
 * JSON, travels to the portal, is shown to the person who asked, and only
 * runs — through the Server Action the ordinary buttons use — once they
 * agree. Every permission check in the app therefore still applies, and the
 * assistant can never do anything the asker could not do by hand.
 */
const TOOLS = [
  {
    functionDeclarations: [
      {
        name: "create_task",
        description:
          "Propose a new task. Use when the person asks for work to be added. " +
          "Leave anything they did not say unset rather than inventing it.",
        parameters: {
          type: "object",
          properties: {
            title: { type: "string", description: "Short, what needs doing." },
            description: { type: "string", description: "Detail, only if given." },
            projectId: {
              type: "string",
              description:
                "Which project, from the list of projects. Omit for a general task.",
            },
            assigneeIds: {
              type: "array",
              items: { type: "string" },
              description: "Who does it, by id, from the team list.",
            },
            dueAt: {
              type: "string",
              description:
                "Due date and time as a full ISO instant, e.g. 2026-09-20T13:00:00.000Z. " +
                "Work it out from the reader's timezone given above.",
            },
            priority: {
              type: "string",
              enum: ["low", "medium", "high", "urgent"],
            },
            status: {
              type: "string",
              enum: ["todo", "in_progress", "in_review", "done"],
            },
          },
          required: ["title"],
        },
      },
      {
        name: "set_task_status",
        description: "Propose moving one task to another status.",
        parameters: {
          type: "object",
          properties: {
            taskId: { type: "string", description: "The id from the board." },
            status: {
              type: "string",
              enum: ["todo", "in_progress", "in_review", "done"],
            },
          },
          required: ["taskId", "status"],
        },
      },
      {
        name: "reschedule_task",
        description:
          "Propose a new due date for one task, or clear it by omitting dueAt.",
        parameters: {
          type: "object",
          properties: {
            taskId: { type: "string", description: "The id from the board." },
            dueAt: {
              type: "string",
              description:
                "The new due instant in ISO form. Omit entirely to remove the due date.",
            },
          },
          required: ["taskId"],
        },
      },
    ],
  },
];

/** Enough board to answer from, small enough to stay inside the free tier. */
const MAX_TASKS = 200;
/** Enough conversation to follow a thread, without resending an hour of it. */
const MAX_TURNS = 12;
/**
 * Under the 20s the portal waits, so it falls back rather than hanging. This
 * is the budget for the whole call including a retry, not for each attempt.
 */
const TIMEOUT_MS = 15_000;
/** One retry. A second one would not fit inside the budget above. */
const ATTEMPTS = 2;
/** Long enough for a busy model to come free, short enough not to be felt. */
const RETRY_PAUSE_MS = 700;
/**
 * Statuses where the model was busy rather than the request wrong. A free-tier
 * Flash model returns 503 often enough that one ask succeeding and the next
 * failing twenty seconds later is its ordinary behaviour, not a fault.
 */
const RETRYABLE = new Set([429, 500, 502, 503, 504]);

export default {
  /**
   * @param {Request} request
   * @param {Env} env
   * @returns {Promise<Response>}
   */
  async fetch(request, env) {
    if (request.method !== "POST") {
      return json({ error: "Use POST." }, 405);
    }
    if (!authorised(request, env)) {
      return json({ error: "Not authorised." }, 401);
    }
    if (!env.GEMINI_API_KEY) {
      console.error("GEMINI_API_KEY is not set on this Worker.");
      return json({ error: "Not configured." }, 500);
    }

    /** @type {{ messages?: AssistantMessage[], snapshot?: AssistantSnapshot }} */
    let body;
    try {
      body = await request.json();
    } catch {
      return json({ error: "Expected JSON." }, 400);
    }

    const { messages, snapshot } = body;
    if (!Array.isArray(messages) || messages.length === 0 || !snapshot?.counts) {
      return json({ error: "Expected { messages, snapshot }." }, 400);
    }

    try {
      const { text, action } = await ask(messages, snapshot, env);
      return json({ text, action });
    } catch (error) {
      // The portal answers from its own local brain on any non-2xx, so the
      // panel degrades to a worse answer rather than to an error. The reason
      // belongs in `wrangler tail`, not in front of whoever asked.
      // The reason, not the Error: Cloudflare's Events list summarises a
      // thrown Error as its stack, which puts "at ask (worker.js:257)" in the
      // one line you can actually see and hides the status and Gemini's own
      // words behind a click. The stack was never the interesting half.
      console.error("Gemini call failed:", reasonOf(error));
      // The caller is the portal's own server, never a browser, so the reason
      // can travel: it ends up in the Vercel log, which is where somebody is
      // already looking when they wonder why the assistant went quiet.
      return json({ error: "Upstream failed.", reason: reasonOf(error) }, 502);
    }
  },
};

/**
 * The shared secret, compared in constant time.
 *
 * A plain `===` on a secret leaks its prefix through how long the comparison
 * takes. The cost of doing it properly is nothing, so there is no reason to
 * take the argument that this one is hard to exploit over the internet.
 *
 * No secret means no service. It would be friendlier to run open until one is
 * set, and that is exactly the window — between `wrangler deploy` and
 * `wrangler secret put` — in which an address that spends somebody's Gemini
 * quota sits on the internet waiting to be found.
 *
 * @param {Request} request
 * @param {Env} env
 * @returns {boolean}
 */
function authorised(request, env) {
  if (!env.SHARED_SECRET) {
    console.error(
      "SHARED_SECRET is not set, so every request is refused. Set it with:\n" +
        "  npx wrangler secret put SHARED_SECRET",
    );
    return false;
  }
  const offered = (request.headers.get("authorization") ?? "").replace(/^Bearer /i, "");
  const a = new TextEncoder().encode(offered);
  const b = new TextEncoder().encode(env.SHARED_SECRET);
  if (a.byteLength !== b.byteLength) return false;
  if (crypto.subtle.timingSafeEqual) return crypto.subtle.timingSafeEqual(a, b);
  // Same idea by hand: every byte is compared, and the loop cannot finish
  // early on a mismatch the way `every` would.
  let difference = 0;
  for (let i = 0; i < a.length; i += 1) difference |= a[i] ^ b[i];
  return difference === 0;
}

/**
 * @param {AssistantMessage[]} messages
 * @param {AssistantSnapshot} snapshot
 * @param {Env} env
 * @returns {Promise<{ text: string, action: { name: string, arguments: Record<string, unknown> } | null }>}
 */
async function ask(messages, snapshot, env) {
  const model = env.GEMINI_MODEL || DEFAULT_MODEL;
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;

  const payload = JSON.stringify({
    systemInstruction: { parts: [{ text: brief(snapshot) }] },
    // A member cannot create or change a task by hand, so the assistant is
    // not offered the means to propose it for them. The database would
    // refuse it anyway; not offering it is the difference between a clear
    // "you cannot" and a confusing failure.
    ...(snapshot.viewer?.canManage ? { tools: TOOLS } : {}),
    // A turn that only proposed something carries no prose, and a part with
    // no text in it is not worth sending back as history.
    contents: messages
      .slice(-MAX_TURNS)
      .filter((message) => message.text && message.text.trim())
      .map((message) => ({
        role: message.role === "assistant" ? "model" : "user",
        parts: [{ text: message.text }],
      })),
    generationConfig: {
      // Low, not zero: this is a question about facts on a board, and the
      // answer should not drift between two identical asks.
      temperature: 0.2,
      /**
       * Far more than an answer needs, because on these models the budget
       * covers the reasoning as well. At 900 a model can think its way
       * through the whole allowance and stop before writing a word, which
       * arrives here as a perfectly successful response with no text in it.
       * The answer itself stays short; the system prompt asks for that.
       */
      maxOutputTokens: 4096,
    },
  });

  /**
   * One budget for the whole call, shared by both attempts, so a retry can
   * never push past the 20 seconds the portal is prepared to wait. A single
   * signal created here aborts whichever attempt is in flight when it fires.
   */
  const deadline = AbortSignal.timeout(TIMEOUT_MS);

  let failure = "";
  for (let attempt = 1; attempt <= ATTEMPTS; attempt += 1) {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        // In a header rather than the query string: URLs turn up in logs.
        "x-goog-api-key": env.GEMINI_API_KEY,
      },
      body: payload,
      signal: deadline,
    });

    if (response.ok) return read(await response.json());

    const detail = await response.text();
    failure = `Gemini replied ${response.status}${
      attempt > 1 ? " twice" : ""
    }: ${detail}`;

    // A wrong key, a model that does not exist and a day's quota already spent
    // will all say exactly the same thing again. Only a busy model is worth
    // asking twice — and a per-day 429 is not a busy model, whatever its code.
    const busy =
      RETRYABLE.has(response.status) && !/PerDay/i.test(detail) && attempt < ATTEMPTS;
    if (!busy) break;

    console.warn(`Gemini replied ${response.status}; asking once more.`);
    await new Promise((resolve) => setTimeout(resolve, RETRY_PAUSE_MS));
  }

  throw new Error(failure);
}

/**
 * What Gemini said, turned into an answer and — perhaps — a proposal.
 *
 * @param {{
 *   candidates?: {
 *     content?: {
 *       parts?: {
 *         text?: string,
 *         thought?: boolean,
 *         functionCall?: { name?: string, args?: Record<string, unknown> },
 *       }[],
 *     },
 *     finishReason?: string,
 *   }[],
 *   promptFeedback?: { blockReason?: string },
 * }} data
 * @returns {{ text: string, action: { name: string, arguments: Record<string, unknown> } | null }}
 */
function read(data) {
  if (data.promptFeedback?.blockReason) {
    throw new Error(`Blocked: ${data.promptFeedback.blockReason}`);
  }

  const parts = data.candidates?.[0]?.content?.parts ?? [];

  const answer = parts
    // Newer models return their reasoning as parts too; those are not the answer.
    .filter((part) => !part.thought && typeof part.text === "string")
    .map((part) => part.text)
    .join("")
    .trim();

  const call = parts.find((part) => part.functionCall?.name)?.functionCall;
  const action = call
    ? { name: String(call.name), arguments: call.args ?? {} }
    : null;

  if (!answer && !action) {
    // Worth naming: an empty answer and a failed call look identical from the
    // portal, and the commonest cause — the reasoning eating the whole token
    // budget — is fixed by a number in this file rather than by retrying.
    throw new Error(
      `Gemini returned no text (finishReason: ${data.candidates?.[0]?.finishReason ?? "none"})`,
    );
  }

  return { text: answer, action };
}

/**
 * The words the board table is written in.
 *
 * The model copies what it is shown. Leave "in_review", "high priority" and
 * "Sep 17, 2026, 5:00 p.m." in the table and they come back out in the middle
 * of an Arabic sentence, because they are the only name it was given for the
 * thing. None of that is data — it is this file describing the board — so it
 * is written in whichever language the answer is.
 *
 * The Arabic is the portal's own wording, so the assistant and the interface
 * never call the same status two different things.
 */
const WORDS = {
  en: {
    date: "en-CA",
    status: {
      todo: "to do",
      in_progress: "in progress",
      in_review: "in review",
      done: "done",
    },
    priority: {
      low: "low priority",
      medium: "medium priority",
      high: "high priority",
      urgent: "urgent priority",
    },
    noDue: "no due date",
    general: "General",
    unassigned: "unassigned",
    followUp: "follow up",
    header: "id | title | status | priority | due | project | assignees",
    board: (/** @type {number} */ shown, /** @type {number} */ total) =>
      `The board (${shown} of ${total} tasks):`,
    more: (/** @type {number} */ n) =>
      `…and ${n} more not listed. Say so if it matters.`,
    projects: "Projects (id | name):",
    people: "People (id | name):",
  },
  ar: {
    // Kuwait, and Latin digits — the same numerals the rest of the portal
    // writes, so a date in an answer matches the date on the card.
    date: "ar-KW-u-nu-latn",
    status: {
      todo: "للتنفيذ",
      in_progress: "قيد التنفيذ",
      in_review: "قيد المراجعة",
      done: "منجزة",
    },
    priority: {
      low: "أولوية منخفضة",
      medium: "أولوية متوسطة",
      high: "أولوية عالية",
      urgent: "أولوية عاجلة",
    },
    noDue: "بدون موعد",
    general: "المهام العامة",
    unassigned: "غير مسندة",
    followUp: "متابعة",
    header: "المعرّف | العنوان | الحالة | الأولوية | الموعد | المشروع | المكلفون",
    board: (/** @type {number} */ shown, /** @type {number} */ total) =>
      `البورد (${shown} من ${total} مهمة):`,
    more: (/** @type {number} */ n) =>
      `…و${n} غيرها ما هي مذكورة. قل جذي إذا كان له دخل.`,
    projects: "المشاريع (المعرّف | الاسم):",
    people: "الناس (المعرّف | الاسم):",
  },
};

/**
 * How to answer somebody who wrote in Arabic.
 *
 * Kuwaiti, not Modern Standard: the people using this work together in an
 * office in Kuwait, and an assistant that replies in newsreader Arabic reads
 * as a form letter. A handful of markers is enough to place the dialect —
 * the last line matters as much as the list, because a model handed dialect
 * words will otherwise use every one of them in every sentence.
 *
 * Names are the exception. A task called "Ship the catalogue" is called that
 * on the board, and translating it means the reader cannot find it.
 */
const KUWAITI = [
  "Answer in Kuwaiti Arabic — the everyday spoken Arabic of Kuwait, not",
  "Modern Standard Arabic. Write the way a colleague in the office would say",
  "it: شنو rather than ماذا, شلون rather than كيف, وايد rather than كثير,",
  "هاللحين for now, باجر for tomorrow, ما في or ماكو for there is none, and",
  "راح or بـ for the future rather than سوف.",
  "Keep it natural and plain. Do not force dialect words in where they do not",
  "belong, and do not write a caricature — short, ordinary sentences.",
  "Everything you write is Arabic — every status, every priority, every date,",
  "every word joining them. The board below is already written in Arabic for",
  "you; use its words rather than the English ones you may know for them, and",
  "never leave an English word in an Arabic sentence because it came to mind",
  "first.",
  "The one exception is a name. Task titles, project names and people's names",
  "stay exactly as they are written on the board: the reader has to be able to",
  "find the thing you are talking about, and a translated title is not on any",
  "card. Do not transliterate them either.",
  "Numbers stay in Latin digits — 17, not ١٧ — as the rest of the portal",
  "writes them.",
]

/**
 * The board, written out for the model.
 *
 * Dates are resolved to the reader's own zone here rather than sent as
 * instants, because asking a language model to do timezone arithmetic is a
 * way of finding out that it cannot.
 *
 * @param {AssistantSnapshot} snapshot
 * @returns {string}
 */
function brief(snapshot) {
  const { viewer, counts, tasks, timeZone, locale, takenAt } = snapshot;
  // What the portal worked out from the question itself. An older portal does
  // not send it, and the interface language is the next best guess.
  const replyIn = snapshot.replyIn === "ar" || snapshot.replyIn === "en"
    ? snapshot.replyIn
    : locale === "ar"
      ? "ar"
      : "en";
  const projects = snapshot.projects ?? [];
  const team = snapshot.team ?? [];
  const words = WORDS[replyIn];
  // Month names rather than 17/09 — a model reading digits alone is one step
  // from doing arithmetic on them.
  const when = (/** @type {string | null} */ iso) =>
    iso
      ? new Intl.DateTimeFormat(words.date, {
          timeZone,
          day: "numeric",
          month: "long",
          year: "numeric",
          hour: "numeric",
          minute: "2-digit",
        }).format(new Date(iso))
      : words.noDue;

  const shown = tasks.slice(0, MAX_TASKS);
  const lines = shown.map((task) => {
    const bits = [
      task.id,
      task.title,
      words.status[task.status] ?? task.status,
      words.priority[task.priority] ?? task.priority,
      when(task.dueAt),
      task.project ?? words.general,
      task.assignees.length ? task.assignees.join("، ") : words.unassigned,
    ];
    if (task.followUpAt) bits.push(`${words.followUp} ${when(task.followUpAt)}`);
    return `- ${bits.join(" | ")}`;
  });

  /**
   * What it may do about what it reads.
   *
   * A member cannot create or change a task by hand, so they are told the
   * plain "no" and given no tools. A manager is told that acting is a
   * proposal somebody still has to agree to — otherwise the model writes as
   * though the job is finished, and the person reads "done" about something
   * sitting in front of them waiting for a click.
   */
  const powers = viewer.canManage
    ? [
        "- You can create a task, move one to another status, and change a due date,",
        "  by calling the matching tool. One at a time, and only when clearly asked.",
        "- Calling a tool does not do anything. It puts the change in front of the",
        "  reader to confirm, so say what you are proposing, never that it is done.",
        "- Use the ids exactly as they appear below — for the task, the project and",
        "  the person. Never invent one, and never guess at who or which project:",
        "  if they did not say, either leave it unset or ask.",
        "- Anything else — deleting, assigning on an existing task, projects, people —",
        "  you cannot do. Say so and point at where in the portal it lives.",
      ]
    : [
        "- You can read and count. You cannot create, edit, assign or delete anything;",
        "  if asked to, say so and describe where in the portal they can do it.",
      ];

  return [
    "You are the assistant inside the Almailgroup task portal. You answer questions",
    "about where work stands, from the board below and from nothing else.",
    "",
    ...(replyIn === "ar" ? KUWAITI : ["Answer in English."]),
    `The reader is ${viewer.name} (${viewer.role}). It is now ${when(takenAt)} in ${timeZone};`,
    "that clock decides what counts as today, overdue and this week.",
    "",
    "Rules:",
    "- Answer only from the board below. If it is not there, say you cannot see it.",
    "- Never invent a task, a person, a date or a number.",
    "- Be brief. Lead with the answer, then the tasks that support it.",
    "- Plain text only. No markdown, no headings, no ** or ##.",
    "- For a list, put each item on its own line starting with the bullet '• '.",
    "- Refer to tasks by their title, as the reader sees them. Ids are for tools.",
    ...powers,
    "",
    // The labels here are in the answer's language for the same reason the
    // board's are: whatever the model is shown is what it reaches for.
    "Counts already worked out for you — use these rather than recounting:",
    `${words.status.todo} ${counts.todo}, ${words.status.in_progress} ${counts.inProgress},`,
    `${words.status.in_review} ${counts.inReview}, ${words.status.done} ${counts.done},`,
    `${replyIn === "ar" ? "متأخرة" : "overdue"} ${counts.overdue},`,
    `${replyIn === "ar" ? "تستحق اليوم" : "due today"} ${counts.dueToday},`,
    `${words.unassigned} ${counts.unassigned}, ${words.noDue} ${counts.noDueDate},`,
    `${replyIn === "ar" ? "الإجمالي" : "total"} ${counts.total}.`,
    "",
    words.board(shown.length, tasks.length),
    words.header,
    ...lines,
    tasks.length > shown.length ? words.more(tasks.length - shown.length) : "",
    ...(viewer.canManage && projects.length
      ? ["", words.projects, ...projects.map((p) => `- ${p.id} | ${p.name}`)]
      : []),
    ...(viewer.canManage && team.length
      ? ["", words.people, ...team.map((p) => `- ${p.id} | ${p.name}`)]
      : []),
  ]
    .filter(Boolean)
    .join("\n");
}

/**
 * @param {unknown} body
 * @param {number} [status]
 * @returns {Response}
 */
/**
 * A failure in one short line, with anything key-shaped taken out — Google
 * does not echo the key back, but a log is a poor place to find out otherwise.
 *
 * @param {unknown} error
 * @returns {string}
 */
function reasonOf(error) {
  return String(error instanceof Error ? error.message : error)
    .replace(/AIza[0-9A-Za-z_-]{10,}/g, "[key]")
    .slice(0, 300);
}

/**
 * @param {unknown} body
 * @param {number} [status]
 * @returns {Response}
 */
function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}
