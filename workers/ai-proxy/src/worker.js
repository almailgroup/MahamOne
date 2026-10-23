// @ts-check
/**
 * Maham One AI proxy: a Cloudflare Worker that passes the app's AI requests
 * to Google's Gemini API, so the Gemini key never reaches a browser.
 *
 * The key is stored only here, as an encrypted Worker secret (GEMINI_API_KEY).
 * The app sends its requests to this Worker with the signed-in person's
 * Supabase access token; the Worker checks the token, applies limits, and
 * calls Google with the key. The person's token is never sent to Google.
 *
 * Who may use it: everyone signed in to Maham One, unless COMPANY_ID is set.
 * With COMPANY_ID empty or left out, any account Supabase confirms may use it.
 * The app lets anyone create an account, so that is anyone who signs up, and
 * Google bills the owner for all of them. With COMPANY_ID set to one company
 * id, or several separated by commas, the Worker also asks Supabase, with the
 * person's own token, whether they are a member of at least one of those
 * companies. Anyone else gets 403.
 *
 * Routes
 *   GET  /health        No sign-in needed. Answers {ok: true, model}. Never secrets.
 *   POST /v1/generate   One whole answer, as JSON (Gemini's generateContent).
 *   POST /v1/stream     The answer while it is written, as Server-Sent Events
 *                       (Gemini's streamGenerateContent?alt=sse, passed through).
 *   OPTIONS             CORS preflight for the three routes above.
 *   Anything else       404, as JSON.
 * The /v1/ in the paths lets a later version of the app use /v2/ without
 * breaking devices that still run an older version.
 *
 * Request body for both /v1 routes (JSON, at most MAX_BODY_BYTES):
 *   {
 *     model?: string,             // one of ALLOWED_MODELS; GEMINI_MODEL if left out
 *     contents: Content[],        // required, as in the Gemini API
 *     systemInstruction?: Content,          // text parts only
 *     generationConfig?: object,  // allowlisted fields; maxOutputTokens capped, one candidate,
 *                                 // DEFAULT_ANSWER_TOKENS and low thinking when left out,
 *                                 // thinking never above low (budget at most 1024)
 *     safetySettings?: object[],
 *     tools?: [{functionDeclarations: [...]}],  // function calling only
 *     toolConfig?: {functionCallingConfig: {...}}
 *   }
 * Any other top-level field is dropped. Inside these fields only the Gemini
 * fields listed below (ALLOWED_* constants), in their camelCase spelling, are
 * accepted; anything else is refused with bad_request. Google also accepts the
 * snake_case spellings (file_data, max_output_tokens), so checking for blocked
 * names would not be enough: what is sent to Google is rebuilt from the
 * allowlists. The answer is Gemini's own response body (generate) or Gemini's
 * own SSE events (stream).
 *
 * Errors are always JSON, {error: {code, message, status}}, where status is
 * the HTTP status and code is one of: unauthorized, forbidden,
 * forbidden_origin, bad_request, payload_too_large, model_not_allowed,
 * rate_limited, upstream_error, upstream_timeout, not_found, internal. Once a
 * stream has started, a failure ends it with an SSE event named "error" whose
 * data is the same JSON. README.md explains each code.
 *
 * Logs hold metadata only (route, status, model, a hash of the user id,
 * duration, token counts). Prompts, answers, tokens and the key are never
 * logged.
 *
 * This file has no dependencies, so it can be pasted into the Cloudflare
 * dashboard as it is.
 */

/**
 * @typedef {object} RateLimiter The Workers Rate Limiting binding.
 * @property {(options: {key: string}) => Promise<{success: boolean}>} limit
 */

/**
 * @typedef {object} Env Settings from wrangler.toml [vars], the secret and the binding.
 * @property {string} [GEMINI_API_KEY] Secret. Set with `wrangler secret put`; never in wrangler.toml.
 * @property {string} [GEMINI_MODEL] The model used when a request names none.
 * @property {string} [ALLOWED_MODELS] Comma-separated models a request may name.
 * @property {string} [ALLOWED_ORIGINS] Comma-separated web origins allowed by CORS.
 * @property {string} [SUPABASE_URL] The Supabase project that signs people in.
 * @property {string} [SUPABASE_PUBLISHABLE_KEY] Its publishable key (public by design).
 * @property {string} [COMPANY_ID] Optional. The company, or companies (comma-separated),
 *   whose members may use the service. Empty or left out: everyone signed in may.
 * @property {string | number} [MAX_OUTPUT_TOKENS] Cap on generationConfig.maxOutputTokens.
 * @property {string | number} [DEFAULT_ANSWER_TOKENS] maxOutputTokens when a request gives none
 *   (still capped by MAX_OUTPUT_TOKENS).
 * @property {string | number} [MAX_BODY_BYTES] Largest request body accepted.
 * @property {string | number} [GENERATE_TIMEOUT_MS] Longest wait for a whole /v1/generate answer.
 * @property {string | number} [STREAM_START_TIMEOUT_MS] Longest wait for a stream's first byte.
 * @property {string | number} [STREAM_IDLE_TIMEOUT_MS] Longest pause allowed inside a stream.
 * @property {RateLimiter} [AI_RATE_LIMITER] Per-user limit ([[ratelimits]] in wrangler.toml).
 */

/**
 * @typedef {'unauthorized' | 'forbidden' | 'forbidden_origin' | 'bad_request'
 *   | 'payload_too_large' | 'model_not_allowed' | 'rate_limited' | 'upstream_error'
 *   | 'upstream_timeout' | 'not_found' | 'internal'} ErrorCode
 */

/** @typedef {Record<string, string | number | boolean | object | undefined>} LogEntry */

const GEMINI_MODELS_URL = 'https://generativelanguage.googleapis.com/v1beta/models/';

const DEFAULT_MAX_BODY_BYTES = 256 * 1024;
const DEFAULT_MAX_OUTPUT_TOKENS = 8192;
/**
 * The longest answer when a request doesn't say (generationConfig.maxOutputTokens
 * left out): enough for a chat answer, a quarter of the most allowed.
 */
const DEFAULT_ANSWER_TOKENS = 2048;
/**
 * The thinking level when a request sets no generationConfig.thinkingConfig.
 * gemini-3.6-flash thinks at "medium" unless told otherwise, and its thinking
 * counts in maxOutputTokens and is billed as output. Google's docs list
 * minimal, low, medium and high for it, under
 * generationConfig.thinkingConfig.thinkingLevel. "low" rather than "minimal":
 * Google says minimal needs the model's thought signatures sent back in a
 * conversation of several turns (the app's chat sends earlier answers as text
 * only), and later Flash models (3.8) no longer accept minimal.
 */
const DEFAULT_THINKING_LEVEL = 'low';
/**
 * Thinking is kept cheap whatever a request asks: a higher level than
 * DEFAULT_THINKING_LEVEL is sent as that level, and a thinking budget (the
 * older way, in tokens) is at most this, -1 ("let the model decide") included.
 */
const LOWERED_THINKING_LEVELS = ['medium', 'high'];
const MAX_THINKING_BUDGET = 1024;
/**
 * generateContent sends nothing until the whole answer is written, so this
 * is the time allowed for the whole answer (thinking included). Long answers
 * should use /v1/stream.
 */
const DEFAULT_GENERATE_TIMEOUT_MS = 90_000;
/** /v1/stream: the time allowed until Google's first byte. */
const DEFAULT_STREAM_START_TIMEOUT_MS = 30_000;
/** A stream may run as long as it keeps sending, with no pause longer than this. */
const DEFAULT_STREAM_IDLE_TIMEOUT_MS = 60_000;

