# Maham One AI proxy

A small Cloudflare Worker that sits between the Maham One app and Google's Gemini API. It holds the Gemini key so the app never has to: anything inside the app can be read by anyone who opens it, so the key must live somewhere only Cloudflare can see.

```
Maham One app (in the browser, signed in)
   |  POST /v1/generate  or  /v1/stream
   |  Authorization: Bearer <the person's Supabase sign-in token>
   v
This Worker (Cloudflare)
   - checks the sign-in with Supabase
   - only if COMPANY_ID is set: checks that the person is a member of one of its companies
   - checks the request (size, model, fields) and the per-person limit
   |  x-goog-api-key: <GEMINI_API_KEY, an encrypted Cloudflare secret>
   v
Google Gemini API
```

The app's AI assistant (**Settings → AI assistant** in Maham One, see [`docs/ai-assistant.md`](../../docs/ai-assistant.md)) sends its questions here. The Worker already running at `maham-ai-proxy` is the first version: to update it, see **"Updating the Worker that is already running"** in step 2 (paste the new `src/worker.js`, deploy, delete `COMPANY_ID` if it is there, test).

Three things to know before you start:

- **Everyone signed in can use it, unless you limit it.** The Worker refuses any request without a valid Maham One cloud sign-in. With `COMPANY_ID` empty or left out (as in `wrangler.toml`), every signed-in account may use it. Anyone on the internet can create a Maham One account, and Google bills the Gemini key's owner for every question, whoever asks it. To limit it later to the members of your own companies, set `COMPANY_ID` (step 2.0) and deploy again: no code change is needed.
- **Not signed in, no AI.** A company kept on this device only (not signed in to the cloud) can't use AI.
- **Do not send real company data until billing is on** (step 1.2). On Google's free tier, Google may use what is sent to improve its products and people at Google may read it. That is not acceptable for payroll, Civil IDs, salaries or IBANs.

What's in this folder:

