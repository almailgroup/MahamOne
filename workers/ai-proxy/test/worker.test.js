// @vitest-environment node
/**
 * Tests for the AI proxy Worker. Supabase and Google are replaced by a fake
 * global fetch; nothing here touches the network.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const KEY = 'AIzaSyTEST-not-a-real-key-0123456789abc';
const SUPABASE_URL = 'https://project-ref.supabase.co';
const PUBLISHABLE = 'sb_publishable_test-only';
const APP = 'https://mahamone.com';
const WORKER = 'https://maham-ai-proxy.example.workers.dev';
const COMPANY = 'maham-company-0001';
const USER_1 = '0f8fad5b-d9cb-469f-a165-70867728950e';
const USER_2 = '7c9e6679-7425-40de-944b-e07fc1f90ae7';
const GEMINI = 'https://generativelanguage.googleapis.com/v1beta/models/';
/** Marks text that must never appear in a log line. */
const PROMPT = 'PRIVATE-PROMPT What is the salary of employee 4471?';
const ANSWER = 'PRIVATE-ANSWER It is in the payroll.';

const base64url = (value) =>
  btoa(JSON.stringify(value)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const nowSeconds = () => Math.floor(Date.now() / 1000);

/** Every token a test made, so afterEach can check none of them was logged. */
let issued = [];
function jwt(claims) {
  const token = `${base64url({ alg: 'HS256', typ: 'JWT' })}.${base64url(claims)}.sig-${issued.length}`;
  issued.push(token);
  return token;
}

let worker;
let testing;
/** token -> the user Supabase answers with (or a Response to send instead). */
let users;
/** "companyId userId" for each member; what row-level security lets a member read. */
let members;
/** Replaces the fake company_members answer when set. */
let membership;
/** Answers the fake Google; replaced per test. */
let gemini;
let calls;
let logs;
let TOKEN;

beforeEach(async () => {
  vi.resetModules();
  ({ default: worker, __testing: testing } = await import('../src/worker.js'));
  issued = [];
  calls = [];
  logs = [];
  TOKEN = jwt({ sub: USER_1, exp: nowSeconds() + 3600 });
  users = new Map([[TOKEN, { id: USER_1, aud: 'authenticated', is_anonymous: false }]]);
  members = new Set([`${COMPANY} ${USER_1}`, `${COMPANY} ${USER_2}`]);
  membership = undefined;
  gemini = () => Response.json(geminiAnswer());
  vi.stubGlobal('fetch', vi.fn(fakeFetch));
  for (const level of ['log', 'info', 'warn', 'error', 'debug']) {
    vi.spyOn(console, level).mockImplementation((...args) => {
      logs.push(args.map(String).join(' '));
    });
  }
});

afterEach(() => {
  // Whatever a test did, no log line may hold the key, a token, a prompt, an
  // answer or a raw user id.
  const all = logs.join('\n');
  expect(all).not.toContain(KEY);
  for (const token of issued) expect(all).not.toContain(token);
  expect(all).not.toContain('PRIVATE-');
  expect(all).not.toContain(USER_1);
  expect(all).not.toContain(USER_2);
  expect(all).not.toContain(COMPANY);
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

async function fakeFetch(input, init = {}) {
  const url = typeof input === 'string' ? input : input.url;
  const call = {
    url,
    method: init.method ?? 'GET',
    headers: new Headers(init.headers),
    body: init.body,
    signal: init.signal,
  };
  calls.push(call);
  if (url === `${SUPABASE_URL}/auth/v1/user`) {
    const token = (call.headers.get('Authorization') ?? '').replace(/^Bearer /, '');
    const user = users.get(token);
    if (user instanceof Response) return user;
    if (typeof user === 'function') return user(call);
    return user
      ? Response.json(user)
      : Response.json({ code: 403, error_code: 'bad_jwt', msg: 'invalid JWT' }, { status: 403 });
  }
  if (url.startsWith(`${SUPABASE_URL}/rest/v1/company_members?`)) {
    if (membership) return membership(call);
    // Like PostgREST with row-level security: the token's own user, and only
    // rows of a company that user is a member of.
    const token = (call.headers.get('Authorization') ?? '').replace(/^Bearer /, '');
    const user = users.get(token);
    if (!user?.id) return Response.json({ code: 'PGRST301', message: 'JWT' }, { status: 401 });
    const query = new URL(url).searchParams;
    // company_id=eq.<id>, or in.(<id>,<id>) for several.
    const filter = query.get('company_id') ?? '';
    const list = /^in\.\((.*)\)$/.exec(filter);
    const companies = list ? list[1].split(',') : [filter.replace(/^eq\./, '')];
    const member = (query.get('user_id') ?? '').replace(/^eq\./, '');
    const visible = companies.some(
      (company) => members.has(`${company} ${user.id}`) && members.has(`${company} ${member}`),
    );
    return Response.json(visible ? [{ role: 'staff' }] : []);
  }
  if (url.startsWith(GEMINI)) return gemini(call);
  throw new Error(`Unexpected fetch to ${url}`);
}

const supabaseCalls = () => calls.filter((call) => call.url.startsWith(SUPABASE_URL));
const authCalls = () => calls.filter((call) => call.url === `${SUPABASE_URL}/auth/v1/user`);
const memberCalls = () => calls.filter((call) => call.url.includes('/rest/v1/company_members'));
const geminiCalls = () => calls.filter((call) => call.url.startsWith(GEMINI));
const geminiBody = (index = 0) => JSON.parse(geminiCalls()[index].body);

function makeEnv(overrides = {}) {
  return {
    GEMINI_API_KEY: KEY,
    GEMINI_MODEL: 'gemini-3.6-flash',
    ALLOWED_MODELS: 'gemini-3.6-flash, gemini-3.6-flash-lite',
    ALLOWED_ORIGINS: 'https://mahamone.com',
    SUPABASE_URL,
    SUPABASE_PUBLISHABLE_KEY: PUBLISHABLE,
    COMPANY_ID: COMPANY,
    MAX_OUTPUT_TOKENS: '1024',
    ...overrides,
  };
}

const question = { contents: [{ role: 'user', parts: [{ text: PROMPT }] }] };

/**
 * Sends a request to the Worker. `token: null` or `origin: null` leaves that
 * header out.
 */
function send(path, options = {}) {
  const {
    method = 'POST',
    body = question,
    token = TOKEN,
    origin = APP,
    headers = {},
    env = makeEnv(),
    signal,
  } = options;
  const h = new Headers(headers);
  if (origin) h.set('Origin', origin);
  if (token) h.set('Authorization', `Bearer ${token}`);
  /** @type {BodyInit | undefined} */
  let payload;
  if (method === 'POST') {
    payload =
      typeof body === 'string' || body instanceof ReadableStream || body instanceof Uint8Array
        ? body
        : JSON.stringify(body);
    if (!h.has('Content-Type')) h.set('Content-Type', 'application/json');
  }
  const request = new Request(WORKER + path, {
    method,
    headers: h,
    body: payload,
    signal,
    ...(payload instanceof ReadableStream ? { duplex: 'half' } : {}),
  });
  return worker.fetch(request, env);
}

function geminiAnswer(text = ANSWER) {
  return {
    candidates: [{ content: { role: 'model', parts: [{ text }] }, finishReason: 'STOP' }],
    usageMetadata: {
      promptTokenCount: 12,
      candidatesTokenCount: 34,
      thoughtsTokenCount: 5,
      totalTokenCount: 51,
    },
    modelVersion: 'gemini-3.6-flash',
  };
}

function googleError(status, error, headers = {}) {
  return Response.json({ error: { code: status, ...error } }, { status, headers });
}

/** A stream like Google's: aborting the fetch's signal errors it, as real fetch does. */
function sseBody(chunks, { signal, then = 'close' } = {}) {
  const encoder = new TextEncoder();
  let index = 0;
  return new ReadableStream(
    {
      start(controller) {
        signal?.addEventListener('abort', () => {
          try {
            controller.error(new DOMException('This operation was aborted', 'AbortError'));
          } catch {
            // already closed
          }
        });
      },
      pull(controller) {
        if (index < chunks.length) {
          controller.enqueue(encoder.encode(chunks[index++]));
          return undefined;
        }
        if (then === 'close') controller.close();
        else if (then === 'error') controller.error(new TypeError('Network connection lost.'));
        else return new Promise(() => {}); // 'hang': never sends again
        return undefined;
      },
    },
    { highWaterMark: 0 },
  );
}

function sseResponse(chunks, call, then) {
  return new Response(sseBody(chunks, { signal: call.signal, then }), {
    headers: { 'Content-Type': 'text/event-stream' },
  });
}

/** A fetch that only ends when its signal is aborted. */
function hang(call) {
  return new Promise((_, reject) => {
    call.signal.addEventListener('abort', () =>
      reject(new DOMException('This operation was aborted', 'AbortError')),
    );
  });
}

async function chunksOf(response) {
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  const out = [];
  for (;;) {
    const { done, value } = await reader.read();
    if (done) return out;
    out.push(decoder.decode(value));
  }
}

async function errorOf(response) {
  expect(response.headers.get('Content-Type')).toBe('application/json; charset=utf-8');
  const body = await response.json();
  expect(Object.keys(body)).toEqual(['error']);
  expect(Object.keys(body.error).sort()).toEqual(['code', 'message', 'status']);
  expect(body.error.status).toBe(response.status);
  return body.error;
}

function logLines() {
  return logs.flatMap((line) => {
    try {
      return [JSON.parse(line)];
    } catch {
      return [];
    }
  });
}

const until = async (check) => {
  for (let i = 0; i < 200 && !check(); i++) await new Promise((r) => setTimeout(r, 5));
};

async function sha256Hex(value) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

const STREAM_EVENTS = [
  'data: {"candidates":[{"content":{"parts":[{"text":"PRIVATE-ANSWER one"}],"role":"model"}}],"usageMetadata":{"promptTokenCount":12,"totalTokenCount":12}}\r\n\r\n',
  // An event split across two chunks, as the network may deliver it.
  'data: {"candidates":[{"content":{"parts":[{"text":" two"}],',
  '"role":"model"}}],"usageMetadata":{"promptTokenCount":12,"totalTokenCount":20}}\r\n\r\n',
  'data: {"candidates":[{"content":{"parts":[{"text":" three"}],"role":"model"},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":12,"candidatesTokenCount":30,"totalTokenCount":42}}\r\n\r\n',
];

describe('GET /health', () => {
  it('answers without a sign-in, with only ok and the model', async () => {
    const response = await send('/health', { method: 'GET', token: null });
    expect(response.status).toBe(200);
    const text = await response.text();
    expect(JSON.parse(text)).toEqual({ ok: true, model: 'gemini-3.6-flash' });
    expect(text).not.toContain(KEY);
    expect(text).not.toContain(PUBLISHABLE);
    expect(text).not.toContain('supabase');
    expect(calls).toHaveLength(0);
    expect(response.headers.get('Access-Control-Allow-Origin')).toBe(APP);
  });

  it('still answers when the key is missing, and never says so', async () => {
    const response = await send('/health', {
      method: 'GET',
      token: null,
      env: makeEnv({ GEMINI_API_KEY: undefined }),
    });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ok: true, model: 'gemini-3.6-flash' });
  });

  it('only answers GET', async () => {
    const response = await send('/health', { method: 'POST' });
    expect(response.status).toBe(404);
    expect((await errorOf(response)).code).toBe('not_found');
  });
});

describe('routing', () => {
  it.each([
    ['GET', '/'],
    ['GET', '/v1/generate'],
    ['GET', '/v1/stream'],
    ['POST', '/v1/unknown'],
    ['POST', '/v1/generate/'],
    ['POST', '/v2/generate'],
    ['PUT', '/v1/generate'],
    ['DELETE', '/health'],
  ])('%s %s is a JSON 404', async (method, path) => {
    const response = await send(path, { method });
    expect(response.status).toBe(404);
    expect(await errorOf(response)).toEqual({
      code: 'not_found',
      message: 'Not found.',
      status: 404,
    });
    expect(response.headers.get('Cache-Control')).toBe('no-store');
    expect(geminiCalls()).toHaveLength(0);
  });

  it('a preflight for an unknown path is a 404', async () => {
    const response = await send('/v1/files', { method: 'OPTIONS' });
    expect(response.status).toBe(404);
  });
});

describe('CORS', () => {
  it('allows every header the app sends, so its preflight never fails', async () => {
    const response = await send('/v1/stream', {
      method: 'OPTIONS',
      token: null,
      headers: {
        'Access-Control-Request-Method': 'POST',
        'Access-Control-Request-Headers': 'authorization,content-type',
      },
    });
    const allowed = (response.headers.get('Access-Control-Allow-Headers') ?? '')
      .split(',')
      .map((header) => header.trim().toLowerCase());
    // src/features/ai/client.ts: the token and the JSON body.
    for (const header of ['authorization', 'content-type']) expect(allowed).toContain(header);
    for (const header of ['x-maham-company', 'x-maham-feature', 'x-maham-shares']) {
      expect(allowed).toContain(header);
    }
  });

  it('echoes an allowed origin, with Vary and Retry-After readable', async () => {
    const response = await send('/v1/generate');
    expect(response.status).toBe(200);
    expect(response.headers.get('Access-Control-Allow-Origin')).toBe(APP);
    expect(response.headers.get('Vary')).toBe('Origin');
    expect(response.headers.get('Access-Control-Expose-Headers')).toBe('Retry-After');
  });

  it('answers a preflight from an allowed origin', async () => {
    for (const path of ['/v1/generate', '/v1/stream', '/health']) {
      const response = await send(path, {
        method: 'OPTIONS',
        token: null,
        headers: {
          'Access-Control-Request-Method': 'POST',
          'Access-Control-Request-Headers': 'authorization, content-type',
        },
      });
      expect(response.status).toBe(204);
      expect(response.headers.get('Access-Control-Allow-Origin')).toBe(APP);
      expect(response.headers.get('Access-Control-Allow-Methods')).toBe('POST, GET, OPTIONS');
      // What the app sends, and the headers later versions of it send (ignored here).
      expect(response.headers.get('Access-Control-Allow-Headers')).toBe(
        'Authorization, Content-Type, X-Maham-Company, X-Maham-Feature, X-Maham-Shares',
      );
      expect(response.headers.get('Access-Control-Max-Age')).toBe('86400');
      expect(response.headers.get('Vary')).toBe('Origin');
      expect(await response.text()).toBe('');
    }
    expect(calls).toHaveLength(0);
  });

  it.each([
    'https://evil.example',
    'https://mahamone.com.evil.example',
    'http://mahamone.com',
    'https://www.mahamone.com',
    'https://ai.mahamone.com',
    'null',
  ])('refuses %s with a 403 and no allow header, even with a valid token', async (origin) => {
    for (const method of ['POST', 'OPTIONS']) {
      const response = await send('/v1/generate', { method, origin });
      expect(response.status).toBe(403);
      expect(response.headers.get('Access-Control-Allow-Origin')).toBeNull();
      expect(response.headers.get('Access-Control-Allow-Methods')).toBeNull();
      expect(response.headers.get('Vary')).toBe('Origin');
      expect((await errorOf(response)).code).toBe('forbidden_origin');
    }
    expect(calls).toHaveLength(0);
  });

  it('lets a request without an Origin through to the sign-in check (CORS is not authentication)', async () => {
    const unsigned = await send('/v1/generate', { origin: null, token: null });
    expect(unsigned.status).toBe(401);
    expect(unsigned.headers.get('Access-Control-Allow-Origin')).toBeNull();

    const signed = await send('/v1/generate', { origin: null });
    expect(signed.status).toBe(200);
    expect(signed.headers.get('Access-Control-Allow-Origin')).toBeNull();
  });

  it('includes the allow header on errors, so the app can read them', async () => {
    const response = await send('/v1/generate', { token: null });
    expect(response.status).toBe(401);
    expect(response.headers.get('Access-Control-Allow-Origin')).toBe(APP);
  });

  it('uses the dev origins when configured, and only those', async () => {
    const env = makeEnv({ ALLOWED_ORIGINS: 'http://localhost:5173, http://127.0.0.1:5173/' });
    const local = await send('/v1/generate', { origin: 'http://localhost:5173', env });
    expect(local.status).toBe(200);
    expect(local.headers.get('Access-Control-Allow-Origin')).toBe('http://localhost:5173');
    const loopback = await send('/health', { method: 'GET', origin: 'http://127.0.0.1:5173', env });
    expect(loopback.status).toBe(200);
    const production = await send('/v1/generate', { origin: APP, env });
    expect(production.status).toBe(403);
    const otherPort = await send('/v1/generate', { origin: 'http://localhost:3000', env });
    expect(otherPort.status).toBe(403);
  });

  it('does not treat "*" as every origin', async () => {
    const env = makeEnv({ ALLOWED_ORIGINS: '*' });
    const response = await send('/v1/generate', { origin: 'https://evil.example', env });
    expect(response.status).toBe(403);
  });
});

describe('sign-in check', () => {
  it('refuses a request without a token, without asking Supabase', async () => {
    const response = await send('/v1/generate', { token: null });
    expect(response.status).toBe(401);
    expect((await errorOf(response)).code).toBe('unauthorized');
    expect(calls).toHaveLength(0);
  });

  it.each(['Basic dXNlcjpwYXNz', 'Bearer', 'Bearer ', 'Bearer a b', 'Token abc'])(
    'refuses the header %j',
    async (value) => {
      const response = await send('/v1/generate', {
        token: null,
        headers: { Authorization: value },
      });
      expect(response.status).toBe(401);
      expect(calls).toHaveLength(0);
    },
  );

  it('refuses an absurdly long token without asking Supabase', async () => {
    const response = await send('/v1/generate', { token: 'x'.repeat(9000) });
    expect(response.status).toBe(401);
    expect(calls).toHaveLength(0);
  });

  it('refuses a token Supabase rejects (401 or 403)', async () => {
    const bad = jwt({ sub: USER_2, exp: nowSeconds() + 3600 });
    const expired = jwt({ sub: USER_2, exp: nowSeconds() + 3600 });
    users.set(expired, Response.json({ code: 401, msg: 'token is expired' }, { status: 401 }));
    for (const token of [bad, expired]) {
      const response = await send('/v1/generate', { token });
      expect(response.status).toBe(401);
      expect((await errorOf(response)).code).toBe('unauthorized');
    }
    expect(geminiCalls()).toHaveLength(0);
  });

  it('checks a valid token with Supabase, with the publishable key', async () => {
    const response = await send('/v1/generate');
    expect(response.status).toBe(200);
    const [check] = authCalls();
    expect(check.url).toBe(`${SUPABASE_URL}/auth/v1/user`);
    expect(check.method).toBe('GET');
    expect(check.headers.get('apikey')).toBe(PUBLISHABLE);
    expect(check.headers.get('Authorization')).toBe(`Bearer ${TOKEN}`);
    expect([...check.headers.values()].join(' ')).not.toContain(KEY);
  });

  it('copes with a trailing slash in SUPABASE_URL', async () => {
    const response = await send('/v1/generate', {
      env: makeEnv({ SUPABASE_URL: `${SUPABASE_URL}/` }),
    });
    expect(response.status).toBe(200);
    expect(supabaseCalls()[0].url).toBe(`${SUPABASE_URL}/auth/v1/user`);
    expect(supabaseCalls()[1].url).toMatch(`${SUPABASE_URL}/rest/v1/company_members?`);
  });

  it('refuses anonymous Supabase users', async () => {
    users.set(TOKEN, { id: USER_1, is_anonymous: true });
    const response = await send('/v1/generate');
    expect(response.status).toBe(401);
    expect(geminiCalls()).toHaveLength(0);
  });

  it('refuses an answer without a user id', async () => {
    users.set(TOKEN, { aud: 'authenticated' });
    const response = await send('/v1/generate');
    expect(response.status).toBe(401);
  });

  it('reports Supabase being down as an upstream error, not a bad sign-in', async () => {
    users.set(TOKEN, new Response('oops', { status: 500 }));
    const down = await send('/v1/generate');
    expect(down.status).toBe(502);
    expect((await errorOf(down)).code).toBe('upstream_error');

    users.set(TOKEN, () => Promise.reject(new TypeError('fetch failed')));
    const unreachable = await send('/v1/generate');
    expect(unreachable.status).toBe(502);
    expect((await errorOf(unreachable)).code).toBe('upstream_error');
  });

  it('reports a wrong publishable key as the Worker not being set up', async () => {
    users.set(
      TOKEN,
      Response.json(
        { message: 'Invalid API key', hint: 'Double check your key.' },
        { status: 401 },
      ),
    );
    const response = await send('/v1/generate');
    expect(response.status).toBe(500);
    expect((await errorOf(response)).code).toBe('internal');
    expect(logLines().at(-1).problem).toMatch(/SUPABASE_PUBLISHABLE_KEY/);
  });

  it("never sends the person's token to Google", async () => {
    await send('/v1/generate');
    gemini = (call) => sseResponse(STREAM_EVENTS, call);
    await send('/v1/stream').then((r) => r.text());
    for (const call of geminiCalls()) {
      expect(call.headers.get('Authorization')).toBeNull();
      expect([...call.headers.values()].join(' ')).not.toContain(TOKEN);
      expect(call.url).not.toContain(TOKEN);
      expect(call.body).not.toContain(TOKEN);
    }
  });
});

describe('sign-in cache', () => {
  let now;
  beforeEach(() => {
    now = Date.now();
    vi.spyOn(Date, 'now').mockImplementation(() => now);
  });

  it('asks Supabase once for repeated requests within 60 seconds', async () => {
    expect((await send('/v1/generate')).status).toBe(200);
    now += 30_000;
    expect((await send('/v1/generate')).status).toBe(200);
    expect(authCalls()).toHaveLength(1);
    expect(memberCalls()).toHaveLength(1);
    expect(logLines().map((line) => line.auth)).toEqual(['checked', 'cache']);
  });

  it('asks again after 60 seconds', async () => {
    await send('/v1/generate');
    now += 60_001;
    await send('/v1/generate');
    expect(authCalls()).toHaveLength(2);
    expect(memberCalls()).toHaveLength(2);
  });

  it('never trusts a token past its expiry, even within 60 seconds', async () => {
    const shortLived = jwt({ sub: USER_2, exp: Math.floor(now / 1000) + 10 });
    users.set(shortLived, { id: USER_2 });
    await send('/v1/generate', { token: shortLived });
    const [entry] = testing.authCache.values();
    expect(entry.until).toBeLessThanOrEqual((Math.floor(now / 1000) + 10) * 1000);
    now += 11_000;
    await send('/v1/generate', { token: shortLived });
    expect(authCalls()).toHaveLength(2);
  });

  it('does not cache a token without an expiry', async () => {
    const noExp = jwt({ sub: USER_2 });
    users.set(noExp, { id: USER_2 });
    await send('/v1/generate', { token: noExp });
    await send('/v1/generate', { token: noExp });
    expect(authCalls()).toHaveLength(2);
    expect(testing.authCache.size).toBe(0);
  });

  it('does not cache a refusal', async () => {
    const bad = jwt({ sub: USER_2, exp: nowSeconds() + 3600 });
    await send('/v1/generate', { token: bad });
    users.set(bad, { id: USER_2 });
    expect((await send('/v1/generate', { token: bad })).status).toBe(200);
    expect(authCalls()).toHaveLength(2);
  });

  it('keys the cache by a SHA-256 hash of the token, never the token', async () => {
    await send('/v1/generate');
    const keys = [...testing.authCache.keys()];
    expect(keys).toEqual([await sha256Hex(TOKEN)]);
    expect(keys[0]).toMatch(/^[0-9a-f]{64}$/);
    expect(JSON.stringify([...testing.authCache.entries()])).not.toContain(TOKEN);
  });
});

describe('company membership (COMPANY_ID)', () => {
  it("asks Supabase, with the person's own token, whether they are a member", async () => {
    expect((await send('/v1/generate')).status).toBe(200);
    const [check] = memberCalls();
    const url = new URL(check.url);
    expect(url.pathname).toBe('/rest/v1/company_members');
    expect(Object.fromEntries(url.searchParams)).toEqual({
      select: 'role',
      company_id: `eq.${COMPANY}`,
      user_id: `eq.${USER_1}`,
      limit: '1',
    });
    expect(check.method).toBe('GET');
    expect(check.headers.get('apikey')).toBe(PUBLISHABLE);
    expect(check.headers.get('Authorization')).toBe(`Bearer ${TOKEN}`);
    expect([...check.headers.values()].join(' ')).not.toContain(KEY);
    // The sign-in check comes first: its user id is the one asked about.
    expect(supabaseCalls().map((call) => new URL(call.url).pathname)).toEqual([
      '/auth/v1/user',
      '/rest/v1/company_members',
    ]);
  });

  it('refuses a signed-in account that is not a member, with 403 forbidden', async () => {
    // Anyone can create an account in the app; that alone must not be enough.
    const stranger = jwt({ sub: 'a5c8f4e2-0b7d-4e1a-9c3f-2d6b8e0f1a4c', exp: nowSeconds() + 3600 });
    users.set(stranger, { id: 'a5c8f4e2-0b7d-4e1a-9c3f-2d6b8e0f1a4c', is_anonymous: false });
    for (const path of ['/v1/generate', '/v1/stream']) {
      const response = await send(path, { token: stranger });
      expect(response.status).toBe(403);
      expect(response.headers.get('Access-Control-Allow-Origin')).toBe(APP);
      expect(await errorOf(response)).toEqual({
        code: 'forbidden',
        message: 'This account is not a member of the company that uses this AI service.',
        status: 403,
      });
    }
    expect(geminiCalls()).toHaveLength(0);
    expect(logLines().map((line) => line.code)).toEqual(['forbidden', 'forbidden']);
  });

  it('refuses a member of another company', async () => {
    members = new Set([`other-company-0001 ${USER_1}`]);
    const response = await send('/v1/generate');
    expect(response.status).toBe(403);
    expect(geminiCalls()).toHaveLength(0);
  });

  // An empty COMPANY_ID is no longer refused: see "open to everyone signed in" below.
  it.each(['short', 'has spaces in it', 'x'.repeat(65), 'a/../../b-c'])(
    'refuses everyone when COMPANY_ID is %j, without asking anyone',
    async (companyId) => {
      const response = await send('/v1/generate', { env: makeEnv({ COMPANY_ID: companyId }) });
      expect(response.status).toBe(500);
      expect(await errorOf(response)).toEqual({
        code: 'internal',
        message: 'The AI service is not set up yet.',
        status: 500,
      });
      expect(calls).toHaveLength(0);
      expect(logLines()[0].problem).toMatch(/COMPANY_ID/);
    },
  );

  it('treats a 401 from the membership check as an expired sign-in', async () => {
    membership = () => Response.json({ code: 'PGRST303', message: 'JWT expired' }, { status: 401 });
    const response = await send('/v1/generate');
    expect(response.status).toBe(401);
    expect((await errorOf(response)).code).toBe('unauthorized');
    expect(logLines()[0]).toMatchObject({ memberStatus: 401 });
    expect(geminiCalls()).toHaveLength(0);
  });

  it.each([
    ['a 500', () => new Response('oops', { status: 500 }), 502, 'upstream_error'],
    ['a 403', () => Response.json({ code: '42501' }, { status: 403 }), 502, 'upstream_error'],
    ['an answer that is not a list', () => Response.json({ role: 'owner' }), 502, 'upstream_error'],
    ['an answer that is not JSON', () => new Response('<html>'), 502, 'upstream_error'],
    [
      'a network failure',
      () => Promise.reject(new TypeError('fetch failed')),
      502,
      'upstream_error',
    ],
    [
      'a timeout',
      () => Promise.reject(new DOMException('timed out', 'TimeoutError')),
      504,
      'upstream_timeout',
    ],
  ])('fails closed on %s from the membership check', async (_, answer, status, code) => {
    membership = answer;
    const response = await send('/v1/generate');
    expect(response.status).toBe(status);
    expect((await errorOf(response)).code).toBe(code);
    expect(geminiCalls()).toHaveLength(0);
    expect(testing.authCache.size).toBe(0);
  });

  it('remembers a member with the sign-in, and does not remember a refusal', async () => {
    members = new Set();
    expect((await send('/v1/generate')).status).toBe(403);
    expect(testing.authCache.size).toBe(0);
    members = new Set([`${COMPANY} ${USER_1}`]);
    expect((await send('/v1/generate')).status).toBe(200);
    expect((await send('/v1/generate')).status).toBe(200);
    expect(authCalls()).toHaveLength(2);
    expect(memberCalls()).toHaveLength(2);
    expect(logLines().map((line) => line.auth)).toEqual(['checked', 'checked', 'cache']);
  });

  it('asks again when COMPANY_ID changes', async () => {
    members.add(`other-company-0001 ${USER_1}`);
    await send('/v1/generate');
    await send('/v1/generate', { env: makeEnv({ COMPANY_ID: 'other-company-0001' }) });
    expect(memberCalls()).toHaveLength(2);
    members = new Set();
    // A token remembered for one company is not trusted for another.
    const response = await send('/v1/generate', {
      env: makeEnv({ COMPANY_ID: 'third-company-01' }),
    });
    expect(response.status).toBe(403);
  });

  it('counts a non-member in the rate limit before asking about membership', async () => {
    members = new Set();
    const limit = vi.fn(async () => ({ success: false }));
    const response = await send('/v1/generate', { env: makeEnv({ AI_RATE_LIMITER: { limit } }) });
    expect(response.status).toBe(429);
    expect(limit).toHaveBeenCalledWith({ key: USER_1 });
    expect(memberCalls()).toHaveLength(0);
  });

  it('refuses a user id from Supabase that is not a UUID, before it goes in a URL', async () => {
    users.set(TOKEN, { id: `${USER_1}&company_id=eq.anything`, is_anonymous: false });
    const response = await send('/v1/generate');
    expect(response.status).toBe(401);
    expect(memberCalls()).toHaveLength(0);
  });
});

describe('several companies (COMPANY_ID a list)', () => {
  const OTHER = 'other-company-0001';
  const THIRD = 'third-company-01';

  it('serves a member of the second company, with one in.(...) request', async () => {
    members = new Set([`${COMPANY} ${USER_1}`]);
    const response = await send('/v1/generate', {
      env: makeEnv({ COMPANY_ID: `${OTHER},${COMPANY}` }),
    });
    expect(response.status).toBe(200);
    expect(geminiCalls()).toHaveLength(1);
    const [check] = memberCalls();
    expect(memberCalls()).toHaveLength(1);
    const url = new URL(check.url);
    expect(url.pathname).toBe('/rest/v1/company_members');
    expect(Object.fromEntries(url.searchParams)).toEqual({
      select: 'role',
      company_id: `in.(${OTHER},${COMPANY})`,
      user_id: `eq.${USER_1}`,
      limit: '1',
    });
    expect(check.headers.get('Authorization')).toBe(`Bearer ${TOKEN}`);
  });

  it('refuses an account that is a member of none of them, with 403 forbidden', async () => {
    members = new Set([`${THIRD} ${USER_1}`]);
    for (const path of ['/v1/generate', '/v1/stream']) {
      const response = await send(path, { env: makeEnv({ COMPANY_ID: `${COMPANY}, ${OTHER}` }) });
      expect(response.status).toBe(403);
      expect(await errorOf(response)).toEqual({
        code: 'forbidden',
        message: 'This account is not a member of the company that uses this AI service.',
        status: 403,
      });
    }
    expect(geminiCalls()).toHaveLength(0);
    expect(testing.authCache.size).toBe(0);
  });

  it('ignores spaces around each id, empty items and repeats', async () => {
    members = new Set([`${OTHER} ${USER_1}`]);
    const env = makeEnv({ COMPANY_ID: ` ${COMPANY} ,, ${OTHER} , ${COMPANY} ,` });
    expect((await send('/v1/generate', { env })).status).toBe(200);
    const query = new URL(memberCalls()[0].url).searchParams;
    expect(query.get('company_id')).toBe(`in.(${COMPANY},${OTHER})`);
  });

  it('asks with eq. when the list holds one id, with spaces or repeated', async () => {
    for (const companyId of [` ${COMPANY} `, `${COMPANY},${COMPANY}`, `,${COMPANY},`]) {
      testing.authCache.clear();
      calls = [];
      expect((await send('/v1/generate', { env: makeEnv({ COMPANY_ID: companyId }) })).status).toBe(
        200,
      );
      const query = new URL(memberCalls()[0].url).searchParams;
      expect(query.get('company_id')).toBe(`eq.${COMPANY}`);
    }
  });

  it.each([
    `${COMPANY},short`,
    `${COMPANY}, has spaces`,
    `${COMPANY};${OTHER}`,
    `${OTHER},a/../../b-c`,
    `${COMPANY},${'x'.repeat(65)}`,
    `${COMPANY},${OTHER})`,
  ])('refuses everyone when an item of COMPANY_ID %j is not a company id', async (companyId) => {
    const response = await send('/v1/generate', { env: makeEnv({ COMPANY_ID: companyId }) });
    expect(response.status).toBe(500);
    expect(await errorOf(response)).toEqual({
      code: 'internal',
      message: 'The AI service is not set up yet.',
      status: 500,
    });
    expect(calls).toHaveLength(0);
    expect(logLines()[0].problem).toBe('COMPANY_ID is not a company id or a list of them');
  });

  it('logs no company id', async () => {
    members = new Set([`${OTHER} ${USER_1}`]);
    await send('/v1/generate', { env: makeEnv({ COMPANY_ID: `${COMPANY},${OTHER}` }) });
    await send('/v1/generate', { env: makeEnv({ COMPANY_ID: `${THIRD},${COMPANY}` }) });
    const all = logs.join('\n');
    for (const id of [COMPANY, OTHER, THIRD]) expect(all).not.toContain(id);
  });
});

describe('open to everyone signed in (COMPANY_ID empty)', () => {
  const STRANGER = 'a5c8f4e2-0b7d-4e1a-9c3f-2d6b8e0f1a4c';
  const open = (overrides = {}) => makeEnv({ COMPANY_ID: '', ...overrides });
  let stranger;
  beforeEach(() => {
    // An account that belongs to no company at all.
    stranger = jwt({ sub: STRANGER, exp: nowSeconds() + 3600 });
    users.set(stranger, { id: STRANGER, aud: 'authenticated', is_anonymous: false });
    members = new Set();
  });

  it.each([
    ['empty', ''],
    ['left out', undefined],
    ['only spaces', '   '],
  ])(
    'serves any signed-in account when COMPANY_ID is %s, without a membership check',
    async (_, companyId) => {
      const env = makeEnv({ COMPANY_ID: companyId });
      const response = await send('/v1/generate', { token: stranger, env });
      expect(response.status).toBe(200);
      expect(await response.json()).toEqual(geminiAnswer());
      gemini = (call) => sseResponse(STREAM_EVENTS, call);
      const stream = await send('/v1/stream', { token: stranger, env });
      expect(stream.status).toBe(200);
      expect((await chunksOf(stream)).join('')).toContain('three');
      expect(memberCalls()).toHaveLength(0);
      expect(authCalls()).toHaveLength(1);
      expect(geminiCalls()).toHaveLength(2);
      expect(logLines().map((line) => line.status)).toEqual([200, 200]);
      expect(logLines().every((line) => line.problem === undefined)).toBe(true);
      expect(logs.join('\n')).not.toContain(STRANGER);
    },
  );

  it('serves a member of a company too, without asking about it', async () => {
    members = new Set([`${COMPANY} ${USER_1}`]);
    expect((await send('/v1/generate', { env: open() })).status).toBe(200);
    expect(supabaseCalls().map((call) => new URL(call.url).pathname)).toEqual(['/auth/v1/user']);
  });

  it('still refuses a request without a token, without asking Supabase', async () => {
    const response = await send('/v1/generate', { token: null, env: open() });
    expect(response.status).toBe(401);
    expect((await errorOf(response)).code).toBe('unauthorized');
    expect(calls).toHaveLength(0);
  });

  it('still refuses a token Supabase rejects, and anonymous users', async () => {
    const bad = jwt({ sub: USER_2, exp: nowSeconds() + 3600 });
    const anonymous = jwt({ sub: USER_2, exp: nowSeconds() + 3600 });
    users.set(anonymous, { id: USER_2, is_anonymous: true });
    for (const token of [bad, anonymous]) {
      const response = await send('/v1/generate', { token, env: open() });
      expect(response.status).toBe(401);
      expect((await errorOf(response)).code).toBe('unauthorized');
    }
    expect(memberCalls()).toHaveLength(0);
    expect(geminiCalls()).toHaveLength(0);
    expect(testing.authCache.size).toBe(0);
  });

  it('keeps CORS as it is', async () => {
    const evil = await send('/v1/generate', {
      token: stranger,
      origin: 'https://evil.example',
      env: open(),
    });
    expect(evil.status).toBe(403);
    expect(evil.headers.get('Access-Control-Allow-Origin')).toBeNull();
    expect((await errorOf(evil)).code).toBe('forbidden_origin');
    expect(calls).toHaveLength(0);
    const app = await send('/v1/generate', { token: stranger, env: open() });
    expect(app.headers.get('Access-Control-Allow-Origin')).toBe(APP);
  });

  it('keeps the allowlists, the caps and the body limit as they are', async () => {
    const env = open();
    const model = await send('/v1/generate', {
      token: stranger,
      env,
      body: { ...question, model: 'gemini-1.5-pro' },
    });
    expect((await errorOf(model)).code).toBe('model_not_allowed');
    const file = await send('/v1/generate', {
      token: stranger,
      env,
      body: {
        contents: [{ role: 'user', parts: [{ fileData: { fileUri: 'https://x.example/a' } }] }],
      },
    });
    expect((await errorOf(file)).code).toBe('bad_request');
    const snake = await send('/v1/generate', {
      token: stranger,
      env,
      body: { ...question, generationConfig: { max_output_tokens: 99_999 } },
    });
    expect((await errorOf(snake)).code).toBe('bad_request');
    const large = await send('/v1/generate', {
      token: stranger,
      env: open({ MAX_BODY_BYTES: '1000' }),
      headers: { 'Content-Length': '5000' },
    });
    expect((await errorOf(large)).code).toBe('payload_too_large');
    expect(geminiCalls()).toHaveLength(0);

    await send('/v1/generate', {
      token: stranger,
      env,
      body: {
        ...question,
        generationConfig: {
          maxOutputTokens: 99_999,
          candidateCount: 4,
          thinkingConfig: { thinkingLevel: 'high' },
        },
      },
    });
    expect(geminiBody().generationConfig).toEqual({
      maxOutputTokens: 1024,
      candidateCount: 1,
      thinkingConfig: { thinkingLevel: 'low' },
    });
  });

  it('keeps the per-user rate limit when the binding is there', async () => {
    const limit = vi.fn(async () => ({ success: false }));
    const response = await send('/v1/generate', {
      token: stranger,
      env: open({ AI_RATE_LIMITER: { limit } }),
    });
    expect(response.status).toBe(429);
    expect(limit).toHaveBeenCalledWith({ key: STRANGER });
    expect(geminiCalls()).toHaveLength(0);
  });

  it('remembers a sign-in for repeated requests, as with a company', async () => {
    expect((await send('/v1/generate', { token: stranger, env: open() })).status).toBe(200);
    expect((await send('/v1/generate', { token: stranger, env: open() })).status).toBe(200);
    expect(authCalls()).toHaveLength(1);
    expect(memberCalls()).toHaveLength(0);
    expect(logLines().map((line) => line.auth)).toEqual(['checked', 'cache']);
  });
});

describe('the sign-in cache when COMPANY_ID changes', () => {
  const OTHER = 'other-company-0001';
  const THIRD = 'third-company-01';

  it('does not carry a pass from open to one company', async () => {
    members = new Set();
    expect((await send('/v1/generate', { env: makeEnv({ COMPANY_ID: '' }) })).status).toBe(200);
    expect(testing.authCache.size).toBe(1);
    const response = await send('/v1/generate', { env: makeEnv({ COMPANY_ID: COMPANY }) });
    expect(response.status).toBe(403);
    expect(authCalls()).toHaveLength(2);
    expect(memberCalls()).toHaveLength(1);
  });

  it('does not carry a pass from open to a list', async () => {
    members = new Set();
    await send('/v1/generate', { env: makeEnv({ COMPANY_ID: undefined }) });
    const response = await send('/v1/generate', {
      env: makeEnv({ COMPANY_ID: `${COMPANY},${OTHER}` }),
    });
    expect(response.status).toBe(403);
    expect(memberCalls()).toHaveLength(1);
  });

  it('does not carry a pass from one list to another', async () => {
    members = new Set([`${OTHER} ${USER_1}`]);
    expect(
      (await send('/v1/generate', { env: makeEnv({ COMPANY_ID: `${COMPANY},${OTHER}` }) })).status,
    ).toBe(200);
    const response = await send('/v1/generate', {
      env: makeEnv({ COMPANY_ID: `${COMPANY},${THIRD}` }),
    });
    expect(response.status).toBe(403);
    expect(memberCalls()).toHaveLength(2);
  });

  it('checks the sign-in again from a company to open', async () => {
    expect((await send('/v1/generate')).status).toBe(200);
    expect((await send('/v1/generate', { env: makeEnv({ COMPANY_ID: '' }) })).status).toBe(200);
    expect(authCalls()).toHaveLength(2);
    expect(memberCalls()).toHaveLength(1);
    expect(logLines().map((line) => line.auth)).toEqual(['checked', 'checked']);
  });

  it('keeps using a pass while COMPANY_ID stays the same', async () => {
    const env = makeEnv({ COMPANY_ID: `${OTHER}, ${COMPANY}` });
    await send('/v1/generate', { env });
    await send('/v1/generate', { env: makeEnv({ COMPANY_ID: `${OTHER},${COMPANY}` }) });
    expect(authCalls()).toHaveLength(1);
    expect(memberCalls()).toHaveLength(1);
  });
});

describe('models', () => {
  it('uses GEMINI_MODEL when the request names none', async () => {
    await send('/v1/generate');
    expect(geminiCalls()[0].url).toBe(`${GEMINI}gemini-3.6-flash:generateContent`);
  });

  it('allows a model from ALLOWED_MODELS', async () => {
    await send('/v1/generate', { body: { ...question, model: 'gemini-3.6-flash-lite' } });
    expect(geminiCalls()[0].url).toBe(`${GEMINI}gemini-3.6-flash-lite:generateContent`);
    expect(geminiBody()).not.toHaveProperty('model');
  });

  it.each([
    'gemini-1.5-pro',
    'gemini-3.6-flash:streamGenerateContent?key=',
    'gemini-3.6-flash:generateContent?key=AIza',
    '../',
    '../../files',
    'gemini-3.6-flash/../../files',
    '..%2F..%2Ffiles',
    'gemini-3.6-flash#',
    'GEMINI-3.6-FLASH',
    ' gemini-3.6-flash',
    'models/gemini-3.6-flash',
    '',
    42,
    null,
    ['gemini-3.6-flash'],
    { name: 'gemini-3.6-flash' },
  ])('refuses %j without calling Google', async (model) => {
    const response = await send('/v1/generate', { body: { ...question, model } });
    expect(response.status).toBe(400);
    const error = await errorOf(response);
    expect(error.code).toBe('model_not_allowed');
    expect(geminiCalls()).toHaveLength(0);
  });

  it('ignores an allowlist entry that is not a plain model name', async () => {
    const env = makeEnv({ ALLOWED_MODELS: 'gemini-3.6-flash,../evil,x:generateContent?' });
    for (const model of ['../evil', 'x:generateContent?']) {
      const response = await send('/v1/generate', { env, body: { ...question, model } });
      expect((await errorOf(response)).code).toBe('model_not_allowed');
    }
    expect(geminiCalls()).toHaveLength(0);
  });

  it('refuses to run when GEMINI_MODEL itself is not a model name', async () => {
    const response = await send('/v1/generate', {
      env: makeEnv({ GEMINI_MODEL: 'gemini-3.6-flash:generateContent?key=' }),
    });
    expect(response.status).toBe(500);
    expect(geminiCalls()).toHaveLength(0);
  });
});

describe('request limits and fields', () => {
  it('refuses a declared Content-Length over the limit before checking the sign-in', async () => {
    const response = await send('/v1/generate', {
      env: makeEnv({ MAX_BODY_BYTES: '1000' }),
      headers: { 'Content-Length': '5000' },
    });
    expect(response.status).toBe(413);
    expect((await errorOf(response)).code).toBe('payload_too_large');
    expect(calls).toHaveLength(0);
  });

  it('stops reading a body without a length once it passes the limit', async () => {
    let pulled = 0;
    const body = new ReadableStream({
      pull(controller) {
        pulled++;
        if (pulled > 50) controller.close();
        else controller.enqueue(new Uint8Array(100).fill(32));
      },
    });
    const response = await send('/v1/generate', { env: makeEnv({ MAX_BODY_BYTES: '1000' }), body });
    expect(response.status).toBe(413);
    expect(pulled).toBeLessThan(20);
    expect(geminiCalls()).toHaveLength(0);
  });

  it('applies the 256 KB default', async () => {
    const big = { contents: [{ role: 'user', parts: [{ text: 'a'.repeat(300 * 1024) }] }] };
    const response = await send('/v1/generate', { body: big });
    expect(response.status).toBe(413);
    const fits = { contents: [{ role: 'user', parts: [{ text: 'a'.repeat(200 * 1024) }] }] };
    expect((await send('/v1/generate', { body: fits })).status).toBe(200);
  });

  it.each([
    ['not JSON', '{"contents": ['],
    ['a list', '[]'],
    ['a string', '"hello"'],
    ['empty', ''],
    ['no contents', '{}'],
    ['empty contents', '{"contents": []}'],
    ['contents not a list', '{"contents": {"parts": []}}'],
    ['an item without parts', '{"contents": [{"role": "user"}]}'],
    ['a part that is not an object', '{"contents": [{"parts": ["hi"]}]}'],
    [
      'a bad systemInstruction',
      '{"contents": [{"parts": [{"text": "x"}]}], "systemInstruction": "be nice"}',
    ],
    [
      'a bad generationConfig',
      '{"contents": [{"parts": [{"text": "x"}]}], "generationConfig": []}',
    ],
    ['bad safetySettings', '{"contents": [{"parts": [{"text": "x"}]}], "safetySettings": {}}'],
    ['a bad toolConfig', '{"contents": [{"parts": [{"text": "x"}]}], "toolConfig": "auto"}'],
  ])('refuses a body that is %s', async (_, body) => {
    const response = await send('/v1/generate', { body });
    expect(response.status).toBe(400);
    const error = await errorOf(response);
    expect(error.code).toBe('bad_request');
    expect(error.message).not.toContain('Unexpected');
    expect(geminiCalls()).toHaveLength(0);
  });

  it('refuses text that is not UTF-8', async () => {
    const response = await send('/v1/generate', { body: new Uint8Array([0x7b, 0xff, 0xfe, 0x7d]) });
    expect(response.status).toBe(400);
  });

  it('passes only the fields the app needs, and drops the rest', async () => {
    const body = {
      model: 'gemini-3.6-flash',
      contents: question.contents,
      systemInstruction: { parts: [{ text: 'You help with Maham One.' }] },
      generationConfig: { temperature: 0.2, responseMimeType: 'application/json' },
      safetySettings: [{ category: 'HARM_CATEGORY_HARASSMENT', threshold: 'BLOCK_ONLY_HIGH' }],
      tools: [{ functionDeclarations: [{ name: 'find_invoice', description: 'Finds one.' }] }],
      toolConfig: { functionCallingConfig: { mode: 'AUTO' } },
      cachedContent: 'cachedContents/someone-elses',
      labels: { team: 'x' },
      key: 'AIzaInjected',
      extra: true,
    };
    expect((await send('/v1/generate', { body })).status).toBe(200);
    const sent = geminiBody();
    expect(Object.keys(sent).sort()).toEqual([
      'contents',
      'generationConfig',
      'safetySettings',
      'systemInstruction',
      'toolConfig',
      'tools',
    ]);
    expect(sent.contents).toEqual(body.contents);
    expect(sent.systemInstruction).toEqual(body.systemInstruction);
    expect(sent.generationConfig).toEqual({
      temperature: 0.2,
      responseMimeType: 'application/json',
      maxOutputTokens: 1024,
      candidateCount: 1,
      thinkingConfig: { thinkingLevel: 'low' },
    });
    expect(sent.tools).toEqual(body.tools);
    expect(sent.toolConfig).toEqual(body.toolConfig);
    expect(geminiCalls()[0].url).not.toContain('AIzaInjected');
  });

  it('caps maxOutputTokens at MAX_OUTPUT_TOKENS and keeps smaller values', async () => {
    const ask = (generationConfig) =>
      send('/v1/generate', { body: { ...question, generationConfig } });
    await ask({ maxOutputTokens: 99_999 });
    await ask({ maxOutputTokens: 100 });
    await ask(undefined);
    expect(geminiCalls().map((_, i) => geminiBody(i).generationConfig.maxOutputTokens)).toEqual([
      1024, 100, 1024,
    ]);
  });

  it('gives a request that names no length DEFAULT_ANSWER_TOKENS, 2048 unless set, still capped', async () => {
    const lengthWith = async (overrides, generationConfig) => {
      calls.length = 0;
      await send('/v1/generate', {
        env: makeEnv(overrides),
        body: generationConfig ? { ...question, generationConfig } : question,
      });
      return geminiBody().generationConfig.maxOutputTokens;
    };
    // The default, with the production cap.
    expect(await lengthWith({ MAX_OUTPUT_TOKENS: '8192' })).toBe(2048);
    expect(await lengthWith({ MAX_OUTPUT_TOKENS: undefined }, {})).toBe(2048);
    expect(await lengthWith({ MAX_OUTPUT_TOKENS: '8192', DEFAULT_ANSWER_TOKENS: '' })).toBe(2048);
    // Set, and never above the cap.
    expect(await lengthWith({ MAX_OUTPUT_TOKENS: '8192', DEFAULT_ANSWER_TOKENS: '3000' })).toBe(
      3000,
    );
    expect(await lengthWith({ MAX_OUTPUT_TOKENS: '1024', DEFAULT_ANSWER_TOKENS: '3000' })).toBe(
      1024,
    );
    // Not a whole number above 0: the 2048 default.
    for (const value of ['lots', '0', '-5', '1.5']) {
      expect(await lengthWith({ MAX_OUTPUT_TOKENS: '8192', DEFAULT_ANSWER_TOKENS: value })).toBe(
        2048,
      );
    }
    // A length the request names is kept, up to the cap, whatever the default.
    expect(
      await lengthWith(
        { MAX_OUTPUT_TOKENS: '8192', DEFAULT_ANSWER_TOKENS: '3000' },
        { maxOutputTokens: 6000 },
      ),
    ).toBe(6000);
  });

  it('uses the 8192 default cap when MAX_OUTPUT_TOKENS is not set', async () => {
    await send('/v1/generate', {
      env: makeEnv({ MAX_OUTPUT_TOKENS: undefined }),
      body: { ...question, generationConfig: { maxOutputTokens: 50_000 } },
    });
    expect(geminiBody().generationConfig.maxOutputTokens).toBe(8192);
  });

  it.each(['lots', 0, -5, 1.5, null, '100'])('refuses maxOutputTokens %j', async (value) => {
    const response = await send('/v1/generate', {
      body: { ...question, generationConfig: { maxOutputTokens: value } },
    });
    expect(response.status).toBe(400);
    expect(geminiCalls()).toHaveLength(0);
  });

  it('asks for one candidate only', async () => {
    await send('/v1/generate', { body: { ...question, generationConfig: { candidateCount: 8 } } });
    expect(geminiBody().generationConfig.candidateCount).toBe(1);
  });

  it.each([
    [[{ googleSearch: {} }]],
    [[{ urlContext: {} }]],
    [[{ codeExecution: {} }]],
    [[{ functionDeclarations: [], googleSearch: {} }]],
    [[{ functionDeclarations: {} }]],
    [{ functionDeclarations: [] }],
    [['find_invoice']],
  ])('refuses tools %j other than function declarations', async (tools) => {
    const response = await send('/v1/generate', { body: { ...question, tools } });
    expect(response.status).toBe(400);
    expect(geminiCalls()).toHaveLength(0);
  });

  it('refuses file links, in contents and in systemInstruction', async () => {
    const link = {
      fileData: { mimeType: 'application/pdf', fileUri: 'https://example.com/big.pdf' },
    };
    const inContents = await send('/v1/generate', {
      body: { contents: [{ role: 'user', parts: [{ text: 'Read this' }, link] }] },
    });
    expect(inContents.status).toBe(400);
    const inSystem = await send('/v1/generate', {
      body: { ...question, systemInstruction: { parts: [link] } },
    });
    expect(inSystem.status).toBe(400);
    expect(geminiCalls()).toHaveLength(0);
  });

  it('accepts inline data', async () => {
    const body = {
      contents: [
        {
          role: 'user',
          parts: [
            { text: 'What is this?' },
            { inlineData: { mimeType: 'image/png', data: 'iVBORw0KGgo=' } },
          ],
        },
      ],
    };
    expect((await send('/v1/generate', { body })).status).toBe(200);
  });
});

describe('what is sent to Google is rebuilt from allowlists', () => {
  const ask = (body) => send('/v1/generate', { body });
  const withConfig = (generationConfig) => ({ ...question, generationConfig });

  async function refused(body, message) {
    const response = await ask(body);
    expect(response.status).toBe(400);
    const error = await errorOf(response);
    expect(error.code).toBe('bad_request');
    if (message) expect(error.message).toMatch(message);
    return error;
  }

  afterEach(() => {
    // Nothing refused may have reached Google.
    for (const call of geminiCalls()) {
      expect(call.body).not.toMatch(
        /file_?[dD]ata|_count|max_output|media_resolution|MEDIA_RESOLUTION_HIGH/,
      );
    }
  });

  it.each([
    ['file_data', { file_data: { file_uri: 'https://www.youtube.com/watch?v=x' } }],
    ['fileData', { fileData: { fileUri: 'https://www.youtube.com/watch?v=x' } }],
    ['inline_data', { inline_data: { mime_type: 'image/png', data: 'iVBORw0KGgo=' } }],
    ['videoMetadata', { text: 'x', videoMetadata: { startOffset: '0s' } }],
    ['executableCode', { executableCode: { language: 'PYTHON', code: 'print(1)' } }],
    ['codeExecutionResult', { codeExecutionResult: { outcome: 'OUTCOME_OK' } }],
    [
      'per-part mediaResolution',
      { text: 'x', mediaResolution: { level: 'MEDIA_RESOLUTION_HIGH' } },
    ],
    ['per-part media_resolution', { text: 'x', media_resolution: 'MEDIA_RESOLUTION_HIGH' }],
    ['thought_signature', { text: 'x', thought_signature: 'abc' }],
    ['function_call', { function_call: { name: 'find_invoice' } }],
  ])('refuses a part with %s, in contents', async (_, part) => {
    await refused({ contents: [{ role: 'user', parts: [{ text: 'summarise' }, part] }] });
    expect(geminiCalls()).toHaveLength(0);
  });

  it.each([
    ['file_data', { file_data: { file_uri: 'https://www.youtube.com/watch?v=x' } }],
    ['fileData', { fileData: { fileUri: 'https://example.com/a.pdf' } }],
    ['inlineData', { inlineData: { mimeType: 'image/png', data: 'iVBORw0KGgo=' } }],
    ['a snake_case text key', { text: 'x', text_: 'y' }],
  ])('refuses a systemInstruction part with %s (text only)', async (_, part) => {
    await refused({ ...question, systemInstruction: { parts: [part] } });
    expect(geminiCalls()).toHaveLength(0);
  });

  it('refuses file links inside a function response', async () => {
    await refused({
      contents: [
        {
          role: 'user',
          parts: [
            {
              functionResponse: {
                name: 'find_invoice',
                response: { ok: true },
                parts: [{ fileData: { fileUri: 'https://www.youtube.com/watch?v=x' } }],
              },
            },
          ],
        },
      ],
    });
    expect(geminiCalls()).toHaveLength(0);
  });

  it('refuses unknown fields on a content item, and roles other than user and model', async () => {
    await refused({ contents: [{ role: 'user', parts: [{ text: 'x' }], extra_parts: [] }] });
    await refused({ contents: [{ role: 'system', parts: [{ text: 'x' }] }] }, /role/);
    expect(geminiCalls()).toHaveLength(0);
  });

  it('refuses a __proto__ key instead of passing it on', async () => {
    const response = await send('/v1/generate', {
      body: '{"contents":[{"parts":[{"text":"x","__proto__":{"fileData":{"fileUri":"u"}}}]}]}',
    });
    expect(response.status).toBe(400);
    expect(geminiCalls()).toHaveLength(0);
  });

  it('refuses candidate_count, and always asks for exactly one candidate', async () => {
    await refused(withConfig({ candidate_count: 8 }), /candidate_count/);
    expect(geminiCalls()).toHaveLength(0);
    await ask(withConfig({ candidateCount: 8 }));
    await ask(withConfig({ temperature: 1 }));
    await ask(question);
    expect(geminiCalls().map((_, i) => geminiBody(i).generationConfig.candidateCount)).toEqual([
      1, 1, 1,
    ]);
  });

  it('refuses max_output_tokens next to maxOutputTokens, in either order', async () => {
    for (const json of [
      '{"contents":[{"parts":[{"text":"x"}]}],"generationConfig":{"maxOutputTokens":8192,"max_output_tokens":65536}}',
      '{"contents":[{"parts":[{"text":"x"}]}],"generationConfig":{"max_output_tokens":65536,"maxOutputTokens":8192}}',
      '{"contents":[{"parts":[{"text":"x"}]}],"generationConfig":{"max_output_tokens":65536}}',
    ]) {
      const response = await send('/v1/generate', { body: json });
      expect(response.status).toBe(400);
      expect((await errorOf(response)).message).toMatch(/max_output_tokens/);
    }
    expect(geminiCalls()).toHaveLength(0);
  });

  it('sends maxOutputTokens once, capped, even when the request repeats it', async () => {
    const json =
      '{"contents":[{"parts":[{"text":"x"}]}],"generationConfig":{"maxOutputTokens":1,"maxOutputTokens":99999}}';
    expect((await send('/v1/generate', { body: json })).status).toBe(200);
    const sent = geminiCalls()[0].body;
    expect(sent.match(/maxOutputTokens/g)).toHaveLength(1);
    expect(JSON.parse(sent).generationConfig.maxOutputTokens).toBe(1024);
  });

  it.each([
    'responseModalities',
    'speechConfig',
    'responseLogprobs',
    'enableEnhancedCivicAnswers',
    'top_p',
    'response_mime_type',
    'thinking_config',
  ])('refuses generationConfig.%s', async (key) => {
    await refused(withConfig({ [key]: ['AUDIO'] }), new RegExp(key));
    expect(geminiCalls()).toHaveLength(0);
  });

  it('keeps the generationConfig fields the app may use', async () => {
    const generationConfig = {
      temperature: 0.4,
      topP: 0.9,
      topK: 20,
      maxOutputTokens: 500,
      stopSequences: ['END'],
      responseMimeType: 'application/json',
      responseSchema: { type: 'OBJECT', properties: { total_amount: { type: 'NUMBER' } } },
      responseJsonSchema: { type: 'object' },
      thinkingConfig: { thinkingLevel: 'low', includeThoughts: false },
      seed: 7,
      presencePenalty: 0.1,
      frequencyPenalty: 0.2,
      mediaResolution: 'MEDIA_RESOLUTION_LOW',
    };
    expect((await ask(withConfig(generationConfig))).status).toBe(200);
    expect(geminiBody().generationConfig).toEqual({ ...generationConfig, candidateCount: 1 });
  });

  it('asks for low thinking when the request sets none, and never more than low', async () => {
    await ask(question);
    await ask(withConfig({ temperature: 0.3 }));
    await ask(withConfig({ thinkingConfig: { thinkingBudget: 512 } }));
    await ask(withConfig({ thinkingConfig: { thinkingLevel: 'high' } }));
    await ask(withConfig({ thinkingConfig: { thinkingLevel: 'MEDIUM', includeThoughts: false } }));
    await ask(withConfig({ thinkingConfig: { thinkingLevel: 'minimal' } }));
    await ask(withConfig({ thinkingConfig: { includeThoughts: false } }));
    expect(geminiCalls().map((_, i) => geminiBody(i).generationConfig.thinkingConfig)).toEqual([
      { thinkingLevel: 'low' },
      { thinkingLevel: 'low' },
      // Never a level next to a budget: Google refuses the two together.
      { thinkingBudget: 512 },
      { thinkingLevel: 'low' },
      { thinkingLevel: 'low', includeThoughts: false },
      // Less than low stays as asked.
      { thinkingLevel: 'minimal' },
      { includeThoughts: false },
    ]);
  });

  it('caps thinkingBudget at 1024 (and MAX_OUTPUT_TOKENS), even "let the model decide"', async () => {
    await ask(withConfig({ thinkingConfig: { thinkingBudget: 50_000 } }));
    await ask(withConfig({ thinkingConfig: { thinkingBudget: -1 } }));
    await ask(withConfig({ thinkingConfig: { thinkingBudget: 0 } }));
    await ask(withConfig({ thinkingConfig: { thinkingBudget: 700 } }));
    expect(
      geminiCalls().map((_, i) => geminiBody(i).generationConfig.thinkingConfig.thinkingBudget),
    ).toEqual([1024, 1024, 0, 700]);
    await send('/v1/generate', {
      env: makeEnv({ MAX_OUTPUT_TOKENS: '600' }),
      body: withConfig({ thinkingConfig: { thinkingBudget: -1 } }),
    });
    expect(geminiBody(4).generationConfig.thinkingConfig.thinkingBudget).toBe(600);
  });

  it('refuses unknown thinking fields and budgets that are not whole numbers', async () => {
    await refused(withConfig({ thinkingConfig: { thinking_budget: 50_000 } }));
    await refused(withConfig({ thinkingConfig: { thinkingBudget: -2 } }));
    await refused(withConfig({ thinkingConfig: { thinkingBudget: 1.5 } }));
    await refused(withConfig({ thinkingConfig: 'high' }));
    expect(geminiCalls()).toHaveLength(0);
  });

  it.each(['MEDIA_RESOLUTION_HIGH', 'MEDIA_RESOLUTION_ULTRA_HIGH', 'high', 1])(
    'refuses mediaResolution %j',
    async (mediaResolution) => {
      await refused(withConfig({ mediaResolution }), /mediaResolution/);
      expect(geminiCalls()).toHaveLength(0);
    },
  );

  it('allows LOW and MEDIUM mediaResolution', async () => {
    for (const mediaResolution of ['MEDIA_RESOLUTION_LOW', 'MEDIA_RESOLUTION_MEDIUM']) {
      expect((await ask(withConfig({ mediaResolution }))).status).toBe(200);
    }
  });

  it('passes text, function calls, function responses and thought signatures through', async () => {
    const contents = [
      { role: 'user', parts: [{ text: 'Find invoice 12' }] },
      {
        role: 'model',
        parts: [
          {
            functionCall: { id: 'c1', name: 'find_invoice', args: { number: '12', due_date: 'x' } },
            thoughtSignature: 'c2lnbmF0dXJl',
          },
        ],
      },
      {
        role: 'user',
        parts: [
          { functionResponse: { id: 'c1', name: 'find_invoice', response: { found: false } } },
        ],
      },
      { role: 'model', parts: [{ text: 'thinking', thought: true }, { text: '' }] },
    ];
    expect((await ask({ contents })).status).toBe(200);
    expect(geminiBody().contents).toEqual(contents);
  });

  it.each([
    [{ functionCall: { name: 'f', args: {}, will_continue: true } }],
    [{ functionCall: { args: {} } }],
    [{ functionCall: { name: 'f', args: 'x' } }],
    [{ functionResponse: { name: 'f', response: {}, scheduling: 'SILENT' } }],
    [{ functionResponse: { name: 'f', response: 'done' } }],
    [{ text: 42 }],
    [{ thought: 'yes' }],
    [{ thoughtSignature: 5 }],
  ])('refuses the part %j', async (part) => {
    await refused({ contents: [{ role: 'model', parts: [part] }] });
    expect(geminiCalls()).toHaveLength(0);
  });

  it('drops unknown top-level fields, snake_case spellings included', async () => {
    const body = {
      ...question,
      generation_config: { max_output_tokens: 65_536, candidate_count: 8 },
      system_instruction: { parts: [{ file_data: { file_uri: 'https://example.com/a.pdf' } }] },
      safety_settings: [{ category: 'x', threshold: 'BLOCK_NONE' }],
      tool_config: { retrieval_config: {} },
      cached_content: 'cachedContents/someone-elses',
    };
    expect((await ask(body)).status).toBe(200);
    expect(Object.keys(geminiBody()).sort()).toEqual(['contents', 'generationConfig']);
    expect(geminiBody().generationConfig).toEqual({
      maxOutputTokens: 1024,
      candidateCount: 1,
      thinkingConfig: { thinkingLevel: 'low' },
    });
  });

  it('checks safetySettings, function declarations and toolConfig field by field', async () => {
    const good = {
      ...question,
      safetySettings: [{ category: 'HARM_CATEGORY_HARASSMENT', threshold: 'BLOCK_ONLY_HIGH' }],
      tools: [
        {
          functionDeclarations: [
            {
              name: 'find_invoice',
              description: 'Finds one.',
              parameters: { type: 'OBJECT', properties: { invoice_number: { type: 'STRING' } } },
            },
          ],
        },
      ],
      toolConfig: {
        functionCallingConfig: { mode: 'ANY', allowedFunctionNames: ['find_invoice'] },
      },
    };
    expect((await ask(good)).status).toBe(200);
    const sent = geminiBody();
    expect(sent.safetySettings).toEqual(good.safetySettings);
    expect(sent.tools).toEqual(good.tools);
    expect(sent.toolConfig).toEqual(good.toolConfig);

    await refused({ ...question, safetySettings: [{ category: 'x', threshold: 'y', extra: 1 }] });
    await refused({ ...question, safetySettings: ['x'] });
    await refused({
      ...question,
      tools: [{ functionDeclarations: [{ name: 'f', google_search: {} }] }],
    });
    await refused({ ...question, tools: [{ functionDeclarations: [{ description: 'no name' }] }] });
    await refused({ ...question, tools: [{ function_declarations: [{ name: 'f' }] }] });
    await refused({ ...question, toolConfig: { retrievalConfig: { languageCode: 'en' } } });
    await refused({ ...question, toolConfig: { function_calling_config: { mode: 'ANY' } } });
    await refused({
      ...question,
      toolConfig: { functionCallingConfig: { mode: 'ANY', allowed_function_names: ['f'] } },
    });
    expect(geminiCalls()).toHaveLength(1);
  });
});

describe('inline files', () => {
  const picture = { inlineData: { mimeType: 'image/png', data: 'iVBORw0KGgo=' } };
  const withParts = (parts) => ({ contents: [{ role: 'user', parts }] });

  it('accepts up to 10 inline files in a request, and refuses an 11th', async () => {
    const ten = Array.from({ length: 10 }, () => picture);
    expect((await send('/v1/generate', { body: withParts([{ text: 'x' }, ...ten]) })).status).toBe(
      200,
    );
    // Counted across the whole conversation, not per message.
    const spread = {
      contents: [
        { role: 'user', parts: ten.slice(0, 6) },
        { role: 'model', parts: [{ text: 'ok' }] },
        { role: 'user', parts: [...ten.slice(0, 5), { text: 'and these' }] },
      ],
    };
    const response = await send('/v1/generate', { body: spread });
    expect(response.status).toBe(400);
    expect((await errorOf(response)).message).toMatch(/at most 10 files/);
    expect(geminiCalls()).toHaveLength(1);
  });

  it('refuses a request made of many tiny pictures', async () => {
    const tiny = Array.from({ length: 1_794 }, () => picture);
    const response = await send('/v1/generate', {
      body: { ...withParts(tiny), generationConfig: { mediaResolution: 'MEDIA_RESOLUTION_HIGH' } },
    });
    expect(response.status).toBe(400);
    expect(geminiCalls()).toHaveLength(0);
  });

  it.each([
    'image/png',
    'image/jpeg',
    'image/webp',
    'image/heic',
    'image/heif',
    'application/pdf',
    'text/plain',
  ])('accepts %s', async (mimeType) => {
    const body = withParts([{ inlineData: { mimeType, data: 'aGVsbG8=' } }]);
    expect((await send('/v1/generate', { body })).status).toBe(200);
    expect(geminiBody().contents[0].parts[0].inlineData).toEqual({ mimeType, data: 'aGVsbG8=' });
  });

  it('sends the type in lower case', async () => {
    const body = withParts([{ inlineData: { mimeType: 'IMAGE/PNG', data: 'aGVsbG8=' } }]);
    expect((await send('/v1/generate', { body })).status).toBe(200);
    expect(geminiBody().contents[0].parts[0].inlineData.mimeType).toBe('image/png');
  });

  it.each([
    [{ mimeType: 'video/mp4', data: 'AAAA' }],
    [{ mimeType: 'audio/mpeg', data: 'AAAA' }],
    [{ mimeType: 'application/zip', data: 'AAAA' }],
    [{ mimeType: 'image/png' }],
    [{ mimeType: 'image/png', data: '' }],
    [{ mimeType: 'image/png', data: 42 }],
    [{ data: 'AAAA' }],
    [{ mime_type: 'image/png', data: 'AAAA' }],
    [{ mimeType: 'image/png', data: 'AAAA', displayName: 'x.png' }],
    ['AAAA'],
  ])('refuses inlineData %j', async (inlineData) => {
    const response = await send('/v1/generate', { body: withParts([{ inlineData }]) });
    expect(response.status).toBe(400);
    expect(geminiCalls()).toHaveLength(0);
  });
});

describe('rate limit', () => {
  it('answers 429 with Retry-After when the per-user limit is reached, without calling Google', async () => {
    const limit = vi.fn(async () => ({ success: false }));
    const response = await send('/v1/generate', { env: makeEnv({ AI_RATE_LIMITER: { limit } }) });
    expect(response.status).toBe(429);
    expect(response.headers.get('Retry-After')).toBe('60');
    expect(response.headers.get('Access-Control-Allow-Origin')).toBe(APP);
    expect((await errorOf(response)).code).toBe('rate_limited');
    expect(limit).toHaveBeenCalledWith({ key: USER_1 });
    expect(geminiCalls()).toHaveLength(0);
  });

  it('lets requests through under the limit', async () => {
    const limit = vi.fn(async () => ({ success: true }));
    const response = await send('/v1/stream', { env: makeEnv({ AI_RATE_LIMITER: { limit } }) });
    expect(response.status).toBe(200);
    expect(limit).toHaveBeenCalledTimes(1);
  });

  it('only counts signed-in requests', async () => {
    const limit = vi.fn(async () => ({ success: true }));
    await send('/v1/generate', { token: null, env: makeEnv({ AI_RATE_LIMITER: { limit } }) });
    expect(limit).not.toHaveBeenCalled();
  });

  it('carries on (and logs it) if the limiter fails', async () => {
    const limit = vi.fn(async () => {
      throw new Error('limiter down');
    });
    const response = await send('/v1/generate', { env: makeEnv({ AI_RATE_LIMITER: { limit } }) });
    expect(response.status).toBe(200);
    expect(logs.some((line) => line.includes('rate_limiter_failed'))).toBe(true);
  });

  it('works without the binding (tests, or not added in the dashboard)', async () => {
    expect((await send('/v1/generate')).status).toBe(200);
  });
});

describe('POST /v1/generate', () => {
  it("returns Gemini's answer as JSON", async () => {
    const response = await send('/v1/generate');
    expect(response.status).toBe(200);
    expect(response.headers.get('Content-Type')).toBe('application/json; charset=utf-8');
    expect(await response.json()).toEqual(geminiAnswer());
  });

  it('sends the key only in x-goog-api-key, never in the URL, and never back', async () => {
    const response = await send('/v1/generate');
    const text = await response.text();
    const [call] = geminiCalls();
    expect(call.method).toBe('POST');
    expect(call.headers.get('x-goog-api-key')).toBe(KEY);
    expect([...call.headers.keys()].sort()).toEqual(['content-type', 'x-goog-api-key']);
    expect(call.url).not.toContain(KEY);
    expect(call.url).not.toMatch(/[?&]key=/);
    expect(call.body).not.toContain(KEY);
    expect(text).not.toContain(KEY);
    expect([...response.headers.values()].join(' ')).not.toContain(KEY);
  });

  it('logs metadata only: route, status, model, user hash, time and token counts', async () => {
    await send('/v1/generate');
    const [line] = logLines();
    expect(line).toMatchObject({
      route: 'generate',
      method: 'POST',
      status: 200,
      model: 'gemini-3.6-flash',
      auth: 'checked',
      usage: { prompt: 12, output: 34, thoughts: 5, total: 51 },
    });
    expect(line.user).toMatch(/^[0-9a-f]{16}$/);
    expect(typeof line.ms).toBe('number');
    expect(Object.keys(line).sort()).toEqual(
      ['auth', 'method', 'model', 'ms', 'route', 'status', 'usage', 'user'].sort(),
    );
  });

  it('refuses to run without the GEMINI_API_KEY secret, without saying more', async () => {
    const response = await send('/v1/generate', { env: makeEnv({ GEMINI_API_KEY: '' }) });
    expect(response.status).toBe(500);
    const error = await errorOf(response);
    expect(error).toEqual({
      code: 'internal',
      message: 'The AI service is not set up yet.',
      status: 500,
    });
    expect(calls).toHaveLength(0);
    expect(logLines()[0].problem).toMatch(/GEMINI_API_KEY/);
  });
});

describe('Google errors', () => {
  it('passes on a 429 with the wait from RetryInfo', async () => {
    gemini = () =>
      googleError(429, {
        status: 'RESOURCE_EXHAUSTED',
        message: 'Quota exceeded for metric generate_content_requests, project 123456789.',
        details: [
          { '@type': 'type.googleapis.com/google.rpc.QuotaFailure', violations: [] },
          { '@type': 'type.googleapis.com/google.rpc.RetryInfo', retryDelay: '37s' },
        ],
      });
    const response = await send('/v1/generate');
    expect(response.status).toBe(429);
    expect(response.headers.get('Retry-After')).toBe('37');
    const error = await errorOf(response);
    expect(error.code).toBe('rate_limited');
    expect(error.message).toContain('37 seconds');
    expect(error.message).not.toContain('123456789');
  });

  it('rounds a fractional RetryInfo up, then falls back to Retry-After, then 30', async () => {
    gemini = () =>
      googleError(429, {
        status: 'RESOURCE_EXHAUSTED',
        details: [{ '@type': 'type.googleapis.com/google.rpc.RetryInfo', retryDelay: '1.2s' }],
      });
    expect((await send('/v1/generate')).headers.get('Retry-After')).toBe('2');
    gemini = () => googleError(429, { status: 'RESOURCE_EXHAUSTED' }, { 'Retry-After': '12' });
    expect((await send('/v1/generate')).headers.get('Retry-After')).toBe('12');
    gemini = () => new Response('Too Many Requests', { status: 429 });
    expect((await send('/v1/generate')).headers.get('Retry-After')).toBe('30');
  });

  it.each([
    [
      500,
      { status: 'INTERNAL', message: 'Internal error at backend shard xyz-42.' },
      502,
      'upstream_error',
    ],
    [503, { status: 'UNAVAILABLE', message: 'The model is overloaded.' }, 503, 'upstream_error'],
    [504, { status: 'DEADLINE_EXCEEDED', message: 'Deadline expired.' }, 504, 'upstream_timeout'],
    [
      403,
      {
        status: 'PERMISSION_DENIED',
        message: 'Generative Language API has not been used in project 123456789.',
      },
      502,
      'upstream_error',
    ],
    [
      401,
      { status: 'UNAUTHENTICATED', message: 'Request had invalid authentication credentials.' },
      502,
      'upstream_error',
    ],
    [
      404,
      {
        status: 'NOT_FOUND',
        message: 'models/gemini-3.6-flash is not found for API version v1beta.',
      },
      502,
      'upstream_error',
    ],
    [
      400,
      { status: 'FAILED_PRECONDITION', message: 'User location is not supported for the API use.' },
      502,
      'upstream_error',
    ],
  ])('maps a Google %i to %i %s without its internals', async (upstream, error, status, code) => {
    gemini = () => googleError(upstream, error);
    const response = await send('/v1/generate');
    expect(response.status).toBe(status);
    const body = await errorOf(response);
    expect(body.code).toBe(code);
    expect(body.message).not.toContain(error.message);
    expect(body.message).not.toContain('123456789');
    expect(logLines()[0]).toMatchObject({ upstream, googleStatus: error.status });
  });

  it('maps a rejected key (400 API_KEY_INVALID) to an upstream error and never echoes the key', async () => {
    gemini = () =>
      googleError(400, {
        status: 'INVALID_ARGUMENT',
        message: `API key not valid: ${KEY}. Please pass a valid API key.`,
        details: [
          { '@type': 'type.googleapis.com/google.rpc.ErrorInfo', reason: 'API_KEY_INVALID' },
        ],
      });
    const response = await send('/v1/generate');
    expect(response.status).toBe(502);
    const text = await response.text();
    expect(JSON.parse(text).error.code).toBe('upstream_error');
    expect(text).not.toContain(KEY);
    expect(logLines()[0]).toMatchObject({ upstream: 400, reason: 'API_KEY_INVALID' });
  });

  it("passes on a short version of Google's message for a request it couldn't use", async () => {
    gemini = () =>
      googleError(400, {
        status: 'INVALID_ARGUMENT',
        message: `Invalid value at 'contents[0].role' (TYPE_STRING), "robot". Key AIzaSyOTHER-key-0000000000 and ${KEY} ${'x'.repeat(400)}`,
      });
    const response = await send('/v1/generate');
    expect(response.status).toBe(400);
    const error = await errorOf(response);
    expect(error.code).toBe('bad_request');
    expect(error.message).toContain("Invalid value at 'contents[0].role'");
    expect(error.message).not.toContain(KEY);
    expect(error.message).not.toContain('AIzaSyOTHER');
    expect(error.message.length).toBeLessThan(300);
  });

  it('handles a Google error that is not JSON', async () => {
    gemini = () => new Response('<html>Bad gateway</html>', { status: 502 });
    const response = await send('/v1/generate');
    expect(response.status).toBe(502);
    expect(await response.text()).not.toContain('html');
  });

  it('handles an answer that is not JSON', async () => {
    gemini = () => new Response('not json', { status: 200 });
    const response = await send('/v1/generate');
    expect(response.status).toBe(502);
    expect((await errorOf(response)).code).toBe('upstream_error');
  });

  it('handles Google being unreachable', async () => {
    gemini = () => Promise.reject(new TypeError('fetch failed'));
    const response = await send('/v1/generate');
    expect(response.status).toBe(502);
    expect((await errorOf(response)).code).toBe('upstream_error');
  });

  it('times out a slow answer with upstream_timeout', async () => {
    gemini = hang;
    const response = await send('/v1/generate', { env: makeEnv({ GENERATE_TIMEOUT_MS: '30' }) });
    expect(response.status).toBe(504);
    expect((await errorOf(response)).code).toBe('upstream_timeout');
    expect(geminiCalls()[0].signal.aborted).toBe(true);
  });

  it('times out an answer whose body stalls', async () => {
    gemini = (call) => new Response(sseBody([], { signal: call.signal, then: 'hang' }));
    const response = await send('/v1/generate', { env: makeEnv({ GENERATE_TIMEOUT_MS: '30' }) });
    expect(response.status).toBe(504);
  });

  it('gives /v1/generate 90 seconds for the whole answer, and streams 30 to start', async () => {
    const delays = [];
    const real = globalThis.setTimeout;
    vi.spyOn(globalThis, 'setTimeout').mockImplementation((fn, ms, ...rest) => {
      delays.push(ms);
      return real(fn, ms, ...rest);
    });
    await send('/v1/generate');
    expect(delays).toContain(90_000);
    expect(delays).not.toContain(30_000);
    delays.length = 0;
    gemini = (call) => sseResponse(STREAM_EVENTS, call);
    await (await send('/v1/stream')).text();
    expect(delays).toContain(30_000);
    expect(delays).not.toContain(90_000);
  });

  it('times /v1/generate by GENERATE_TIMEOUT_MS only, including reading the answer', async () => {
    const slowly = (call) =>
      new Promise((resolve) =>
        setTimeout(
          () => resolve(new Response(sseBody([JSON.stringify(geminiAnswer())], call))),
          60,
        ),
      );
    gemini = slowly;
    const fast = makeEnv({ STREAM_START_TIMEOUT_MS: '10', GENERATE_TIMEOUT_MS: '2000' });
    expect((await send('/v1/generate', { env: fast })).status).toBe(200);

    // A body that starts at once but takes longer than the limit to finish.
    gemini = (call) => {
      const encoder = new TextEncoder();
      return new Response(
        new ReadableStream({
          start(controller) {
            controller.enqueue(encoder.encode('{"candidates":'));
            call.signal.addEventListener('abort', () =>
              controller.error(new DOMException('aborted', 'AbortError')),
            );
          },
        }),
      );
    };
    const response = await send('/v1/generate', { env: makeEnv({ GENERATE_TIMEOUT_MS: '40' }) });
    expect(response.status).toBe(504);
    expect((await errorOf(response)).code).toBe('upstream_timeout');
  });

  it('times the start of /v1/stream by STREAM_START_TIMEOUT_MS only', async () => {
    gemini = (call) =>
      new Promise((resolve) => setTimeout(() => resolve(sseResponse(STREAM_EVENTS, call)), 60));
    const env = makeEnv({ GENERATE_TIMEOUT_MS: '10', STREAM_START_TIMEOUT_MS: '2000' });
    const response = await send('/v1/stream', { env });
    expect(response.status).toBe(200);
    expect(await chunksOf(response)).toEqual(STREAM_EVENTS);
  });

  it('stops waiting for Google when the app goes away', async () => {
    gemini = hang;
    const controller = new AbortController();
    const pending = send('/v1/generate', { signal: controller.signal });
    await until(() => geminiCalls().length > 0);
    controller.abort();
    const response = await pending;
    expect(geminiCalls()[0].signal.aborted).toBe(true);
    expect(response.status).toBe(499);
    expect(logLines()[0]).toMatchObject({ status: 499, cancelled: true });
  });
});

describe('POST /v1/stream', () => {
  beforeEach(() => {
    gemini = (call) => sseResponse(STREAM_EVENTS, call);
  });

  it("passes Gemini's SSE chunks through unchanged and in order", async () => {
    const response = await send('/v1/stream');
    expect(response.status).toBe(200);
    expect(response.headers.get('Content-Type')).toBe('text/event-stream; charset=utf-8');
    expect(response.headers.get('Cache-Control')).toBe('no-store');
    expect(response.headers.get('X-Content-Type-Options')).toBe('nosniff');
    expect(response.headers.get('Access-Control-Allow-Origin')).toBe(APP);
    expect(await chunksOf(response)).toEqual(STREAM_EVENTS);
    const [call] = geminiCalls();
    expect(call.url).toBe(`${GEMINI}gemini-3.6-flash:streamGenerateContent?alt=sse`);
    expect(call.headers.get('x-goog-api-key')).toBe(KEY);
    expect(call.url).not.toContain(KEY);
  });

  it('hands each chunk on as it arrives, without waiting for the rest', async () => {
    const encoder = new TextEncoder();
    let upstream;
    gemini = () =>
      new Response(
        new ReadableStream({
          start(controller) {
            upstream = controller;
            controller.enqueue(encoder.encode(STREAM_EVENTS[0]));
          },
        }),
      );
    const response = await send('/v1/stream');
    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    expect(decoder.decode((await reader.read()).value)).toBe(STREAM_EVENTS[0]);
    upstream.enqueue(encoder.encode(STREAM_EVENTS[3]));
    expect(decoder.decode((await reader.read()).value)).toBe(STREAM_EVENTS[3]);
    upstream.close();
    expect((await reader.read()).done).toBe(true);
  });

  it('logs once at the end, with the token counts from the last event', async () => {
    const response = await send('/v1/stream');
    expect(logLines()).toHaveLength(0);
    await chunksOf(response);
    const lines = logLines();
    expect(lines).toHaveLength(1);
    expect(lines[0]).toMatchObject({
      route: 'stream',
      status: 200,
      model: 'gemini-3.6-flash',
      usage: { prompt: 12, output: 30, total: 42 },
    });
    expect(lines[0].user).toMatch(/^[0-9a-f]{16}$/);
  });

  it('answers a failure before the first byte as JSON, not as a stream', async () => {
    gemini = () =>
      googleError(429, {
        status: 'RESOURCE_EXHAUSTED',
        details: [{ '@type': 'type.googleapis.com/google.rpc.RetryInfo', retryDelay: '5s' }],
      });
    const response = await send('/v1/stream');
    expect(response.status).toBe(429);
    expect(response.headers.get('Retry-After')).toBe('5');
    expect((await errorOf(response)).code).toBe('rate_limited');

    gemini = () => googleError(500, { status: 'INTERNAL', message: 'boom' });
    const failed = await send('/v1/stream');
    expect(failed.status).toBe(502);
    expect((await errorOf(failed)).code).toBe('upstream_error');
  });

  it('times out when Google sends nothing at all, as JSON', async () => {
    gemini = hang;
    const response = await send('/v1/stream', { env: makeEnv({ STREAM_START_TIMEOUT_MS: '30' }) });
    expect(response.status).toBe(504);
    expect((await errorOf(response)).code).toBe('upstream_timeout');
  });

  it('times out when Google answers but never sends the first byte, as JSON', async () => {
    gemini = (call) => sseResponse([], call, 'hang');
    const response = await send('/v1/stream', { env: makeEnv({ STREAM_START_TIMEOUT_MS: '30' }) });
    expect(response.status).toBe(504);
    expect((await errorOf(response)).code).toBe('upstream_timeout');
    expect(geminiCalls()[0].signal.aborted).toBe(true);
  });

  it('treats an empty stream as an upstream error', async () => {
    gemini = (call) => sseResponse([], call);
    const response = await send('/v1/stream');
    expect(response.status).toBe(502);
    expect((await errorOf(response)).code).toBe('upstream_error');
  });

  it('ends with an "error" event when Google fails mid-stream', async () => {
    gemini = (call) => sseResponse(STREAM_EVENTS.slice(0, 2), call, 'error');
    const response = await send('/v1/stream');
    expect(response.status).toBe(200);
    const chunks = await chunksOf(response);
    expect(chunks.slice(0, 2)).toEqual(STREAM_EVENTS.slice(0, 2));
    expect(chunks).toHaveLength(3);
    const last = chunks[2];
    expect(last.startsWith('\n\n')).toBe(true);
    const match = /\n\nevent: error\ndata: (.*)\n\n$/.exec(last);
    expect(match).not.toBeNull();
    expect(JSON.parse(match[1])).toEqual({
      error: {
        code: 'upstream_error',
        message: 'The AI service stopped in the middle of the answer.',
        status: 502,
      },
    });
    expect(logLines()[0]).toMatchObject({ status: 200, code: 'upstream_error', streamError: 502 });
  });

  it('ends with an upstream_timeout event when Google goes quiet mid-stream', async () => {
    gemini = (call) => sseResponse(STREAM_EVENTS.slice(0, 1), call, 'hang');
    const response = await send('/v1/stream', { env: makeEnv({ STREAM_IDLE_TIMEOUT_MS: '30' }) });
    const chunks = await chunksOf(response);
    expect(chunks[0]).toBe(STREAM_EVENTS[0]);
    const event = /event: error\ndata: (.*)\n\n$/.exec(chunks.at(-1));
    expect(JSON.parse(event[1]).error).toMatchObject({ code: 'upstream_timeout', status: 504 });
    expect(geminiCalls()[0].signal.aborted).toBe(true);
  });

  it('stops Google when the app closes the stream', async () => {
    gemini = (call) => sseResponse(STREAM_EVENTS.slice(0, 1), call, 'hang');
    const response = await send('/v1/stream');
    const reader = response.body.getReader();
    await reader.read();
    await reader.cancel();
    expect(geminiCalls()[0].signal.aborted).toBe(true);
    expect(logLines()[0]).toMatchObject({ route: 'stream', status: 499, cancelled: true });
  });

  it('stops Google when the runtime reports the app has gone (request.signal)', async () => {
    gemini = (call) => sseResponse(STREAM_EVENTS.slice(0, 1), call, 'hang');
    const controller = new AbortController();
    const response = await send('/v1/stream', { signal: controller.signal });
    const reader = response.body.getReader();
    await reader.read();
    controller.abort();
    expect(geminiCalls()[0].signal.aborted).toBe(true);
    expect(logLines()).toHaveLength(1);
    expect(logLines()[0]).toMatchObject({ route: 'stream', status: 499, cancelled: true });
    await reader.cancel();
    expect(logLines()).toHaveLength(1);
  });

  it('never puts the key in the stream', async () => {
    const text = (await chunksOf(await send('/v1/stream'))).join('');
    expect(text).not.toContain(KEY);
  });
});

describe('every response', () => {
  it('has Cache-Control: no-store and X-Content-Type-Options: nosniff', async () => {
    const responses = [
      await send('/health', { method: 'GET' }),
      await send('/v1/generate', { method: 'OPTIONS' }),
      await send('/v1/generate', { origin: 'https://evil.example' }),
      await send('/nowhere', { method: 'GET' }),
      await send('/v1/generate', { token: null }),
      await send('/v1/generate'),
      await send('/v1/generate', { body: 'nope' }),
    ];
    gemini = (call) => sseResponse(STREAM_EVENTS, call);
    responses.push(await send('/v1/stream'));
    for (const response of responses) {
      expect(response.headers.get('Cache-Control')).toBe('no-store');
      expect(response.headers.get('X-Content-Type-Options')).toBe('nosniff');
      expect(response.headers.get('Vary')).toBe('Origin');
      await response.body?.cancel();
    }
  });
});