/** For each call to Supabase (the sign-in check and, with COMPANY_ID, the membership check). */
const AUTH_TIMEOUT_MS = 5_000;
/** A checked token is trusted for at most this long, and never past its expiry. */
const AUTH_CACHE_MS = 60_000;
const AUTH_CACHE_MAX_ENTRIES = 1_000;
const MAX_TOKEN_LENGTH = 8_192;
/** Supabase user ids are UUIDs; anything else is refused before it goes in a URL. */
const USER_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
/** The app's company ids (companies_id_format in the Supabase migration). */
const COMPANY_ID = /^[A-Za-z0-9_-]{8,64}$/;

/** The period of the [[ratelimits]] binding in wrangler.toml, in seconds. */
const RATE_LIMIT_RETRY_AFTER_S = 60;

const MAX_CONTENTS = 1_000;
/**
 * Model names are checked twice: against ALLOWED_MODELS, and against this
 * pattern, so even a mistyped allowlist can't put "/", ":", "?" or "%" into
 * the URL sent to Google.
 */
const MODEL_NAME = /^[a-z0-9][a-z0-9.-]{0,79}$/;

// What may be sent to Google. Every object below is rebuilt from these lists,
// in Gemini's camelCase spelling only; any other key (including the snake_case
// spellings Google also accepts, such as file_data or candidate_count) is
// refused. Left out on purpose:
//   fileData (and functionResponse.parts): makes Google fetch a file or video
//     of any length itself, outside the body limit.
//   candidateCount above 1, responseModalities, speechConfig: multiply the
//     cost or produce images or audio.
//   mediaResolution HIGH (generationConfig, or per part): more tokens per image.
//   cachedContent, Google Search, URL context, code execution, retrievalConfig:
//     send data elsewhere, bill separately, or read other people's caches.

const ALLOWED_CONTENT_FIELDS = ['role', 'parts'];
const ALLOWED_PART_FIELDS = [
  'text',
  'inlineData',
  'functionCall',
  'functionResponse',
  'thought',
  'thoughtSignature',
];
const ALLOWED_INLINE_FIELDS = ['mimeType', 'data'];
const ALLOWED_FUNCTION_CALL_FIELDS = ['id', 'name', 'args'];
const ALLOWED_FUNCTION_RESPONSE_FIELDS = ['id', 'name', 'response'];
const ALLOWED_GENERATION_FIELDS = [
  'temperature',
  'topP',
  'topK',
  'maxOutputTokens',
  'candidateCount',
  'stopSequences',
  'responseMimeType',
  'responseSchema',
  'responseJsonSchema',
  'thinkingConfig',
  'seed',
  'presencePenalty',
  'frequencyPenalty',
  'mediaResolution',
];
const ALLOWED_THINKING_FIELDS = ['thinkingBudget', 'thinkingLevel', 'includeThoughts'];
const ALLOWED_MEDIA_RESOLUTIONS = ['MEDIA_RESOLUTION_LOW', 'MEDIA_RESOLUTION_MEDIUM'];
const ALLOWED_SAFETY_FIELDS = ['category', 'threshold', 'method'];
const ALLOWED_TOOL_FIELDS = ['functionDeclarations'];
const ONLY_FUNCTIONS = 'tools may only hold functionDeclarations.';
const ALLOWED_FUNCTION_FIELDS = [
  'name',
  'description',
  'behavior',
  'parameters',
  'parametersJsonSchema',
  'response',
  'responseJsonSchema',
];
const ALLOWED_TOOL_CONFIG_FIELDS = ['functionCallingConfig'];
const ALLOWED_CALLING_CONFIG_FIELDS = ['mode', 'allowedFunctionNames'];

/**
 * Files sent inline (inlineData): pictures, PDFs and plain text. Audio and
 * video are refused: a small, low-quality file can hold hours, and Google
 * bills them by length, not size.
 */
const ALLOWED_INLINE_TYPES = [
  'image/png',
  'image/jpeg',
  'image/webp',
  'image/heic',
  'image/heif',
  'application/pdf',
  'text/plain',
];
/**
 * Google bills each picture by a flat number of tokens whatever its size
 * (and each PDF page), so many tiny pictures cost far more than their bytes.
 */
const MAX_INLINE_PARTS = 10;

/** @type {Record<string, {name: 'health' | 'generate' | 'stream', method: string}>} */
const ROUTES = {
  '/health': { name: 'health', method: 'GET' },
  '/v1/generate': { name: 'generate', method: 'POST' },
  '/v1/stream': { name: 'stream', method: 'POST' },
};

/** Sent on every response. */
const SECURITY_HEADERS = {
  'Cache-Control': 'no-store',
  'X-Content-Type-Options': 'nosniff',
};

/** @type {Record<ErrorCode, number>} */
const DEFAULT_STATUS = {
  unauthorized: 401,
  forbidden: 403,
  forbidden_origin: 403,
  bad_request: 400,
  payload_too_large: 413,
  model_not_allowed: 400,
  rate_limited: 429,
  upstream_error: 502,
  upstream_timeout: 504,
  not_found: 404,
  internal: 500,
};

/** An error with a message that is safe to show: never secrets or prompts. */
class ProxyError extends Error {
  /**
   * @param {ErrorCode} code
   * @param {string} message
   * @param {{status?: number, headers?: Record<string, string>, log?: LogEntry}} [options]
   *   `log` is extra metadata for the log line (never sent to the app).
   */
  constructor(code, message, options = {}) {
    super(message);
    this.name = 'ProxyError';
    this.code = code;
    this.status = options.status ?? DEFAULT_STATUS[code];
    this.headers = options.headers ?? {};
    this.log = options.log ?? {};
  }
}

/** @param {string} message */
const badRequest = (message) => new ProxyError('bad_request', message);

/**
 * Tokens that passed the checks (signed in, and a member of one of the
 * companies in COMPANY_ID when it names any), keyed by the SHA-256 of the
 * token: the token itself is never kept. companies is the COMPANY_ID they
 * were checked against, as config.companies has it ('' when open to everyone
 * signed in), so a pass is never reused under another setting.
 * @type {Map<string, {userId: string, companies: string, until: number}>}
 */
const authCache = new Map();

/** For the tests only: the Worker never reads this. */
export const __testing = { authCache };

export default {
  /**
   * @param {Request} request
   * @param {Env} env
   * @returns {Promise<Response>}
   */
  async fetch(request, env) {
    const started = Date.now();
    const config = readConfig(env);
    const { pathname } = new URL(request.url);
    const route = Object.hasOwn(ROUTES, pathname) ? ROUTES[pathname] : undefined;
    const origin = request.headers.get('Origin');
    const cors = corsFor(origin, config.origins);

    /** @type {LogEntry} */
    const entry = { route: route?.name ?? 'other', method: request.method };
    /** Set when a stream writes its own log line once it ends. */
    const deferred = { log: false };

    /** @type {Response} */
    let response;
    try {
      if (cors.forbidden) {
        entry.origin = origin?.slice(0, 100);
        throw new ProxyError('forbidden_origin', 'This website may not use the AI service.');
      }
      if (!route) throw notFound();
      if (request.method === 'OPTIONS') {
        response = preflight(cors.headers);
      } else if (request.method !== route.method) {
        throw notFound();
      } else if (route.name === 'health') {
        response = jsonResponse({ ok: true, model: config.defaultModel }, 200, cors.headers);
      } else {
        response = await handleAi(request, config, {
          stream: route.name === 'stream',
          cors: cors.headers,
          entry,
          started,
          deferred,
        });
      }
    } catch (error) {
      response = errorResponse(error, cors.headers, entry);
    }
    if (!deferred.log) writeLog(entry, response.status, started);
    return response;
  },
};

