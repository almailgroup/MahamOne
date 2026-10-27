# AI assistant (first version)

Maham One has an AI assistant (المساعد الذكي) that answers questions about
using the app: where something is, how to record it, what a Kuwaiti rule
generally says. It answers in Arabic or English, in the language of the
question. This first version is deliberately small: it sees only what the
person types and which page they are on, never the company's records.

## Turning it on

1. The company must be kept in the cloud (Settings → Team → Keep in the
   cloud). A company kept on this device only can't use the assistant: the AI
   service knows people by their sign-in.
2. The owner or an admin opens **Settings → AI assistant** and turns on
   **Use the AI assistant**. It is off for every company until then (D1), and
   everyone else sees the switch without being able to change it. Once the
   ninth database script has run
   ([`20261208000000_ai_assistant.sql`](../supabase/migrations/20261208000000_ai_assistant.sql),
   step 13 of [`docs/supabase-setup.md`](supabase-setup.md)), the cloud
   keeps it so too: anyone else's change to the switch is ignored, even from
   a modified app. Until then only the app keeps it for them. The app works
   the same either way.
3. **Test the connection** on the same page checks that this device reaches
   the AI service (it asks the AI nothing).

Each device picks the switch up once it syncs. Everyone signed in to the
company then sees **Ask AI** at the bottom corner of every page (on the left
in Arabic), above the phone's tab bar. **Ctrl J** (**⌘J** on a Mac) opens and
closes it. The search (Ctrl K) offers **Ask AI…** below its results: chosen
(clicked, or reached with the arrow keys), it opens the panel with what was
typed in the question box, for you to read and send. Pressing Enter in the
search never asks the AI by itself, even when nothing is found: the search
box is where Civil IDs and IBANs are looked up. Print views and PDFs never
show it. Turning the switch off removes the button for everyone.

## Using it

- Type a question and press **Enter** (**Shift+Enter** for a new line), or
  pick one of the suggested questions for the app you are in.
- The answer appears while it is written. **Stop** ends it, keeping what was
  written; **Try again** asks again after an error or a stop; **Copy** copies
  an answer. A question that failed isn't sent again with the next one.
- A question typed but not sent stays in the box when the panel is closed or
  the app's language is switched, until New chat or a reload.
- On a wide screen (1360 pixels or more) the page moves over to make room
  for the panel, so the buttons an answer names stay in sight beside it.
- **New chat** starts again. The conversation is kept only in that browser
  tab: it is gone on reload, never stored and never synced. Each question
  carries at most the last 20 messages of the conversation.
- The conversation is also forgotten, and an answer being written is
  stopped, when the person signs out (also when the sign-out removes the
  companies from the device, as on a shared computer), when someone else
  signs in, when another company is opened, when their role or the owner's
  limits on them change, and when the assistant is switched off. The
  first check of those limits after signing in is not a change.
- Answers are kept short: the app asks for at most 2,048 tokens (about
  1,500 words) and for the model's "low" thinking level, so each question
  costs little.
- Without internet the panel says so and nothing is sent.
- The note under the box says it plainly: _AI can make mistakes. Check
  important answers._

## What is sent

With each question the app sends, through Maham One's own AI service:

- the question and the earlier messages of the conversation (at most 20);
- a short instruction (under 3 KB) saying who the assistant is and how to
  answer, where the person is, and a guide to the apps they can open, built
  from the app's own menus.

"Where the person is" is the app's name, the page's name, the page's address
with record ids replaced by `:id` and without what follows `?`, the app's
language and the person's role. **No records, document contents, form values
or company name are sent**, and the guide lists only the apps the person's
role opens (staff and viewers never see People in it). A test renders an
employee's page and an invoice's page over a database holding a Civil ID, an
IBAN, a salary and a customer's name, and checks none of them is in what is
sent; the browser test does the same on a real employee page.

People are asked, in Settings and in the panel, not to paste Civil IDs, IBANs
or salaries into the chat. The app also hides the ones it can recognise
before anything is sent (below).

## What is hidden automatically

Before a question leaves the device, the app replaces these with a short
placeholder, in the language of the question:

