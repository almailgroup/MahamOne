/**
 * `server-only` throws on import outside a server render, which is exactly its
 * job — and which makes any module that imports it untestable. Under Vitest it
 * resolves here instead, so server modules can be unit tested without
 * weakening the guard that protects them in the real build.
 */
export {};