// ---------------------------------------------------------------------------
// Settings

/** @param {Env} env */
function readConfig(env) {
  const defaultModel = text(env.GEMINI_MODEL);
  const companyIds = [...new Set(list(env.COMPANY_ID))];
  return {
    apiKey: text(env.GEMINI_API_KEY),
    defaultModel,
    models: new Set([defaultModel, ...list(env.ALLOWED_MODELS)].filter((m) => MODEL_NAME.test(m))),
    origins: new Set(list(env.ALLOWED_ORIGINS).map(normalizeOrigin)),
    supabaseUrl: text(env.SUPABASE_URL).replace(/\/+$/, ''),
    supabaseKey: text(env.SUPABASE_PUBLISHABLE_KEY),
    // COMPANY_ID as a list: spaces and empty items dropped, each id once.
    // Empty: open to everyone signed in.
    companyIds,
    // The same list as one string, for the sign-in cache.
    companies: companyIds.join(','),
    maxOutputTokens: positiveInt(env.MAX_OUTPUT_TOKENS, DEFAULT_MAX_OUTPUT_TOKENS),
    answerTokens: positiveInt(env.DEFAULT_ANSWER_TOKENS, DEFAULT_ANSWER_TOKENS),
    maxBodyBytes: positiveInt(env.MAX_BODY_BYTES, DEFAULT_MAX_BODY_BYTES),
    generateTimeoutMs: positiveInt(env.GENERATE_TIMEOUT_MS, DEFAULT_GENERATE_TIMEOUT_MS),
    streamStartMs: positiveInt(env.STREAM_START_TIMEOUT_MS, DEFAULT_STREAM_START_TIMEOUT_MS),
    streamIdleMs: positiveInt(env.STREAM_IDLE_TIMEOUT_MS, DEFAULT_STREAM_IDLE_TIMEOUT_MS),
    limiter: env.AI_RATE_LIMITER,
  };
}

/** @typedef {ReturnType<typeof readConfig>} Config */

/** @param {unknown} value */
function text(value) {
  return value === undefined || value === null ? '' : String(value).trim();
}

/** @param {unknown} value */
function list(value) {
  return text(value)
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
}

/**
 * @param {unknown} value
 * @param {number} fallback
 */
function positiveInt(value, fallback) {
  const number = Number(text(value));
  return text(value) !== '' && Number.isInteger(number) && number > 0 ? number : fallback;
}

/** @param {string} origin */
function normalizeOrigin(origin) {
  return origin.replace(/\/+$/, '').toLowerCase();
}

/**
 * Settings the /v1 routes can't work without. The app only learns that the
 * service isn't set up; the log line names the missing setting.
 * @param {Config} config
 */
function assertConfigured(config) {
  /** @type {string | null} */
  let problem = null;
  if (!config.apiKey) problem = 'GEMINI_API_KEY secret is not set';
  else if (!MODEL_NAME.test(config.defaultModel))
    problem = 'GEMINI_MODEL is missing or not a model name';
  else if (!/^https:\/\/[a-z0-9.-]+(:\d+)?$/i.test(config.supabaseUrl))
    problem = 'SUPABASE_URL is not an https address';
  else if (!config.supabaseKey) problem = 'SUPABASE_PUBLISHABLE_KEY is not set';
  // COMPANY_ID is optional (empty: everyone signed in), but each item it holds
  // must be a company id: a mistyped value is refused, never read as empty,
  // which would let in everyone signed in.
  else if (!config.companyIds.every((id) => COMPANY_ID.test(id)))
    problem = 'COMPANY_ID is not a company id or a list of them';
  if (problem) {
    throw new ProxyError('internal', 'The AI service is not set up yet.', { log: { problem } });
  }
}

// ---------------------------------------------------------------------------
// CORS
//
// CORS is NOT authentication. It only tells browsers which web pages may read
// this Worker's answers, so other websites can't build on it in their
// visitors' browsers. Anything that isn't a browser (curl, a script, a server)
// can send any Origin header, or none, and CORS does nothing to stop it. The
// real gate is the sign-in check in authenticate() and, when COMPANY_ID is set,
// the membership check in authorize() below, which every /v1 request must pass
// whatever its origin.

/**
 * @param {string | null} origin
 * @param {Set<string>} allowed
 */
function corsFor(origin, allowed) {
  /** @type {Record<string, string>} */
  const headers = { Vary: 'Origin' };
  // No Origin header: not a cross-origin browser request (curl, a server).
  if (origin === null) return { forbidden: false, headers };
  // Only exact entries match: a "*" in ALLOWED_ORIGINS matches no origin.
  if (!allowed.has(normalizeOrigin(origin))) return { forbidden: true, headers };
  headers['Access-Control-Allow-Origin'] = origin;
  headers['Access-Control-Expose-Headers'] = 'Retry-After';
  return { forbidden: false, headers };
}

/**
 * The headers the app may send. Besides the token and the JSON type, the
 * company, the feature and the kinds of data a request holds, which later
 * versions of the app send (and of the Worker check): allowed now so that a
 * newer app never fails its preflight here, and ignored.
 */
const ALLOWED_REQUEST_HEADERS = [
  'Authorization',
  'Content-Type',
  'X-Maham-Company',
  'X-Maham-Feature',
  'X-Maham-Shares',
].join(', ');

/** @param {Record<string, string>} cors */
function preflight(cors) {
  /** @type {Record<string, string>} */
  const headers = { ...cors };
  if (headers['Access-Control-Allow-Origin']) {
    headers['Access-Control-Allow-Methods'] = 'POST, GET, OPTIONS';
    headers['Access-Control-Allow-Headers'] = ALLOWED_REQUEST_HEADERS;
    headers['Access-Control-Max-Age'] = '86400';
  }
  return new Response(null, { status: 204, headers: { ...headers, ...SECURITY_HEADERS } });
}

// ---------------------------------------------------------------------------
// The /v1 routes

/**
 * @param {Request} request
 * @param {Config} config
 * @param {{stream: boolean, cors: Record<string, string>, entry: LogEntry, started: number,
 *   deferred: {log: boolean}}} context
 */
async function handleAi(request, config, context) {
  assertConfigured(config);
  // Cheap checks first, so oversized requests never reach Supabase.
  checkDeclaredLength(request, config.maxBodyBytes);
  const user = await authenticate(request, config);
  context.entry.user = await hashUserId(user.userId);
  context.entry.auth = user.cached ? 'cache' : 'checked';
  // Before the membership check, so an account outside the company can't
  // make the Worker call Supabase more than the limit allows either.
  await enforceRateLimit(config.limiter, user.userId);
  await authorize(user, config);
  const input = await readJsonBody(request, config.maxBodyBytes);
  const { model, body } = buildGeminiRequest(input, config);
  context.entry.model = model;
  return context.stream
    ? streamAnswer(request, config, model, body, context)
    : generateAnswer(request, config, model, body, context);
}

// ---------------------------------------------------------------------------
// Authentication: the signed-in person's Supabase access token

