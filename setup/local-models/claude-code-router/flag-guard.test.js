// Tests fuer flag-guard.js. Ausfuehren: node --test setup/local-models/claude-code-router/flag-guard.test.js
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const {
  createGuard,
  readConfig,
  sessionKey,
  toLocalBody,
  refusalSniffer,
  createFlagStore,
} = require('./flag-guard.js');

const REFUSAL_SSE =
  'event: message_delta\ndata: {"type":"message_delta","delta":{"stop_reason":"refusal"}}\n\n';
const OK_SSE =
  'event: message_delta\ndata: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}\n\n';

function listen(server) {
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server.address().port)));
}

function fakeServer(name, reply) {
  const calls = [];
  const server = http.createServer((req, res) => {
    let raw = '';
    req.on('data', (c) => (raw += c));
    req.on('end', () => {
      calls.push({ headers: req.headers, body: raw ? JSON.parse(raw) : null });
      res.writeHead(200, { 'content-type': 'text/event-stream' });
      res.end(reply(calls.length));
    });
  });
  return { name, server, calls };
}

function post(port, path, body, headers = {}) {
  return new Promise((resolve, reject) => {
    const req = http.request(
      { host: '127.0.0.1', port, path, method: 'POST', headers: { 'content-type': 'application/json', ...headers } },
      (res) => {
        let data = '';
        res.on('data', (c) => (data += c));
        res.on('end', () => resolve({ status: res.statusCode, data }));
      },
    );
    req.on('error', reject);
    req.end(JSON.stringify(body));
  });
}

test('readConfig: Standardwerte und Validierung', () => {
  const config = readConfig({});
  assert.equal(config.port, 3457);
  assert.equal(config.host, '127.0.0.1');
  assert.equal(config.ttlMs, 60 * 60 * 1000);
  assert.throws(() => readConfig({ FLAG_GUARD_PORT: 'abc' }));
  assert.throws(() => readConfig({ FLAG_GUARD_TTL_MIN: '0' }));
});

test('sessionKey: stabil je Sitzung, null ohne Anker', () => {
  const a = { metadata: { user_id: 'session_1' }, messages: [{ role: 'user', content: 'x' }] };
  const b = { metadata: { user_id: 'session_1' }, messages: [{ role: 'user', content: 'y' }] };
  const c = { metadata: { user_id: 'session_2' }, messages: [] };
  assert.equal(sessionKey(a), sessionKey(b));
  assert.notEqual(sessionKey(a), sessionKey(c));
  assert.equal(sessionKey({ messages: [] }), null);
  assert.ok(sessionKey({ messages: [{ role: 'user', content: [{ type: 'text', text: 'hi' }] }] }));
});

test('toLocalBody: entfernt cache_control, metadata, tool_choice ohne Mutation', () => {
  const input = {
    model: 'claude-x',
    metadata: { user_id: 'u' },
    tool_choice: { type: 'auto' },
    system: [{ type: 'text', text: 's', cache_control: { type: 'ephemeral' } }],
    messages: [{ role: 'user', content: [{ type: 'text', text: 'hi', cache_control: { type: 'ephemeral' } }] }],
  };
  const snapshot = JSON.stringify(input);
  const out = toLocalBody(input, 'qwen');
  assert.equal(out.model, 'qwen');
  assert.equal(out.metadata, undefined);
  assert.equal(out.tool_choice, undefined);
  assert.equal(JSON.stringify(out).includes('cache_control'), false);
  assert.equal(JSON.stringify(input), snapshot);
});

test('refusalSniffer: erkennt refusal auch ueber Chunk-Grenzen', () => {
  const sniffer = refusalSniffer();
  sniffer.push(Buffer.from('data: {"delta":{"stop_rea'));
  assert.equal(sniffer.refused, false);
  sniffer.push(Buffer.from('son": "refusal"}}\n\n'));
  assert.equal(sniffer.refused, true);
  const clean = refusalSniffer();
  clean.push(Buffer.from(OK_SSE));
  assert.equal(clean.refused, false);
});

test('createFlagStore: laeuft nach TTL ab', () => {
  let now = 1000;
  const store = createFlagStore(500, () => now);
  store.flag('k');
  assert.equal(store.isFlagged('k'), true);
  now = 1600;
  assert.equal(store.isFlagged('k'), false);
  assert.equal(store.size(), 0);
});

test('Integration: nach refusal geht die Sitzung lokal, ohne API-Key, andere Sitzungen nicht', async (t) => {
  const upstream = fakeServer('upstream', (n) => (n === 1 ? REFUSAL_SSE : OK_SSE));
  const local = fakeServer('local', () => OK_SSE);
  const upPort = await listen(upstream.server);
  const localPort = await listen(local.server);
  const guard = createGuard(
    readConfig({
      FLAG_GUARD_UPSTREAM: `http://127.0.0.1:${upPort}`,
      FLAG_GUARD_LOCAL: `http://127.0.0.1:${localPort}`,
      FLAG_GUARD_LOCAL_MODEL: 'qwen-test',
    }),
    () => {},
  );
  const guardPort = await listen(guard);
  t.after(() => [upstream.server, local.server, guard].forEach((s) => s.close()));

  const flagged = { model: 'claude-x', metadata: { user_id: 'A' }, messages: [{ role: 'user', content: 'a' }] };
  const other = { model: 'claude-x', metadata: { user_id: 'B' }, messages: [{ role: 'user', content: 'b' }] };
  const auth = { 'x-api-key': 'test-key', 'anthropic-version': '2023-06-01' };

  const first = await post(guardPort, '/v1/messages', flagged, auth);
  assert.match(first.data, /refusal/);
  assert.equal(upstream.calls.length, 1);
  assert.equal(upstream.calls[0].headers['x-api-key'], 'test-key');

  await post(guardPort, '/v1/messages', flagged, auth);
  assert.equal(local.calls.length, 1);
  assert.equal(local.calls[0].body.model, 'qwen-test');
  assert.equal(local.calls[0].headers['x-api-key'], undefined);

  await post(guardPort, '/v1/messages', other, auth);
  assert.equal(upstream.calls.length, 2);

  await post(guardPort, '/_flag-guard/reset', {});
  await post(guardPort, '/v1/messages', flagged, auth);
  assert.equal(upstream.calls.length, 3);
  assert.equal(local.calls.length, 1);
});

test('Integration: Ziel nicht erreichbar -> 502 mit Anthropic-Fehlerformat', async (t) => {
  const guard = createGuard(readConfig({ FLAG_GUARD_UPSTREAM: 'http://127.0.0.1:1' }), () => {});
  const guardPort = await listen(guard);
  t.after(() => guard.close());
  const res = await post(guardPort, '/v1/messages', { messages: [{ role: 'user', content: 'x' }] });
  assert.equal(res.status, 502);
  assert.equal(JSON.parse(res.data).type, 'error');
});