| File                | What it is                                                                     |
| ------------------- | ------------------------------------------------------------------------------ |
| `src/worker.js`     | The Worker. One file, no dependencies, so it can be pasted into the dashboard. |
| `wrangler.toml`     | Its settings for the command-line way (B). Safe to keep in git: no secrets.    |
| `.dev.vars.example` | The shape of the local secrets file for testing on a computer.                 |
| `test/`             | Automated tests (run with the app's tests).                                    |

---

## Step 1. Get a Gemini API key, on the paid tier

### 1.1 Create the key

1. Go to [Google AI Studio](https://aistudio.google.com/apikey) and sign in with the company's Google account.
2. Choose **Create API key**. When asked for a Google Cloud project, create a new one just for this, for example `maham-one-ai`, so its billing, limits and key are separate from anything else.
3. Copy the key (it starts with `AIza`). Keep it only in a password manager until step 2. Never paste it into the app, a chat, an email, a ticket or GitHub, and never send it to us.

### 1.2 Turn on billing (required before real data)

Google's terms for the Gemini API differ by tier:

- **Free tier:** Google may use prompts and answers to improve its products, and human reviewers may read them.
- **Paid tier** (Cloud Billing turned on for the key's project): prompts and answers are not used to improve Google's products.

To turn it on:

1. In AI Studio, on the API keys page, find the key's project and choose **Set up billing** (or go to [Google Cloud console](https://console.cloud.google.com/) → **Billing** → **Link a billing account** and pick the project).
2. Add or choose a billing account and finish the steps.
3. Back on the AI Studio API keys page, check that the project now shows a paid plan or tier (for example "Tier 1") instead of "Free".

Until it does, test only with made-up text such as "Write a short thank-you note to a customer".

Google's terms change from time to time; read the current [Gemini API Additional Terms of Service](https://ai.google.dev/gemini-api/terms) yourself, including how long Google may keep requests to detect abuse.

### 1.3 Restrict the key to the Gemini API

1. In [Google Cloud console](https://console.cloud.google.com/), pick the key's project at the top.
2. **APIs & Services** → **Credentials** → click the key.
3. Under **API restrictions** choose **Restrict key** and tick only **Generative Language API**. Save.
4. Leave **Application restrictions** at **None**: the Worker's network addresses change, and the key is protected by living only in Cloudflare.

### 1.4 Set a budget alert and a hard limit

A budget only warns you; a quota actually stops spending. Set both.

1. **Budget:** Google Cloud console → **Billing** → **Budgets & alerts** → **Create budget**. Scope it to the key's project, set a monthly amount (for example USD 20), and keep the alerts at 50%, 90% and 100%. The billing account's admins get the emails.
2. **Quota:** Google Cloud console → **APIs & Services** → **Generative Language API** → **Quotas & system limits**. Find the requests-per-day (and per-minute) limits for the model and choose **Edit** to lower them to what the company needs, for example 2,000 a day. The names on that page change; look for "generate content requests".

---

## Step 2. Deploy the Worker

### 2.0 Optional: find your companies' cloud ids

Only if you want to limit the AI to your own companies. With `COMPANY_ID` empty or left out, the Worker serves everyone signed in to Maham One, and you can skip this step. To serve only the members of your companies, set `COMPANY_ID` to a company's cloud id, or to several separated by commas. An id is not secret, but it must be exact. To find them:

1. Sign in at [supabase.com/dashboard](https://supabase.com/dashboard) and open the Maham One project (`gagdyhintrxdkiqhahzh`).
2. **Table Editor** → the `companies` table. Find the company by its `name` and copy its `id` (8 to 64 letters, digits, `-` or `_`).

   Or open the **SQL Editor** → **New query**, paste this and choose **Run**:

   ```sql
   select id, name from public.companies;
   ```

   It lists every company kept in the cloud, by `id` and `name`, and changes nothing. Copy the `id` on the row of each of your companies' `name`, exactly as it is (no quotes or spaces).

With `COMPANY_ID` set, someone who isn't a member of any of those companies gets `forbidden`. If an id in it is mistyped, or it holds only commas, the Worker refuses every AI request with `internal` ("The AI service is not set up yet") rather than guess.

Then pick **one** way. Both give you an address like `https://maham-ai-proxy.<your-subdomain>.workers.dev`.

### Way A: the Cloudflare dashboard only

1. Sign in at [dash.cloudflare.com](https://dash.cloudflare.com/) and open **Workers & Pages** (under **Compute**).
2. Choose **Create** → **Create Worker** (or **Start with Hello World!**). Name it `maham-ai-proxy` and choose **Deploy**.
3. Choose **Edit code**. Delete everything in `worker.js`, paste the whole of [`src/worker.js`](src/worker.js) from this folder, and choose **Deploy**.
4. Go to the Worker's **Settings** → **Variables and Secrets**. Choose **Add** for each of these, with type **Text**:

   | Variable name              | Value                                            |
   | -------------------------- | ------------------------------------------------ |
   | `GEMINI_MODEL`             | `gemini-3.6-flash`                               |
   | `ALLOWED_MODELS`           | `gemini-3.6-flash`                               |
   | `ALLOWED_ORIGINS`          | `https://mahamone.com`                           |
   | `SUPABASE_URL`             | `https://gagdyhintrxdkiqhahzh.supabase.co`       |
   | `SUPABASE_PUBLISHABLE_KEY` | `sb_publishable_KyVAkWtemw_XDnNK8ZKRpA_-5x4pk8d` |
   | `COMPANY_ID` (optional)    | leave it out, or the ids from step 2.0           |
   | `MAX_OUTPUT_TOKENS`        | `8192`                                           |
   | `DEFAULT_ANSWER_TOKENS`    | `2048`                                           |
   | `MAX_BODY_BYTES`           | `262144`                                         |

   The publishable key is public by design (the app already contains it); it only names the Supabase project.

5. Same page: **Add** → type **Secret** (not Text) → name `GEMINI_API_KEY` → paste the key from step 1.1 → **Deploy**. Once saved, a secret is encrypted and can't be read back by anyone, only replaced.
6. **Settings** → **Bindings** → **Add binding**. If **Rate limiting** is offered, add it with variable name `AI_RATE_LIMITER`, limit `30`, period `60` seconds (namespace ID `1001` if asked). If the dashboard doesn't offer it, carry on: the Worker then limits nobody per minute, so Google's quota from step 1.4, if you set one, is the only ceiling. Way B adds the limit.
7. **Settings** → **Runtime**: set the compatibility date to `2026-10-01` or later, and add the compatibility flag `enable_request_signal` if you can. It lets the Worker stop Google's work as soon as the app closes the connection. Optional.
8. **Settings** → **Observability**: turn **Workers Logs** on. If there's a separate switch for invocation logs, turn that off: the Worker writes its own log line for every request.
9. **Settings** → **Domains & Routes**: check that the `workers.dev` address is on and copy it.
10. Test it (step 3).

If you change the code later, follow "Updating the Worker that is already running" below. If you switch to way B later, note that `wrangler deploy` makes the Worker match `wrangler.toml`: variables added only in the dashboard are replaced by the file's (the secret is kept).

### Updating the Worker that is already running (dashboard)

For the Worker deployed with the first version of `src/worker.js` (way A). The new version gives shorter answers unless the app asks for more and keeps the model's thinking cheap. Like the first version, it serves everyone signed in to Maham One unless you set `COMPANY_ID`. Your Gemini key and the other variables stay as they are.

1. Sign in at [dash.cloudflare.com](https://dash.cloudflare.com/) → **Workers & Pages** → `maham-ai-proxy` → **Edit code**. Delete everything in `worker.js`, paste the whole of the new [`src/worker.js`](src/worker.js) from this folder, and choose **Deploy**.
2. **Delete `COMPANY_ID` if it is there.** Open **Settings** → **Variables and Secrets**. Earlier versions of these steps asked you to add `COMPANY_ID`, and while it is there only the members of its companies can use the AI. If it is listed, delete it and choose **Deploy**. If it isn't, there is nothing to do.
3. Test `/health` (step 3.1): open `https://maham-ai-proxy.steep-band-c624.workers.dev/health` in a browser, or run `curl -i "$WORKER/health"`. Expect `200` and `{"ok":true,"model":"gemini-3.6-flash"}`. (`/health` doesn't show whether `COMPANY_ID` is set; step 2 is the place to check.)
4. Then step 3.3 with your own sign-in: expect `200` and an answer. An account that is a member of no company gets an answer too; if it gets `403` and `"code":"forbidden"`, `COMPANY_ID` is still set (step 2).

No new variables are needed. `COMPANY_ID` is optional (without it, everyone signed in may use the AI), and so is `DEFAULT_ANSWER_TOKENS` (without it, the Worker uses 2048). Leave the other variables already there as they are (`GEMINI_MODEL`, `ALLOWED_MODELS`, `ALLOWED_ORIGINS`, `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `MAX_OUTPUT_TOKENS` = `8192`, `MAX_BODY_BYTES`) and the `GEMINI_API_KEY` secret.

To limit the AI to your own companies at any time, with no code change: **Settings** → **Variables and Secrets** → **Add**, type **Text**, name `COMPANY_ID`, value the id from step 2.0 (or several, separated by commas), then choose **Deploy**. A person who isn't a member of any of them then gets `403` and `"code":"forbidden"`. If you get `500` and "The AI service is not set up yet", an id is mistyped (an id is 8 to 64 letters, digits, `-` or `_`) or the value is only commas.

With way B instead: run `npx wrangler deploy` (`wrangler.toml` already has `DEFAULT_ANSWER_TOKENS`; put ids in `COMPANY_ID = ""` only if you want to limit the AI), then steps 3 and 4. Way B needs no step 2: the deploy sets the variables from `wrangler.toml`, where `COMPANY_ID` is empty.

### Way B: the command line (Wrangler)

You need [Node.js 22](https://nodejs.org/) (the same version as the app). Only if you want to limit the AI to your own companies, first open `wrangler.toml` in this folder and put their ids from step 2.0 in `COMPANY_ID = ""` (several separated by commas); left empty, everyone signed in may use it. Then, in a terminal, from the top of this repository:

```sh
cd workers/ai-proxy
npm install                          # installs Wrangler for this folder only
npx wrangler login                   # opens a browser to sign in to Cloudflare
npx wrangler secret put GEMINI_API_KEY
```

The last command asks for the value: paste the key from step 1.1 and press Enter (nothing shows while you paste). The first time, it also asks whether to create a Worker called `maham-ai-proxy`: answer **y**. Then:

```sh
npx wrangler deploy                  # prints the workers.dev address
npx wrangler tail                    # live log lines; Ctrl+C to stop
```

If the Cloudflare account has no `workers.dev` subdomain yet, `wrangler deploy` asks you to pick one. Wrangler may also warn that several environments are defined; that's harmless, these commands use the main one (`npm run deploy` and `npm run tail` name it explicitly). Everything else (variables, the rate limit, logs) comes from `wrangler.toml`.

To check the settings without a Cloudflare account, `npm run check` bundles the Worker without uploading it (it writes a `dist-check` folder you can delete).

### Optional: ai.mahamone.com instead of workers.dev

This only works if `mahamone.com`'s DNS is managed by Cloudflare (the domain is a zone in the same Cloudflare account). The app is hosted on Vercel, so check where the DNS lives first. If it is on Cloudflare: in the dashboard, **Settings** → **Domains & Routes** → **Add** → **Custom domain** → `ai.mahamone.com`; or turn on the commented `routes` line in `wrangler.toml` and deploy again. Nothing else changes: the allowed origin stays `https://mahamone.com`.

### Optional: a second Worker for testing on a computer

`wrangler.toml` also defines `maham-ai-proxy-dev`, which accepts requests from the app running at `http://localhost:5173`. Its own `COMPANY_ID` under `[env.dev.vars]` is empty too (everyone signed in); set it to a test company's id to allow only that company's members. Deploy it with `npx wrangler deploy --env dev` and give it its own key with `npx wrangler secret put GEMINI_API_KEY --env dev`. Use a separate key, and made-up data only.

---

## Step 3. Test it

Each test below is given twice: for **macOS, Linux, Git Bash or WSL** (`sh`), and for **Windows PowerShell** (`powershell`). On Windows you can also install Git for Windows and run the `sh` versions in **Git Bash** as they are. Replace the address with yours.

```sh
WORKER=https://maham-ai-proxy.your-subdomain.workers.dev
```

```powershell
$WORKER = "https://maham-ai-proxy.your-subdomain.workers.dev"
```

**3.1 Health check** (no sign-in needed):

```sh
curl -i "$WORKER/health"
```

```powershell
curl.exe -i "$WORKER/health"
```

Expect `200` and `{"ok":true,"model":"gemini-3.6-flash"}`.

**3.2 Without a sign-in** (must be refused):

```sh
curl -i -X POST "$WORKER/v1/generate" \
  -H "Content-Type: application/json" \
  -d '{"contents":[{"role":"user","parts":[{"text":"Say hello in Arabic and English."}]}]}'
```

In PowerShell, write the request to a file first (PowerShell would otherwise strip the quotes inside it), then send the file:

```powershell
'{"contents":[{"role":"user","parts":[{"text":"Say hello in Arabic and English."}]}]}' | Out-File -Encoding ascii hello.json
curl.exe -i -X POST "$WORKER/v1/generate" -H "Content-Type: application/json" --data-binary "@hello.json"
```

Expect `401` and `"code":"unauthorized"`.

**3.3 With your sign-in.** Copy your access token from the signed-in app (if `COMPANY_ID` is set, use an account that is a member of one of its companies):

1. Open [mahamone.com](https://mahamone.com) in Chrome or Edge and sign in.
2. Open the developer tools (**F12**, or **Cmd+Option+I** on a Mac) → **Application** tab → **Local Storage** → `https://mahamone.com` → the key `almailbooks.auth`. (In Firefox and Safari it's the **Storage** tab.)
3. Its value is a block of text. Copy only the value of `access_token`: the long text starting with `eyJ`, without the quotes. Do not copy the `refresh_token`.

   Or, in the developer tools' **Console** tab, type this and press Enter; it copies the token for you:

   ```js
   copy(JSON.parse(localStorage.getItem('almailbooks.auth')).access_token);
   ```

This token lets whoever has it act as you in Maham One until it expires (about an hour). Use it only in your own terminal, and never send it to anyone, including us.

```sh
TOKEN=paste-the-access-token-here

curl -i -X POST "$WORKER/v1/generate" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"contents":[{"role":"user","parts":[{"text":"Say hello in Arabic and English."}]}]}'
```

```powershell
$TOKEN = "paste-the-access-token-here"
curl.exe -i -X POST "$WORKER/v1/generate" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" --data-binary "@hello.json"
```

Expect `200` and Gemini's answer as JSON (the text is under `candidates[0].content.parts[0].text`). If you get `403` and `"code":"forbidden"`, `COMPANY_ID` is set and the account isn't a member of any of its companies, or an id in it is wrong (step 2.0).

The same with streaming, where the answer arrives in pieces as `data:` lines:

```sh
curl -N -X POST "$WORKER/v1/stream" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"contents":[{"role":"user","parts":[{"text":"Write three short tips for keeping invoices tidy."}]}]}'
```

```powershell
'{"contents":[{"role":"user","parts":[{"text":"Write three short tips for keeping invoices tidy."}]}]}' | Out-File -Encoding ascii tips.json
curl.exe -N -X POST "$WORKER/v1/stream" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" --data-binary "@tips.json"
```

Delete `hello.json` and `tips.json` afterwards if you like; they hold only the test questions.

**3.4 CORS** (which web pages may call it from a browser):

```sh
# The app's own address: expect 204 and "Access-Control-Allow-Origin: https://mahamone.com"
curl -i -X OPTIONS "$WORKER/v1/generate" \
  -H "Origin: https://mahamone.com" \
  -H "Access-Control-Request-Method: POST" \
  -H "Access-Control-Request-Headers: authorization, content-type"

# Any other website: expect 403 and no Access-Control-Allow-Origin header
curl -i "$WORKER/health" -H "Origin: https://example.com"
```

```powershell
curl.exe -i -X OPTIONS "$WORKER/v1/generate" -H "Origin: https://mahamone.com" -H "Access-Control-Request-Method: POST" -H "Access-Control-Request-Headers: authorization, content-type"
curl.exe -i "$WORKER/health" -H "Origin: https://example.com"
```

CORS only controls what web pages can do inside a browser. It is not a lock: tools like curl can send any `Origin`, or none. The sign-in check in 3.2 and 3.3 (and, with `COMPANY_ID` set, the membership check) is what keeps others out.

**3.5 Watch the logs** with `npx wrangler tail` (way B) or the Worker's **Logs** tab in the dashboard. Each request writes one line like:

```json
{
  "route": "generate",
  "method": "POST",
  "user": "3f9c1a2b7d4e5f60",
  "auth": "checked",
  "model": "gemini-3.6-flash",
  "usage": { "prompt": 9, "output": 24, "total": 61 },
  "status": 200,
  "ms": 1840
}
```

`user` is a scrambled stand-in for the person, not their id or email. Prompts, answers, tokens and the key are never logged.

---

## Step 4. What to send back to us

Only the Worker's address, for example `https://maham-ai-proxy.your-subdomain.workers.dev` (or `https://ai.mahamone.com`). It would also help to say which way you used (A or B), whether the rate limiting binding was added, whether `COMPANY_ID` is set (no need to send it), and that billing is on.

**Never** send the Gemini key or your access token. We don't need either: the key stays in Cloudflare, and the app gets each person's token when they sign in.

---

## Rotating the key

Do this if the key may have been seen by someone, when someone with access to it leaves, and otherwise about once a year.

1. In [AI Studio](https://aistudio.google.com/apikey), create a new key **in the same project** (so billing and the paid-tier terms carry over), and restrict it as in step 1.3.
2. Put it in the Worker: dashboard → the Worker → **Settings** → **Variables and Secrets** → `GEMINI_API_KEY` → edit → paste → **Deploy**. Or run `npx wrangler secret put GEMINI_API_KEY` again.
3. Test with step 3.3.
4. Delete the old key: Google Cloud console → **APIs & Services** → **Credentials** → the old key → **Delete**.

If the key has leaked, delete it first (step 4), then do steps 1 to 3. AI is unavailable in between.

## Changing the model

Google renames and retires models often. When it retires the one in `GEMINI_MODEL`, the Worker answers `upstream_error` ("The AI model is not available"). To change it, set both `GEMINI_MODEL` and `ALLOWED_MODELS` to the new name from [Google's model list](https://ai.google.dev/gemini-api/docs/models): in the dashboard (**Variables and Secrets**) or in `wrangler.toml` followed by `npx wrangler deploy`. `ALLOWED_MODELS` may list several, separated by commas; the app can then pick one of them, and nothing else.

---

## Settings

| Name                       | Where                 | What it does                                                                                                         |
| -------------------------- | --------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `GEMINI_API_KEY`           | Secret                | The Gemini key. Only ever set as an encrypted secret.                                                                |
| `GEMINI_MODEL`             | Variable              | The model used when the app names none, and shown by `/health`.                                                      |
| `ALLOWED_MODELS`           | Variable              | The models the app may ask for, comma-separated. Others get `model_not_allowed`.                                     |
| `ALLOWED_ORIGINS`          | Variable              | The web addresses allowed by CORS, comma-separated and exact. `*` is not accepted.                                   |
| `SUPABASE_URL`             | Variable              | The Supabase project people sign in with.                                                                            |
| `SUPABASE_PUBLISHABLE_KEY` | Variable              | Its publishable key (public).                                                                                        |
| `COMPANY_ID`               | Variable (optional)   | Empty: everyone signed in may use it. One company's id, or several comma-separated (step 2.0): only their members.   |
| `MAX_OUTPUT_TOKENS`        | Variable              | The longest answer, in tokens (Gemini counts its "thinking" in this too). Default 8192.                              |
| `DEFAULT_ANSWER_TOKENS`    | Variable              | The longest answer when a request doesn't say (no `maxOutputTokens`), never above `MAX_OUTPUT_TOKENS`. Default 2048. |
| `MAX_BODY_BYTES`           | Variable              | The largest request, in bytes. Default 262144 (256 KB). Raise it if the app needs to send pictures of receipts.      |
| `GENERATE_TIMEOUT_MS`      | Variable (optional)   | `/v1/generate`: the time allowed for the **whole** answer (Google sends nothing until it is done). Default 90000.    |
| `STREAM_START_TIMEOUT_MS`  | Variable (optional)   | `/v1/stream`: the time allowed until Google starts answering. Default 30000 (30 seconds).                            |
| `STREAM_IDLE_TIMEOUT_MS`   | Variable (optional)   | `/v1/stream`: the longest pause allowed in the middle of an answer. A stream may run longer overall. Default 60000.  |
| `AI_RATE_LIMITER`          | Rate limiting binding | 30 requests a minute per person. Without it, there's no per-person limit in the Worker.                              |

---

## Error codes

Every error is JSON like `{"error":{"code":"unauthorized","message":"Sign in to use the AI assistant.","status":401}}`. The `message` is safe to show to the person; `status` repeats the HTTP status.

| Code                | HTTP         | What it means                                                                                                                                                                            | What to do                                                                                                                          |
| ------------------- | ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `unauthorized`      | 401          | No sign-in token, or Supabase says it is expired or not valid.                                                                                                                           | Sign in again (the app refreshes tokens on its own). If everyone gets it, check `SUPABASE_URL`.                                     |
| `forbidden`         | 403          | Signed in, but `COMPANY_ID` is set and the person isn't a member of any of its companies.                                                                                                | Invite them to one of those companies, or remove `COMPANY_ID` to let everyone signed in. If members get it too, check the ids.      |
| `forbidden_origin`  | 403          | The request came from a web page not in `ALLOWED_ORIGINS`.                                                                                                                               | Add the app's exact address (for example `https://mahamone.com`) to `ALLOWED_ORIGINS`.                                              |
| `bad_request`       | 400          | The request isn't valid JSON, misses `contents`, holds a field or file type the Worker doesn't pass on (the message names it), or Google couldn't use it (its short reason is included). | A problem in the app's request; tell us the message.                                                                                |
| `payload_too_large` | 413          | The request is bigger than `MAX_BODY_BYTES`.                                                                                                                                             | Send less, or raise `MAX_BODY_BYTES`.                                                                                               |
| `model_not_allowed` | 400          | The app asked for a model that isn't in `ALLOWED_MODELS`.                                                                                                                                | Add it to `ALLOWED_MODELS` if it should be allowed.                                                                                 |
| `rate_limited`      | 429          | Too many requests from this person (30 a minute, with the binding), or Google's limit for the key is used up.                                                                            | Wait for the seconds in the `Retry-After` header. If it keeps happening, raise the Google quota (step 1.4).                         |
| `upstream_error`    | 502 (or 503) | Google failed or refused: Google is down or overloaded, the key is wrong or restricted, billing, the model was retired, or Supabase is down.                                             | Try again. If it persists, check the log line (`upstream`, `googleStatus`, `reason`), the key (step 1), billing and `GEMINI_MODEL`. |
| `upstream_timeout`  | 504          | Google (or Supabase) took too long: for `/v1/generate`, the whole answer took longer than `GENERATE_TIMEOUT_MS`.                                                                         | Try again; ask for a shorter answer, or use `/v1/stream` for long ones.                                                             |
| `not_found`         | 404          | No such address or method. The routes are `GET /health`, `POST /v1/generate`, `POST /v1/stream`.                                                                                         | Check the address.                                                                                                                  |
| `internal`          | 500          | The Worker isn't set up: the `GEMINI_API_KEY` secret is missing, an id in `COMPANY_ID` is mistyped, or a variable is wrong. The log line names it (`problem`).                           | Add the secret or fix the variable.                                                                                                 |

During a streamed answer, the HTTP status is already 200 when the answer starts. If Google fails after that, the stream ends with an event named `error` whose data is the same JSON:

```
event: error
data: {"error":{"code":"upstream_error","message":"The AI service stopped in the middle of the answer.","status":502}}
```

---

## Who can use it, and the limits

- **Everyone signed in to the Maham One cloud, unless `COMPANY_ID` is set**, whatever their role. The app allows sign-ups, so with `COMPANY_ID` empty that includes anyone who creates an account. With `COMPANY_ID` set, only the members of its companies: someone who creates their own account, or who belongs only to another company, gets `forbidden`. That check asks Supabase with the person's own token, so the database's own rules decide; the Worker needs no Supabase admin key. The app adds a switch for each company (**Settings → AI assistant**) on top: nobody sees the assistant in a company until its owner or an admin turns it on. Someone who creates their own company is its owner, so the switch alone doesn't keep strangers out; `COMPANY_ID` does.
- **Up to 30 requests a minute per person**, only with the rate limiting binding (a Worker set up in the dashboard often has none, and then there is no per-person limit). The limit is counted in each Cloudflare location separately, so it is a guard against runaway loops rather than an exact count. Google's quota (step 1.4), if you set one, is the ceiling for everyone together; without one, nothing caps the total.
- **Not signed in, not served:** a company kept on this device only can't use AI.
- **Size:** requests are at most 256 KB (`MAX_BODY_BYTES`), answers at most 8192 tokens (`MAX_OUTPUT_TOKENS`, thinking included), and always one answer per request. A request that doesn't say how long its answer may be gets 2048 tokens (`DEFAULT_ANSWER_TOKENS`).
- **Thinking:** a request that sets no `thinkingConfig` is sent with `"thinkingConfig": {"thinkingLevel": "low"}`. `gemini-3.6-flash` otherwise thinks at "medium", and its thinking is billed as output and counts in the answer's length. Not "minimal": Google's docs say it needs the model's thought signatures sent back in a conversation of several turns, which the chat doesn't do, and newer Flash models no longer accept it. A request's own `thinkingConfig` is kept cheap too: `thinkingLevel` "medium" or "high" is sent as "low" ("minimal" and "low" as asked), and `thinkingBudget` is at most 1024 tokens (and `MAX_OUTPUT_TOKENS`), with -1 ("let the model decide") sent as 1024. A level is never added next to a budget: Google refuses the two together.
- **Files:** at most 10 files sent inline per request, and only pictures (PNG, JPEG, WebP, HEIC, HEIF), PDFs and plain text. Audio, video and file links (`fileData`, which would make Google fetch a file or video of any length itself) are refused. High-resolution picture processing (`mediaResolution` HIGH) is refused.
- **What a request costs is not just its size.** Google counts each picture, and each PDF page, as a fixed number of tokens (hundreds each, more at higher resolution), whatever its size in bytes. So a request with pictures or a PDF of many near-empty pages can cost several times what 256 KB of text would: the 10-file limit bounds pictures, but a single PDF can have up to Google's page limit. The budget alert and quota in step 1.4, if you set them, are the backstop.
- **Only the fields the app needs are passed on:** `contents`, `systemInstruction` (text only), `generationConfig`, `safetySettings`, `tools` and `toolConfig`. Other top-level fields are dropped. Inside them, only the Gemini fields the app uses, in their usual spelling (`maxOutputTokens`, not `max_output_tokens`), are accepted; anything else is refused with `bad_request`, so nothing slips past the limits under another name.
- `tools` may only describe the app's own functions (function calling). Google Search, URL fetching and code execution are refused, since they would send data elsewhere or bill separately.
- What Google receives: only those fields. Not the person's token, user id, email or address; Google sees Cloudflare's network address. Cloudflare passes the data through and its logs hold only the metadata line shown in step 3.5.
- Cloudflare's Workers Free plan allows 100,000 requests a day; check Cloudflare's current plan limits if the company grows.

---

## For developers

**Request** (both `/v1/generate` and `/v1/stream`): JSON with `contents` (required), and optionally `model` (from `ALLOWED_MODELS`), `systemInstruction`, `generationConfig`, `safetySettings`, `tools` (`[{ "functionDeclarations": [...] }]`) and `toolConfig`, as in the [Gemini API](https://ai.google.dev/api/generate-content), camelCase only. Headers: `Authorization: Bearer <Supabase access token>` and `Content-Type: application/json`. The preflight also allows `X-Maham-Company`, `X-Maham-Feature` and `X-Maham-Shares`, which later versions of the app send; this version ignores them. Accepted fields (the `ALLOWED_*` lists at the top of `src/worker.js`):

- each content: `role` (`user` or `model`), `parts`; each part: `text`, `inlineData` (`mimeType`, `data`), `functionCall` (`id`, `name`, `args`), `functionResponse` (`id`, `name`, `response`), `thought`, `thoughtSignature`. `systemInstruction` parts: `text` only.
- `generationConfig`: `temperature`, `topP`, `topK`, `maxOutputTokens` (capped; `DEFAULT_ANSWER_TOKENS` when left out), `candidateCount` (always sent as 1), `stopSequences`, `responseMimeType`, `responseSchema`, `responseJsonSchema`, `thinkingConfig` (`thinkingBudget` at most 1024 and `MAX_OUTPUT_TOKENS`, -1 sent as 1024; `thinkingLevel`, "medium" and "high" sent as "low"; `includeThoughts`; `{"thinkingLevel": "low"}` when left out), `seed`, `presencePenalty`, `frequencyPenalty`, `mediaResolution` (`MEDIA_RESOLUTION_LOW` or `MEDIA_RESOLUTION_MEDIUM`).
- `safetySettings` items: `category`, `threshold`, `method`. Function declarations: `name`, `description`, `behavior`, `parameters`, `parametersJsonSchema`, `response`, `responseJsonSchema`. `toolConfig`: `functionCallingConfig` (`mode`, `allowedFunctionNames`).

Use `/v1/stream` for anything long (reports, summaries near the token cap): `/v1/generate` must finish within `GENERATE_TIMEOUT_MS` (90 seconds), because Google sends nothing until the answer is complete.

**Answer:** `/v1/generate` returns Gemini's `generateContent` response as it is. `/v1/stream` passes Gemini's `streamGenerateContent?alt=sse` events through unchanged, as they arrive, then possibly one `event: error` as above; a client should ignore a `data:` line it can't parse just before an `error` event. Errors before the first byte are ordinary JSON errors. `Retry-After` is readable from the browser.

**Run it on this computer:** `cp .dev.vars.example .dev.vars`, put a test key in `.dev.vars` (git-ignored), then `npm run dev` (the `dev` settings, which allow `http://localhost:5173`); it listens on `http://localhost:8787`.

**Tests:** from the top of the repository, `npm test` runs them with the app's tests (`npm test -- workers/ai-proxy` for these only); `npm test` in this folder does the same (it needs the app's own `npm ci` at the top first). They replace Supabase and Google with fakes; nothing goes over the network.

**The app** (`src/features/ai/client.ts`) reaches this Worker at `VITE_AI_PROXY_URL` (the live address by default), with the person's token, and sends `generationConfig` with `maxOutputTokens` 2048 and `thinkingLevel` "low" on every chat request. It shows `forbidden` as "Your account is not a member of the company the AI assistant is set up for. Ask the owner.", never as a sign-in problem, and `internal` with "The AI service is not set up yet" as "The AI assistant is not set up yet. Ask the owner." It already has messages for the codes the next version of this Worker is planned to send (`not_enabled`, `budget_exceeded`, `update_required`). It sends only the `Authorization` and `Content-Type` headers, not `X-Maham-Company` or `X-Maham-Feature`: the first version of this Worker, live until the owner pastes this one, lists only those two in its preflight, so any other header would stop every question. A later Worker that needs the company header must answer this version of the app with `update_required` (the app then says "The AI assistant needs the latest version of the app. Reload the page and try again."), not refuse it with another code.