/**
 * @typedef {object} SignedIn
 * @property {string} userId The Supabase user id.
 * @property {boolean} cached True when this token passed the checks for the
 *   current COMPANY_ID (signed in, and a member of one of its companies when it
 *   names any) less than a minute ago.
 * @property {string} token The access token, only for the membership check.
 * @property {string} cacheKey The SHA-256 of the token.
 * @property {number} until How long a positive result may be remembered.
 */

/**
 * Checks the Bearer token with Supabase (GET /auth/v1/user), which works for
 * both the older HS256 tokens and the newer asymmetric ones. A token that has
 * passed both this and authorize() is remembered for at most AUTH_CACHE_MS,
 * and never past its expiry.
 * @param {Request} request
 * @param {Config} config
 * @returns {Promise<SignedIn>}
 */
async function authenticate(request, config) {
  const header = request.headers.get('Authorization') ?? '';
  const match = /^Bearer\s+(\S+)$/i.exec(header.trim());
  if (!match || match[1].length > MAX_TOKEN_LENGTH) {
    throw new ProxyError('unauthorized', 'Sign in to use the AI assistant.');
  }
  const token = match[1];
  const cacheKey = await sha256Hex(token);

  const cached = authCache.get(cacheKey);
  if (cached && cached.until > Date.now() && cached.companies === config.companies) {
    return { userId: cached.userId, cached: true, token, cacheKey, until: cached.until };
  }
  if (cached) authCache.delete(cacheKey);

  const response = await askSupabase(`${config.supabaseUrl}/auth/v1/user`, token, config, 'auth');

  // Supabase answers 401 or 403 for a bad or expired token (400 for some
  // malformed ones, 404 when the account was deleted).
  if ([400, 401, 403, 404].includes(response.status)) {
    const reply = await response.text().catch(() => '');
    if (response.status === 401 && /invalid api key/i.test(reply)) {
      // Everyone would be refused: the Worker's own setting is wrong.
      throw new ProxyError('internal', 'The AI service is not set up correctly.', {
        log: { problem: 'Supabase refused SUPABASE_PUBLISHABLE_KEY' },
      });
    }
    throw expiredSignIn({ authStatus: response.status });
  }
  if (!response.ok) {
    await discard(response);
    throw new ProxyError('upstream_error', 'Could not check your sign-in. Try again.', {
      log: { authStatus: response.status },
    });
  }

  /** @type {any} */
  const user = await response.json().catch(() => null);
  if (!user || typeof user.id !== 'string' || !USER_ID.test(user.id)) {
    throw new ProxyError('unauthorized', 'Your sign-in is not valid. Sign in again.');
  }
  if (user.is_anonymous === true) {
    throw new ProxyError('unauthorized', 'Sign in with your account to use the AI assistant.');
  }

  const until = Math.min(Date.now() + AUTH_CACHE_MS, tokenExpiry(token) ?? 0);
  return { userId: user.id, cached: false, token, cacheKey, until };
}

/**
 * With COMPANY_ID empty, everyone signed in may use the service, and nothing
 * more is asked. With COMPANY_ID set, only members of at least one of its
 * companies may. The app lets anyone create an account (and then a company of
 * their own), so then a valid sign-in alone is not enough.
 *
 * The question goes to Supabase's REST API with the person's own token, so
 * the database's row-level security answers it: a member can read their
 * company's rows in company_members, and nobody else can. No service key is
 * needed. One request covers every company in the list. A positive answer
 * (or, when open, the sign-in alone) is remembered together with the sign-in.
 * @param {SignedIn} user
 * @param {Config} config
 */
async function authorize(user, config) {
  if (user.cached) return;
  if (config.companyIds.length > 0) await checkMembership(user, config);
  if (user.until > Date.now()) {
    remember(user.cacheKey, {
      userId: user.userId,
      companies: config.companies,
      until: user.until,
    });
  }
}

/**
 * One company_members request for every company in COMPANY_ID: a row comes
 * back only if the person is a member of at least one of them.
 * @param {SignedIn} user
 * @param {Config} config
 */
async function checkMembership(user, config) {
  const ids = config.companyIds;
  // Company ids are only letters, digits, "-" and "_" (checked in
  // assertConfigured), so they are safe inside in.(...).
  const query = new URLSearchParams({
    select: 'role',
    company_id: ids.length === 1 ? `eq.${ids[0]}` : `in.(${ids.join(',')})`,
    user_id: `eq.${user.userId}`,
    limit: '1',
  });
  const response = await askSupabase(
    `${config.supabaseUrl}/rest/v1/company_members?${query}`,
    user.token,
    config,
    'membership',
  );
  if (response.status === 401) {
    await discard(response);
    throw expiredSignIn({ memberStatus: 401 });
  }
  if (!response.ok) {
    await discard(response);
    throw new ProxyError('upstream_error', 'Could not check your access. Try again.', {
      log: { memberStatus: response.status },
    });
  }
  /** @type {unknown} */
  const rows = await response.json().catch(() => null);
  if (!Array.isArray(rows)) {
    throw new ProxyError('upstream_error', 'Could not check your access. Try again.', {
      log: { memberStatus: response.status, failure: 'membership answer not a list' },
    });
  }
  if (rows.length === 0) {
    throw new ProxyError(
      'forbidden',
      'This account is not a member of the company that uses this AI service.',
    );
  }
}

/**
 * GET from Supabase with the person's token and the publishable key.
 * @param {string} url
 * @param {string} token
 * @param {Config} config
 * @param {'auth' | 'membership'} what For the log line.
 */
async function askSupabase(url, token, config, what) {
  try {
    return await fetch(url, {
      headers: {
        apikey: config.supabaseKey,
        Authorization: `Bearer ${token}`,
        Accept: 'application/json',
      },
      signal: AbortSignal.timeout(AUTH_TIMEOUT_MS),
    });
  } catch (error) {
    if (errorName(error) === 'TimeoutError') {
      throw new ProxyError('upstream_timeout', 'Checking your sign-in took too long. Try again.', {
        log: { failure: `${what} timeout` },
      });
    }
    throw new ProxyError('upstream_error', 'Could not check your sign-in. Try again.', {
      log: { failure: `${what} ${errorName(error)}` },
    });
  }
}

/** @param {LogEntry} log */
function expiredSignIn(log) {
  return new ProxyError(
    'unauthorized',
    'Your sign-in has expired or is not valid. Sign in again.',
    { log },
  );
}

/**
 * The token's exp claim in milliseconds, or null. Only used to limit the
 * cache: Supabase has already checked the signature.
 * @param {string} token
 */
function tokenExpiry(token) {
  const payload = token.split('.')[1];
  if (!payload) return null;
  try {
    const base64 = payload.replace(/-/g, '+').replace(/_/g, '/');
    const claims = JSON.parse(atob(base64.padEnd(Math.ceil(base64.length / 4) * 4, '=')));
    return typeof claims?.exp === 'number' && Number.isFinite(claims.exp)
      ? claims.exp * 1000
      : null;
  } catch {
    return null;
  }
}

/**
 * @param {string} key
 * @param {{userId: string, companies: string, until: number}} value
 */
function remember(key, value) {
  if (authCache.size >= AUTH_CACHE_MAX_ENTRIES) {
    const now = Date.now();
    for (const [k, v] of authCache) if (v.until <= now) authCache.delete(k);
    // Still full: drop the oldest.
    if (authCache.size >= AUTH_CACHE_MAX_ENTRIES) {
      const oldest = authCache.keys().next().value;
      if (oldest !== undefined) authCache.delete(oldest);
    }
  }
  authCache.set(key, value);
}

/** @param {string} value */
async function sha256Hex(value) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