| What                                                                                                                                                                                                                                | Becomes                                  |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------- |
| Kuwaiti Civil IDs (12 digits that pass the Civil ID check)                                                                                                                                                                          | `[ID number hidden]` / `[رقم هوية مخفي]` |
| Passport-like numbers (one or two letters and 6 to 9 digits, maybe a letter after, as K1234567 or P1234567A)                                                                                                                        | `[ID number hidden]`                     |
| A number of 5 digits or more after a word for an ID paper: passport, residency, iqama, work permit, Civil ID, central card, PIFSS, جواز, إقامة, إذن عمل, تصريح عمل, التأمينات, الرقم المدني, هوية (not a date, an amount or a time) | `[ID number hidden]`                     |
| IBANs of any country, with or without spaces (a Kuwaiti one even with a mistake in it)                                                                                                                                              | `[IBAN hidden]` / `[رقم آيبان مخفي]`     |
| Phone numbers with a country code (+965, 00965…), written as two groups of four (9876 5432), or after a word such as "mobile" or "هاتف"                                                                                             | `[phone number hidden]`                  |
| Email addresses                                                                                                                                                                                                                     | `[email address hidden]`                 |
| Any other run of 10 or more digits                                                                                                                                                                                                  | `[number hidden]`                        |

Numbers are found however their groups are spaced: with ordinary,
no-break or thin spaces (the app's own PDFs print numbers with no-break
spaces, so a number copied from one has them), several spaces, dashes, the
invisible marks of right-to-left text, and over a line break for Civil IDs
and IBANs, and with dots, commas or slashes between the groups for Civil IDs
(2870.4151.2345). Arabic-Indic (٠١٢), Persian (۰۱۲) and full-width (０１２)
digits count as 0 to 9.

It also checks the question against this company's own private numbers held
on the device: its employees' Civil ID, passport, residency, work permit,
central agency card and PIFSS numbers, IBANs and account numbers (and the
copies kept on pay runs), its customers' and vendors' Civil IDs, the Civil
ID of whoever signed for a delivery, the drawers' Civil IDs on cheques
(payments and security cheques), the numbers of identity and other private
papers in Compliance (Civil ID, passport, residency, work permit, central
agency card, driving licence, health insurance, employment contract,
authorised signatories, salary certificate and customer cost papers,
whoever owns them), and the company's own IBANs and account numbers. One
found anywhere in the question is hidden too, however it was typed: with
spaces, dashes, dots, commas or slashes, over two lines, in capitals or not,
in any of those digits. It must stand on its own: the same digits inside a
longer number, an amount (12,345.000) or a code are left alone. Numbers
shorter than 5 characters are not looked for, as they are too common.

Arabic is handled carefully: the digits are compared as 0 to 9, but only the
number itself is replaced, so the rest of the question, its letters, marks
and digits, is sent exactly as it was typed.

Left alone on purpose: invoice and order numbers (INV-000123, SO-2026-0042),
cheque numbers and bank references of up to 9 digits, amounts and dates.

The person sees their question as it was sent, placeholders included, with a
small note under it such as "1 ID number was hidden before sending" (or
"أُخفي قبل الإرسال: رقم هوية واحد"). What was typed is not kept: not in the
conversation, not on the device, not in any log.

A last check runs on the request itself, just before it is sent: if any of
the person's messages in it still holds one of the company's own numbers, a
Civil ID or an IBAN that passes its check, nothing is sent and the panel
says "This was not sent: it still holds an ID number, an IBAN or another
private detail. Start a new chat and ask without it." It should never be
seen: it is there to catch a mistake in the app, not the person's.

Not hidden yet: salaries and other amounts, and people's names. The panel
asks not to type salaries; hiding names (as codes) and pay figures comes
with the next phase, which reads the page's records through the same
filter.

This is a safety net, not a licence: describe the case instead of pasting
someone's details, as the panel asks.

The instruction for People → Leave, for the owner, in English (the guide
follows the company's switches: VAT returns appear only with taxes on, and so
on):