/** A short, stable stand-in for the user id in logs. @param {string} userId */
async function hashUserId(userId) {
  return (await sha256Hex(`maham-ai-proxy:user:${userId}`)).slice(0, 16);
}

// ---------------------------------------------------------------------------
// Limits

/**
 * Per-user limit from the Rate Limiting binding. Without the binding (in
 * tests, or if it wasn't added in the dashboard) requests are not limited
 * here; Google's own quotas still apply.
 * @param {RateLimiter | undefined} limiter
 * @param {string} userId
 */
async function enforceRateLimit(limiter, userId) {
  if (!limiter || typeof limiter.limit !== 'function') return;
  /** @type {{success: boolean}} */
  let outcome;
  try {
    outcome = await limiter.limit({ key: userId });
  } catch (error) {
    // The limiter is a guard against runaway loops, not a lock: if it fails,
    // the request goes on and the failure is logged.
    console.warn(JSON.stringify({ event: 'rate_limiter_failed', failure: errorName(error) }));
    return;
  }
  if (!outcome?.success) {
    throw new ProxyError('rate_limited', 'Too many AI requests. Wait a minute and try again.', {
      headers: { 'Retry-After': String(RATE_LIMIT_RETRY_AFTER_S) },
    });
  }
}

/**
 * @param {Request} request
 * @param {number} maxBytes
 */
function checkDeclaredLength(request, maxBytes) {
  const declared = request.headers.get('Content-Length');
  if (declared !== null && Number(declared) > maxBytes) throw tooLarge(maxBytes);
}

/** @param {number} maxBytes */
function tooLarge(maxBytes) {
  return new ProxyError(
    'payload_too_large',
    `The request is too large. The limit is ${Math.floor(maxBytes / 1024)} KB.`,
  );
}

/**
 * Reads the body, stopping as soon as it passes maxBytes (a missing or wrong
 * Content-Length doesn't get around the limit).
 * @param {Request} request
 * @param {number} maxBytes
 * @returns {Promise<unknown>}
 */
async function readJsonBody(request, maxBytes) {
  if (!request.body) throw badRequest('Send the request as JSON.');
  const reader = request.body.getReader();
  /** @type {Uint8Array[]} */
  const chunks = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > maxBytes) {
      await reader.cancel().catch(() => {});
      throw tooLarge(maxBytes);
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  /** @type {string} */
  let json;
  try {
    json = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } catch {
    throw badRequest('The request is not valid UTF-8 text.');
  }
  try {
    return JSON.parse(json);
  } catch {
    // Never put the parser's message in an error or a log: it quotes the body.
    throw badRequest('The request is not valid JSON.');
  }
}

/**
 * Builds what is sent to Google from the fields the app needs, with the model
 * checked against the allowlist and the answer length capped. Every object is
 * rebuilt from the ALLOWED_* lists above; nothing from the request is passed
 * on without going through them.
 * @param {unknown} input
 * @param {Config} config
 * @returns {{model: string, body: Record<string, unknown>}}
 */
function buildGeminiRequest(input, config) {
  if (!isObject(input)) throw badRequest('The request must be a JSON object.');

  const model = input.model === undefined ? config.defaultModel : input.model;
  if (typeof model !== 'string' || !config.models.has(model)) {
    throw new ProxyError(
      'model_not_allowed',
      `That model is not available here. Use one of: ${[...config.models].join(', ')}.`,
    );
  }

  const { contents } = input;
  if (!Array.isArray(contents) || contents.length === 0) {
    throw badRequest('contents must be a list with at least one item.');
  }
  if (contents.length > MAX_CONTENTS)
    throw badRequest(`contents may have at most ${MAX_CONTENTS} items.`);
  const files = { count: 0 };
  /** @type {Record<string, unknown>} */
  const body = { contents: contents.map((content) => cleanContent(content, files)) };

  if (input.systemInstruction !== undefined) {
    body.systemInstruction = cleanSystemInstruction(input.systemInstruction);
  }
  body.generationConfig = cleanGenerationConfig(input.generationConfig, config);

  if (input.safetySettings !== undefined) {
    if (!Array.isArray(input.safetySettings)) {
      throw badRequest('safetySettings must be a list of objects.');
    }
    body.safetySettings = input.safetySettings.map((setting) =>
      pick(setting, ALLOWED_SAFETY_FIELDS, 'Each item in safetySettings'),
    );
  }

  if (input.tools !== undefined) {
    // Function calling only. Google Search, URL context and code execution
    // would send data to other services or bill separately, so they are refused.
    if (!Array.isArray(input.tools)) throw badRequest(ONLY_FUNCTIONS);
    body.tools = input.tools.map((tool) => {
      const clean = pick(tool, ALLOWED_TOOL_FIELDS, 'Each item in tools', ONLY_FUNCTIONS);
      if (!Array.isArray(clean.functionDeclarations)) throw badRequest(ONLY_FUNCTIONS);
      clean.functionDeclarations = clean.functionDeclarations.map((declaration) => {
        const fn = pick(declaration, ALLOWED_FUNCTION_FIELDS, 'Each function declaration');
        if (typeof fn.name !== 'string')
          throw badRequest('Each function declaration needs a name.');
        return fn;
      });
      return clean;
    });
  }

  if (input.toolConfig !== undefined) {
    const toolConfig = pick(input.toolConfig, ALLOWED_TOOL_CONFIG_FIELDS, 'toolConfig');
    if (toolConfig.functionCallingConfig !== undefined) {
      toolConfig.functionCallingConfig = pick(
        toolConfig.functionCallingConfig,
        ALLOWED_CALLING_CONFIG_FIELDS,
        'toolConfig.functionCallingConfig',
      );
    }
    body.toolConfig = toolConfig;
  }

  return { model, body };
}

/**
 * @param {unknown} content
 * @param {{count: number}} files Inline files seen so far in the request.
 */
function cleanContent(content, files) {
  const where = 'contents';
  const clean = pick(content, ALLOWED_CONTENT_FIELDS, `Each item in ${where}`);
  if (clean.role !== undefined && clean.role !== 'user' && clean.role !== 'model') {
    throw badRequest('role must be "user" or "model".');
  }
  if (!Array.isArray(clean.parts)) {
    throw badRequest(`Each item in ${where} must be an object with a list of parts.`);
  }
  clean.parts = clean.parts.map((part) => cleanPart(part, where, files));
  return clean;
}

/**
 * @param {unknown} part
 * @param {string} where
 * @param {{count: number}} files
 */
function cleanPart(part, where, files) {
  if (isObject(part) && (part.fileData !== undefined || part.file_data !== undefined)) {
    // A file link makes Google fetch a file of any size, outside the body limit.
    throw badRequest('File links (fileData) are not accepted. Send the file inline (inlineData).');
  }
  const clean = pick(part, ALLOWED_PART_FIELDS, `Each part in ${where}`);
  if (clean.text !== undefined && typeof clean.text !== 'string') {
    throw badRequest('text must be a string.');
  }
  if (clean.thought !== undefined && typeof clean.thought !== 'boolean') {
    throw badRequest('thought must be true or false.');
  }
  if (clean.thoughtSignature !== undefined && typeof clean.thoughtSignature !== 'string') {
    throw badRequest('thoughtSignature must be a string.');
  }
  if (clean.inlineData !== undefined) {
    files.count += 1;
    if (files.count > MAX_INLINE_PARTS) {
      throw badRequest(`A request may hold at most ${MAX_INLINE_PARTS} files (inlineData).`);
    }
    const inline = pick(clean.inlineData, ALLOWED_INLINE_FIELDS, 'inlineData');
    const type = typeof inline.mimeType === 'string' ? inline.mimeType.trim().toLowerCase() : '';
    if (!ALLOWED_INLINE_TYPES.includes(type)) {
      throw badRequest(
        'inlineData may only hold a picture (PNG, JPEG, WebP, HEIC), a PDF or plain text.',
      );
    }
    if (typeof inline.data !== 'string' || inline.data === '') {
      throw badRequest('inlineData.data must be the file as base64 text.');
    }
    clean.inlineData = { mimeType: type, data: inline.data };
  }
  if (clean.functionCall !== undefined) {
    const call = pick(clean.functionCall, ALLOWED_FUNCTION_CALL_FIELDS, 'functionCall');
    if (typeof call.name !== 'string') throw badRequest('functionCall needs a name.');
    if (call.args !== undefined && !isObject(call.args)) {
      throw badRequest('functionCall.args must be an object.');
    }
    clean.functionCall = call;
  }
  if (clean.functionResponse !== undefined) {
    // Not functionResponse.parts: those can carry file links too.
    const reply = pick(
      clean.functionResponse,
      ALLOWED_FUNCTION_RESPONSE_FIELDS,
      'functionResponse',
    );
    if (typeof reply.name !== 'string') throw badRequest('functionResponse needs a name.');
    if (reply.response !== undefined && !isObject(reply.response)) {
      throw badRequest('functionResponse.response must be an object.');
    }
    clean.functionResponse = reply;
  }
  return clean;
}

/**
 * The system instruction: text parts only.
 * @param {unknown} instruction
 */
function cleanSystemInstruction(instruction) {
  const where = 'systemInstruction';
  const clean = pick(instruction, ALLOWED_CONTENT_FIELDS, where);
  if (!Array.isArray(clean.parts)) {
    throw badRequest(`${where} must be an object with a list of parts.`);
  }
  clean.parts = clean.parts.map((part) => {
    if (isObject(part) && (part.fileData !== undefined || part.file_data !== undefined)) {
      throw badRequest(
        'File links (fileData) are not accepted. Send the file inline (inlineData).',
      );
    }
    const text = pick(part, ['text'], `Each part in ${where}`, 'Only text is accepted there.');
    if (typeof text.text !== 'string') throw badRequest(`Each part in ${where} must be text.`);
    return text;
  });
  return clean;
}

/**
 * @param {unknown} input
 * @param {Config} config The cap (MAX_OUTPUT_TOKENS) and the default answer
 *   length (DEFAULT_ANSWER_TOKENS).
 */
function cleanGenerationConfig(input, config) {
  const { maxOutputTokens } = config;
  if (input !== undefined && !isObject(input)) {
    throw badRequest('generationConfig must be an object.');
  }
  const clean = pick(input ?? {}, ALLOWED_GENERATION_FIELDS, 'generationConfig');

  const asked = clean.maxOutputTokens;
  if (asked === undefined) {
    // Not the most allowed: a request that doesn't say gets a chat answer's length.
    clean.maxOutputTokens = Math.min(config.answerTokens, maxOutputTokens);
  } else if (!isWholeNumber(asked) || asked < 1) {
    throw badRequest('generationConfig.maxOutputTokens must be a whole number above 0.');
  } else {
    clean.maxOutputTokens = Math.min(asked, maxOutputTokens);
  }
  // One answer per request, always: more candidates would multiply the cost.
  clean.candidateCount = 1;

  if (clean.mediaResolution !== undefined) {
    if (!ALLOWED_MEDIA_RESOLUTIONS.includes(/** @type {any} */ (clean.mediaResolution))) {
      throw badRequest(
        'generationConfig.mediaResolution may only be MEDIA_RESOLUTION_LOW or MEDIA_RESOLUTION_MEDIUM.',
      );
    }
  }

  if (clean.thinkingConfig !== undefined) {
    const thinking = pick(
      clean.thinkingConfig,
      ALLOWED_THINKING_FIELDS,
      'generationConfig.thinkingConfig',
    );
    const budget = thinking.thinkingBudget;
    if (budget !== undefined) {
      // -1 lets the model decide; 0 turns thinking off where the model allows it.
      if (!isWholeNumber(budget) || budget < -1) {
        throw badRequest('thinkingConfig.thinkingBudget must be a whole number, -1 or more.');
      }
      // Never more than MAX_THINKING_BUDGET: "let the model decide" is that much at most.
      const most = Math.min(MAX_THINKING_BUDGET, maxOutputTokens);
      thinking.thinkingBudget = budget === -1 ? most : Math.min(budget, most);
    }
    const level = thinking.thinkingLevel;
    if (typeof level === 'string' && LOWERED_THINKING_LEVELS.includes(level.toLowerCase())) {
      // Kept cheap: a higher level is sent as the default one.
      thinking.thinkingLevel = DEFAULT_THINKING_LEVEL;
    }
    clean.thinkingConfig = thinking;
  } else {
    // Cheap thinking unless the request chose: the model's own default thinks more.
    clean.thinkingConfig = { thinkingLevel: DEFAULT_THINKING_LEVEL };
  }
  return clean;
}

/**
 * A copy of `source` with only the `allowed` keys, refusing any other key
 * rather than dropping it, so the app learns at once that Google never saw it.
 * @param {unknown} source
 * @param {readonly string[]} allowed
 * @param {string} where What the object is, for the error message.
 * @param {string} [hint] Added to the message for an unknown key.
 * @returns {Record<string, any>}
 */
function pick(source, allowed, where, hint) {
  if (!isObject(source)) throw badRequest(`${where} must be an object.`);
  /** @type {Record<string, any>} */
  const clean = {};
  for (const key of Object.keys(source)) {
    if (!allowed.includes(key)) {
      const name = /^[A-Za-z0-9_]{1,40}$/.test(key) ? `"${key}"` : 'that field';
      throw badRequest(`${where} may not hold ${name}.${hint ? ` ${hint}` : ''}`);
    }
    clean[key] = source[key];
  }
  return clean;
}

/**
 * @param {unknown} value
 * @returns {value is number}
 */
function isWholeNumber(value) {
  return typeof value === 'number' && Number.isInteger(value);
}

/**
 * @param {unknown} value
 * @returns {value is Record<string, any>}
 */