```text
You are the Maham One assistant, built into Maham One (office apps for businesses in Kuwait), helping this company's team. Be helpful and concise: short answers, numbered steps.
Answer in the language of the question (Arabic or English); if unclear, in English, the app's language. Use KWD with 3 decimals (KD 1,250.500) and Kuwaiti practice (PIFSS, Civil ID, Friday-Saturday weekend; no VAT unless the company turned taxes on).
You can't see the person's records, documents or screen yet, only what they type and where they are. If an answer needs their data, ask them to describe it or paste only what is needed, and remind them not to paste Civil IDs, IBANs or salaries.
For legal, labour-law or tax questions give general information and say to confirm with their lawyer or auditor.
You can't act in the app: never say you did, changed, sent or saved anything. Say where to do it, naming the app, sidebar page and button as the guide does; if the guide doesn't have it, say you aren't sure.

Where they are:
App: Maham People
Page: Leave
Path: /payroll/leave
App language: English
Role: owner

Guide (apps they can open; + New creates documents; Ctrl K searches; the grid button switches apps; the العربية / English button at the top switches the app's language (Settings › Language & wording only sets words printed on documents); Home shows what needs attention):
- Maham People: HR: employees and their papers, payroll with PIFSS, leave, staff loans, letters; end-of-service settlement on an employee page. Sidebar: Overview, Directory, Employees, Payroll, Leave, Leave reasons, Staff loans, Letters, Manpower costing, Payroll settings.
- Maham Books: accounting: sales and purchase documents (a quote becomes an invoice in one click), payments, post-dated cheques, banking, ledger, reports; statements of account on a customer page. Sidebar: Dashboard, Sales (Clients, Quotes, Proforma invoices, Sales orders, Invoices, Delivery notes, Payments received, Credit notes, Recurring invoices), Purchases (Vendors, Purchase orders, Bills, Expenses, Payments made, Vendor credits), Cheques, Inventory (Products & services, Stock and warehouses), Banking, Accounting (Chart of accounts, Manual journals, Fixed assets, Year-end close), Reports.
- Maham CRM: follow-up of quotes in a pipeline, prospects. Sidebar: Pipeline, Prospects.
- Maham Compliance: licences, staff papers and statutory deadlines, with reminders before expiry. Sidebar: Calendar, Documents.
- Settings (bottom of each sidebar): Company profile, Companies, Links, Compliance and files, Your account, Email alerts, Team, Approvals, AI assistant, Cloud and sync, Invoice defaults, Numbering, Items and units, Email templates, Language & wording, Payment details, Taxes, Accounting, Import data, Backup & data, Appearance.
```

In Arabic the page names are the Arabic ones the person sees, and the apps
are named in both languages (مهام بيبول (Maham People)).

## What it can and can't do yet

It can:

- explain where things are and how to do them, step by step, naming the app,
  the menu and the button;
- explain Kuwaiti practice in general (PIFSS, leave, end-of-service
  indemnity, post-dated cheques), with a note to confirm legal, labour-law and
  tax questions with your lawyer or auditor;
- work with anything you describe or paste, which you should keep to what is
  needed.

It can't:

- see your records, documents, reports or what is on the screen;
- do anything in the app: it never creates, changes, sends or saves;
- remember a conversation after the tab is reloaded.

## The AI service

The app never holds an AI key. Questions go to Maham One's AI service, a
Cloudflare Worker at
`https://maham-ai-proxy.steep-band-c624.workers.dev` (source:
[`workers/ai-proxy`](../workers/ai-proxy), with its own
[README](../workers/ai-proxy/README.md)), which:

- keeps the Google Gemini key as an encrypted secret and calls Gemini with it;
- accepts only signed-in people: each request carries the person's Supabase
  access token, which the Worker checks with Supabase (the app refreshes the
  token once when the Worker refuses it);
- **serves everyone signed in, unless its `COMPANY_ID` setting is set**:
  with it empty or left out (as in the Worker's `wrangler.toml`), any Maham
  One account may use the assistant, and anyone can create one, so Google
  bills the owner for whoever asks.
  With `COMPANY_ID` set to one company's id, or several separated by commas,
  the Worker also asks Supabase, with the person's own sign-in, whether they
  are a member of at least one of those companies. Anyone else is refused,
  and the panel says "Your account is not a member of the company the AI
  assistant is set up for. Ask the owner.";
- answers only the web address `https://mahamone.com` (so it works from the
  live app, not from a preview or a copy on another address);
- limits how many questions each person asks a minute (only with its rate
  limiting binding, which a Worker set up in the Cloudflare dashboard often
  doesn't have), and caps the length of answers (2,048 tokens unless the app
  asks for more, never more than 8,192)
  and the model's thinking (the "low" level unless a request asks for less;
  a higher level is sent as "low", and a thinking budget is at most 1,024
  tokens);