function isObject(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

// ---------------------------------------------------------------------------
// Calling Google

/**
 * One call to Google: aborted when it takes too long, or when the app goes away.
 */
class UpstreamCall {
  /**
   * @param {Request} request
   * @param {number} timeoutMs Until stopTimer() or done() is called.
   */
  constructor(request, timeoutMs) {
    this.controller = new AbortController();
    /** @type {'timeout' | 'client' | null} */
    this.reason = null;
    this.timer = setTimeout(() => this.abort('timeout'), timeoutMs);
    this.clientSignal = request.signal;
    this.onClientGone = () => this.abort('client');
    if (this.clientSignal?.aborted) this.abort('client');
    else this.clientSignal?.addEventListener('abort', this.onClientGone);
  }

  get signal() {
    return this.controller.signal;
  }

  /** @param {'timeout' | 'client'} reason */
  abort(reason) {
    this.reason ??= reason;
    this.controller.abort();
  }

  stopTimer() {
    clearTimeout(this.timer);
  }

  done() {
    clearTimeout(this.timer);
    this.clientSignal?.removeEventListener('abort', this.onClientGone);
  }

  /**
   * What a failure means, given why (if at all) the call was aborted.
   * @param {unknown} error
   */
  explain(error) {
    if (error instanceof ProxyError) return error;
    if (this.reason === 'timeout') {
      return new ProxyError(
        'upstream_timeout',
        'The AI service took too long to answer. Try again.',
      );
    }
    if (this.reason === 'client') {
      // Nobody reads this answer: the app has gone. It is only logged.
      return new ProxyError('bad_request', 'The request was cancelled.', {
        status: 499,
        log: { cancelled: true },
      });
    }
    return new ProxyError('upstream_error', 'Could not reach the AI service. Try again.', {
      log: { failure: errorName(error) },
    });
  }
}

/**
 * @param {string} model Already checked against the allowlist and MODEL_NAME.
 * @param {boolean} stream
 * @param {Record<string, unknown>} body
 * @param {string} apiKey
 * @param {AbortSignal} signal
 */
function callGemini(model, stream, body, apiKey, signal) {
  const method = stream ? 'streamGenerateContent?alt=sse' : 'generateContent';
  return fetch(`${GEMINI_MODELS_URL}${encodeURIComponent(model)}:${method}`, {
    method: 'POST',
    // The key goes only in this header, never in the URL (where it could end
    // up in logs). Nothing from the app's request headers is passed on: not
    // the person's token, not their cookies.
    headers: { 'Content-Type': 'application/json', 'x-goog-api-key': apiKey },
    body: JSON.stringify(body),
    signal,
  });
}

/**
 * POST /v1/generate: waits for the whole answer and returns Gemini's JSON.
 * Google sends nothing until the answer is complete, so GENERATE_TIMEOUT_MS
 * covers the whole call, reading the answer included.
 * @param {Request} request
 * @param {Config} config
 * @param {string} model
 * @param {Record<string, unknown>} body
 * @param {{cors: Record<string, string>, entry: LogEntry}} context
 */
async function generateAnswer(request, config, model, body, context) {
  const call = new UpstreamCall(request, config.generateTimeoutMs);
  try {
    const upstream = await callGemini(model, false, body, config.apiKey, call.signal);
    if (!upstream.ok) throw await upstreamFailure(upstream, config.apiKey);
    const raw = await upstream.text();
    /** @type {unknown} */
    let data;
    try {
      data = JSON.parse(raw);
    } catch {
      throw new ProxyError(
        'upstream_error',
        'The AI service sent an answer that could not be read.',
      );
    }
    context.entry.usage = usageOf(data);
    return jsonResponse(data, 200, context.cors);
  } catch (error) {
    throw call.explain(error);
  } finally {
    call.done();
  }
}

/**
 * POST /v1/stream: passes Gemini's Server-Sent Events through as they come.
 * Until Google's first byte arrives (at most STREAM_START_TIMEOUT_MS) a
 * failure is an ordinary JSON error; after that, the stream ends with an
 * "error" event, and only pauses longer than STREAM_IDLE_TIMEOUT_MS end it.
 * @param {Request} request
 * @param {Config} config
 * @param {string} model
 * @param {Record<string, unknown>} body
 * @param {{cors: Record<string, string>, entry: LogEntry, started: number,
 *   deferred: {log: boolean}}} context
 */
async function streamAnswer(request, config, model, body, context) {
  const call = new UpstreamCall(request, config.streamStartMs);
  /** @type {ReadableStreamDefaultReader<Uint8Array> | undefined} */
  let reader;
  /** @type {Uint8Array} */
  let first;
  try {
    const upstream = await callGemini(model, true, body, config.apiKey, call.signal);
    if (!upstream.ok) throw await upstreamFailure(upstream, config.apiKey);
    if (!upstream.body)
      throw new ProxyError('upstream_error', 'The AI service sent an empty answer.');
    reader = upstream.body.getReader();
    const read = await reader.read();
    if (read.done) throw new ProxyError('upstream_error', 'The AI service sent an empty answer.');
    first = read.value;
  } catch (error) {
    call.done();
    reader?.cancel().catch(() => {});
    throw call.explain(error);
  }
  call.stopTimer();

  context.deferred.log = true;
  const { entry, started } = context;
  const stream = relayEvents(reader, first, call, config.streamIdleMs, (status, extra) => {
    call.done();
    writeLog({ ...entry, ...extra }, status, started);
  });
  return new Response(stream, {
    status: 200,
    headers: {
      'Content-Type': 'text/event-stream; charset=utf-8',
      ...context.cors,
      ...SECURITY_HEADERS,
    },
  });
}

/**
 * Hands each chunk from Google to the app as soon as the app is ready for it,
 * without collecting them (highWaterMark 0). Token counts are read from the
 * last event that has them, for the log.
 * @param {ReadableStreamDefaultReader<Uint8Array>} reader
 * @param {Uint8Array} first
 * @param {UpstreamCall} call
 * @param {number} idleMs
 * @param {(status: number, extra: LogEntry) => void} finish
 */
function relayEvents(reader, first, call, idleMs, finish) {
  const usage = usageTracker();
  usage.push(first);
  /** @type {Uint8Array | null} */
  let pending = first;
  let ended = false;
  /**
   * @param {number} status
   * @param {LogEntry} extra
   */
  const end = (status, extra) => {
    if (ended) return;
    ended = true;
    finish(status, { usage: usage.result(), ...extra });
  };
  // When the app disconnects, the Workers runtime fires request.signal (with
  // the enable_request_signal flag) rather than cancelling this stream, and
  // then stops the request: UpstreamCall has already aborted Google by then,
  // and this writes the log line while it still can.
  call.clientSignal?.addEventListener('abort', () => end(499, { cancelled: true }), { once: true });

  return new ReadableStream(
    {
      async pull(controller) {
        if (pending) {
          controller.enqueue(pending);
          pending = null;
          return;
        }
        try {
          const { done, value } = await readWithin(reader, idleMs, () => call.abort('timeout'));
          if (done) {
            controller.close();
            end(200, {});
            return;
          }
          usage.push(value);
          controller.enqueue(value);
        } catch (error) {
          const failure =
            call.reason === null
              ? new ProxyError(
                  'upstream_error',
                  'The AI service stopped in the middle of the answer.',
                  {
                    log: { failure: errorName(error) },
                  },
                )
              : call.explain(error);
          // The blank lines first end any event Google left half-written.
          controller.enqueue(
            new TextEncoder().encode(
              `\n\nevent: error\ndata: ${JSON.stringify(errorBody(failure))}\n\n`,
            ),
          );
          controller.close();
          end(200, { code: failure.code, streamError: failure.status, ...failure.log });
        }
      },
      cancel() {
        // The app closed the connection: stop Google too.
        call.abort('client');
        reader.cancel().catch(() => {});
        end(499, { cancelled: true });
      },
    },
    { highWaterMark: 0 },
  );
}

/**
 * @param {ReadableStreamDefaultReader<Uint8Array>} reader
 * @param {number} ms
 * @param {() => void} onTimeout
 * @returns {Promise<ReadableStreamReadResult<Uint8Array>>}
 */
function readWithin(reader, ms, onTimeout) {
  /** @type {ReturnType<typeof setTimeout> | undefined} */
  let timer;
  /** @type {Promise<never>} */
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => {
      onTimeout();
      reject(new Error('stream idle'));
    }, ms);
  });
  return Promise.race([reader.read(), timeout]).finally(() => clearTimeout(timer));
}

/**
 * Finds the token counts in Gemini's SSE events (the last event that has
 * usageMetadata holds the totals). Only the counts are ever kept for the log.
 */
function usageTracker() {
  const decoder = new TextDecoder();
  let partial = '';
  let last = '';
  let tracking = true;
  return {
    /** @param {Uint8Array} chunk */
    push(chunk) {
      if (!tracking) return;
      const lines = (partial + decoder.decode(chunk, { stream: true })).split('\n');
      partial = lines.pop() ?? '';
      if (partial.length > 1_000_000) {
        tracking = false;
        partial = '';
        last = '';
        return;
      }
      for (const line of lines) {
        if (line.startsWith('data:') && line.includes('"usageMetadata"')) last = line;
      }
    },
    result() {
      if (!last) return undefined;
      try {
        return usageOf(JSON.parse(last.slice('data:'.length)));
      } catch {
        return undefined;
      }
    },
  };
}

/**
 * Token counts from Gemini's usageMetadata, for the log.
 * @param {unknown} data
 */
function usageOf(data) {
  const usage = isObject(data) && isObject(data.usageMetadata) ? data.usageMetadata : null;
  if (!usage) return undefined;
  /** @param {string} key */
  const count = (key) => (Number.isFinite(usage[key]) ? usage[key] : undefined);
  return {
    prompt: count('promptTokenCount'),
    output: count('candidatesTokenCount'),
    thoughts: count('thoughtsTokenCount'),
    total: count('totalTokenCount'),
  };
}

/**
 * Turns Google's error into one of ours, with a short message that never
 * holds the key or Google's internal details.
 * @param {Response} response
 * @param {string} apiKey
 */
async function upstreamFailure(response, apiKey) {
  const { status } = response;
  const google = await readGoogleError(response);
  const log = { upstream: status, googleStatus: google.status, reason: google.reason };

  if (status === 429) {
    const wait = retryAfterSeconds(google.details, response.headers.get('Retry-After'));
    return new ProxyError(
      'rate_limited',
      `The AI service is busy or its quota is used up. Try again in ${wait} seconds.`,
      { headers: { 'Retry-After': String(wait) }, log },
    );
  }
  if (
    status === 401 ||
    status === 403 ||
    (google.reason !== undefined && google.reason.startsWith('API_KEY'))
  ) {
    return new ProxyError(
      'upstream_error',
      "The AI service did not accept this Worker's key. The owner needs to check the Gemini key.",
      { log },
    );
  }
  if (status === 400 && google.status === 'FAILED_PRECONDITION') {
    return new ProxyError(
      'upstream_error',
      "The AI service refused this account (billing or region). The owner needs to check the Gemini key's project.",
      { log },
    );
  }
  if (status === 400) {
    const detail = safeMessage(google.message, apiKey);
    return new ProxyError(
      'bad_request',
      detail
        ? `The AI service could not use this request: ${detail}`
        : 'The AI service could not use this request.',
      { log },
    );
  }
  if (status === 404) {
    return new ProxyError(
      'upstream_error',
      'The AI model is not available. The owner needs to update GEMINI_MODEL.',
      { log },
    );
  }
  if (status === 503) {
    const after = response.headers.get('Retry-After');
    return new ProxyError('upstream_error', 'The AI service is overloaded. Try again shortly.', {
      status: 503,
      headers: after && /^\d+$/.test(after) ? { 'Retry-After': after } : {},
      log,
    });
  }
  if (status === 504) {
    return new ProxyError(
      'upstream_timeout',
      'The AI service took too long to answer. Try again.',
      {
        log,
      },
    );
  }
  return new ProxyError('upstream_error', 'The AI service had a problem. Try again.', { log });
}

/**
 * @param {Response} response
 * @returns {Promise<{status?: string, reason?: string, message?: string, details: any[]}>}
 */
async function readGoogleError(response) {
  try {
    /** @type {any} */
    let parsed = JSON.parse((await response.text()).slice(0, 64 * 1024));
    if (Array.isArray(parsed)) parsed = parsed[0];
    const error = isObject(parsed) && isObject(parsed.error) ? parsed.error : {};
    const details = Array.isArray(error.details) ? error.details.filter(isObject) : [];
    const reason = details.find((d) => typeof d.reason === 'string')?.reason;
    return {
      status: typeof error.status === 'string' ? error.status.slice(0, 64) : undefined,
      reason: typeof reason === 'string' ? reason.slice(0, 64) : undefined,
      message: typeof error.message === 'string' ? error.message : undefined,
      details,
    };
  } catch {
    return { details: [] };
  }
}

/**
 * Seconds to wait, from Google's RetryInfo ("37s"), else its Retry-After
 * header, else 30.
 * @param {any[]} details
 * @param {string | null} header
 */
function retryAfterSeconds(details, header) {
  const info = details.find(
    (d) => typeof d['@type'] === 'string' && d['@type'].endsWith('google.rpc.RetryInfo'),
  );
  const delay =
    typeof info?.retryDelay === 'string' ? /^(\d+(?:\.\d+)?)s$/.exec(info.retryDelay) : null;
  let seconds = delay
    ? Math.ceil(Number(delay[1]))
    : header && /^\d+$/.test(header)
      ? Number(header)
      : 30;
  if (!Number.isFinite(seconds)) seconds = 30;
  return Math.min(Math.max(seconds, 1), 3600);
}

/**
 * Google's own message for a request it couldn't use, shortened and with
 * anything that looks like a key removed.
 * @param {string | undefined} message
 * @param {string} apiKey
 */
function safeMessage(message, apiKey) {
  if (!message) return '';
  let safe = apiKey ? message.split(apiKey).join('[hidden]') : message;
  safe = safe
    .replace(/AIza[0-9A-Za-z_-]{10,}/g, '[hidden]')
    .replace(/\s+/g, ' ')
    .trim();
  return safe.length > 200 ? `${safe.slice(0, 199)}…` : safe;
}

/** @param {Response} response */
async function discard(response) {
  await response.body?.cancel().catch(() => {});
}

// ---------------------------------------------------------------------------
// Responses and logs

/**
 * @param {unknown} data
 * @param {number} status
 * @param {Record<string, string>} headers
 */
function jsonResponse(data, status, headers) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', ...headers, ...SECURITY_HEADERS },
  });
}

function notFound() {
  return new ProxyError('not_found', 'Not found.');
}

/** @param {ProxyError} failure */
function errorBody(failure) {
  return { error: { code: failure.code, message: failure.message, status: failure.status } };
}

/**
 * @param {unknown} error
 * @param {Record<string, string>} cors
 * @param {LogEntry} entry
 */
function errorResponse(error, cors, entry) {
  const failure =
    error instanceof ProxyError
      ? error
      : new ProxyError('internal', 'Something went wrong in the AI service. Try again.', {
          log: { failure: errorName(error) },
        });
  Object.assign(entry, { code: failure.code }, failure.log);
  return jsonResponse(errorBody(failure), failure.status, { ...cors, ...failure.headers });
}

/**
 * Only an error's name is logged, never its message: messages can quote the
 * request (a JSON parser's do).
 * @param {unknown} error
 */
function errorName(error) {
  return error instanceof Error ? error.name : typeof error;
}

/**
 * One JSON line per request (Workers Logs and `wrangler tail` show it).
 * @param {LogEntry} entry
 * @param {number} status
 * @param {number} started
 */
function writeLog(entry, status, started) {
  const line = JSON.stringify({ ...entry, status, ms: Date.now() - started });
  if (status >= 500) console.error(line);
  else console.log(line);
}