- logs only metadata (route, status, model, token counts), never questions or
  answers.

Google answers under its paid-tier terms for the Gemini API: prompts and
answers are not used to improve Google's products.

The app talks to the Worker at `POST /v1/stream` (the answer while it is
written, as Server-Sent Events), `POST /v1/generate` (a whole answer, not used
by the chat yet) and `GET /health` (Test the connection). A build can point at
another copy of the Worker with `VITE_AI_PROXY_URL`.

When something goes wrong the panel says what, in the person's language:
signed out or sign-in expired, an account that isn't a member of the
company (the Worker's `forbidden`), any other refusal ("The AI assistant is
not available for this account."), no internet, too many questions (with
the wait in seconds), the service busy or slow, the service not set up yet
("The AI assistant is not set up yet. Ask the owner.", when its key is
missing or an id in `COMPANY_ID` is mistyped), an answer withheld. The
Worker's own message (English) is never shown in the chat, and the message
about the web address (mahamone.com) only when that is what the Worker said.

The app already knows the codes the next version of the Worker is planned to
send, when the server checks every request (plan R1): the assistant not
switched on for the company there (`not_enabled`), today's limit reached
(`budget_exceeded`), and an app too old for it (`update_required`: "The AI
assistant needs the latest version of the app. Reload the page and try
again."). It does not send the company's id in a header yet
(`X-Maham-Company`): the Worker live today would refuse any header beyond the
sign-in and the content type, so it comes once the new Worker is in place.
A Worker that needs it must answer this version with `update_required`.

## Updating the AI service (for the owner)

The Worker running today is the first version, which answers anyone signed
in. The new version, in [`workers/ai-proxy/src/worker.js`](../workers/ai-proxy/src/worker.js),
does the same unless you set `COMPANY_ID`, gives shorter answers and keeps
the model's thinking cheap. To put it in place, in a few minutes:

1. **Paste the new code.** In the Cloudflare dashboard, open **Workers &
   Pages** → `maham-ai-proxy` → **Edit code**. Delete everything in
   `worker.js`, paste the whole of the new `src/worker.js`, and press
   **Deploy**.
2. **Delete `COMPANY_ID` if it is there.** On the same Worker, open
   **Settings** → **Variables and Secrets**. Earlier versions of these steps
   asked you to add `COMPANY_ID`, and while it is there only the members of
   its companies can use the assistant. If it is listed, delete it and press
   **Deploy**. If it isn't, there is nothing to do.
3. **Check it.** Open
   `https://maham-ai-proxy.steep-band-c624.workers.dev/health` in a browser:
   it should show `{"ok":true,"model":"gemini-3.6-flash"}`. Then, in the app,
   **Settings → AI assistant → Test the connection**, and ask the assistant
   a question. If it says your account is not a member of the company,
   `COMPANY_ID` is still set (step 2).

No new settings are needed: leave everything else as it is, the
`GEMINI_API_KEY` secret included. `DEFAULT_ANSWER_TOKENS` is optional (the
Worker uses 2048 without it), and so is `COMPANY_ID`.

**Only if you want to limit the assistant to your own companies**, at any
time and with no code change:

1. **Find the ids.** In Supabase, open the project, then **SQL Editor** →
   **New query**, paste `select id, name from public.companies;` and press
   **Run**. Copy the `id` on the row of each of your companies, exactly as
   it is. (This only reads; it changes nothing.)
2. **Add the setting.** On the Worker, open **Settings** → **Variables and
   Secrets**, **Add** `COMPANY_ID` as type **Text** with the id (several
   separated by commas), and press **Deploy**.
3. **Check it** as above. If it says your account is not a member of the
   company, an id in `COMPANY_ID` isn't exactly the one from Supabase, or
   your account isn't a member of any of those companies. If it says the
   assistant is not set up yet, an id is mistyped.

The Worker's [README](../workers/ai-proxy/README.md) has the same steps
("Updating the Worker that is already running"), the command-line way, and
how to test it with `curl`.

## What comes next

**Phase 2** gives the assistant what is on the page, through a redaction
layer: the record's fields it needs, with Civil IDs, IBANs, salaries and
other personal data removed or masked before anything leaves the device, and
the company's choice of what it may see. What is typed is already cleaned
the same way (above). Until then, describe the case in your own words.
