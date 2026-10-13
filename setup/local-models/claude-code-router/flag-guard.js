#!/usr/bin/env node
// flag-guard: kleiner Proxy zwischen claude-code-router (ccr) und der Anthropic-API.
//
// Reicht alles unveraendert durch. Lehnt Anthropic eine Antwort ab
// (stop_reason "refusal"), merkt er sich die Sitzung und schickt deren weitere
// Anfragen fuer FLAG_GUARD_TTL_MIN Minuten an das lokale Modell (Ollama,
// Anthropic-kompatibles /v1/messages). Danach wieder Claude.
//
// Keine Abhaengigkeiten, Node >= 18. Lauscht nur auf 127.0.0.1.
// Logs enthalten nie Inhalte, nur gekuerzte Sitzungs-Hashes.
//
// Umgebung:
//   FLAG_GUARD_PORT         Standard 3457
//   FLAG_GUARD_UPSTREAM     Standard https://api.anthropic.com
//   FLAG_GUARD_LOCAL        Standard http://127.0.0.1:11434 (Ollama)
//   FLAG_GUARD_LOCAL_MODEL  Standard qwen3-coder:30b
//   FLAG_GUARD_TTL_MIN      Standard 60
//
// Zuruecksetzen: curl -X POST http://127.0.0.1:3457/_flag-guard/reset
'use strict';

const http = require('node:http');
const https = require('node:https');
const crypto = require('node:crypto');
const { StringDecoder } = require('node:string_decoder');

const MAX_BODY_BYTES = 50 * 1024 * 1024;
const SNIFF_TAIL_CHARS = 256;
const REFUSAL_RE = /"stop_reason"\s*:\s*"refusal"/;
const MESSAGES_PATH = '/v1/messages';
const RESET_PATH = '/_flag-guard/reset';
const HOP_BY_HOP = new Set([
  'connection', 'keep-alive', 'proxy-connection', 'transfer-encoding', 'upgrade',
  'te', 'trailer', 'host', 'content-length', 'accept-encoding',
]);

function log(line) {
  process.stderr.write(`${new Date().toISOString()} flag-guard: ${line}\n`);
}

function readConfig(env = process.env) {
  const port = Number(env.FLAG_GUARD_PORT || 3457);
  const ttlMin = Number(env.FLAG_GUARD_TTL_MIN || 60);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error('FLAG_GUARD_PORT ungueltig');
  }
  if (!(ttlMin > 0)) throw new Error('FLAG_GUARD_TTL_MIN muss > 0 sein');
  return Object.freeze({
    host: '127.0.0.1',
    port,
    upstream: (env.FLAG_GUARD_UPSTREAM || 'https://api.anthropic.com').replace(/\/+$/, ''),
    local: (env.FLAG_GUARD_LOCAL || 'http://127.0.0.1:11434').replace(/\/+$/, ''),
    localModel: env.FLAG_GUARD_LOCAL_MODEL || 'qwen3-coder:30b',
    ttlMin,
    ttlMs: ttlMin * 60 * 1000,
  });
}

function textOf(content) {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';
  return content.map((part) => (part && typeof part.text === 'string' ? part.text : '')).join('');
}

// Stabil ueber eine Unterhaltung: Claude Code schickt die Sitzungs-ID in metadata.user_id;
// sonst dient die erste Nachricht als Anker. Ohne beides: null (nie umleiten).
function sessionKey(body) {
  const userId = body && body.metadata && body.metadata.user_id;
  const first = body && Array.isArray(body.messages) ? body.messages[0] : undefined;
  const firstText = first ? textOf(first.content) : '';
  const seed = userId ? `u:${userId}` : firstText ? `m:${firstText}` : '';
  if (!seed) return null;
  return crypto.createHash('sha256').update(seed).digest('hex').slice(0, 16);
}

function stripCacheControl(value) {
  if (Array.isArray(value)) return value.map(stripCacheControl);
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value)
        .filter(([key]) => key !== 'cache_control')
        .map(([key, inner]) => [key, stripCacheControl(inner)]),
    );
  }
  return value;
}

// Ollama kennt weder Prompt-Caching noch metadata/tool_choice: entfernen, Eingabe bleibt unveraendert.
function toLocalBody(body, model) {
  // eslint-disable-next-line no-unused-vars
  const { metadata, tool_choice, ...rest } = stripCacheControl(body);
  return { ...rest, model };
}

function refusalSniffer() {
  const decoder = new StringDecoder('utf8');
  let tail = '';
  let refused = false;
  return {
    push(chunk) {
      if (refused) return;
      const text = tail + decoder.write(chunk);
      refused = REFUSAL_RE.test(text);
      tail = text.slice(-SNIFF_TAIL_CHARS);
    },
    get refused() {
      return refused;
    },
  };
}

function createFlagStore(ttlMs, now = Date.now) {
  const flaggedUntil = new Map();
  return {
    flag(key) {
      flaggedUntil.set(key, now() + ttlMs);
    },
    isFlagged(key) {
      const until = flaggedUntil.get(key);
      if (until === undefined) return false;
      if (until > now()) return true;
      flaggedUntil.delete(key);
      return false;
    },
    clear() {
      flaggedUntil.clear();
    },
    size() {
      return flaggedUntil.size;
    },
  };
}

function filterHeaders(headers) {
  return Object.fromEntries(
    Object.entries(headers).filter(([key]) => !HOP_BY_HOP.has(key.toLowerCase())),
  );
}

function readBody(req, limit = MAX_BODY_BYTES) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > limit) {
        reject(new Error('Request-Body zu gross'));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

function forward({ target, method, headers, body, res, onChunk }) {
  const url = new URL(target);
  const client = url.protocol === 'https:' ? https : http;
  return new Promise((resolve, reject) => {
    const upstreamReq = client.request(
      url,
      {
        method,
        headers: { ...headers, 'accept-encoding': 'identity', 'content-length': body.length },
      },
      (upstreamRes) => {
        res.writeHead(upstreamRes.statusCode || 502, filterHeaders(upstreamRes.headers));
        upstreamRes.on('data', (chunk) => {
          if (onChunk) onChunk(chunk);
          res.write(chunk);
        });
        upstreamRes.on('end', () => {
          res.end();
          resolve(upstreamRes.statusCode);
        });
        upstreamRes.on('error', reject);
      },
    );
    upstreamReq.on('error', reject);
    upstreamReq.end(body);
  });
}

function sendJson(res, status, payload) {
  const data = JSON.stringify(payload);
  res.writeHead(status, { 'content-type': 'application/json', 'content-length': Buffer.byteLength(data) });
  res.end(data);
}

function parseJson(raw) {
  if (!raw.length) return null;
  try {
    return JSON.parse(raw.toString('utf8'));
  } catch {
    return null;
  }
}

function createGuard(config, logLine = log) {
  const store = createFlagStore(config.ttlMs);

  async function handle(req, res) {
    const path = (req.url || '/').split('?')[0];
    if (req.method === 'POST' && path === RESET_PATH) {
      store.clear();
      logLine('alle Sitzungen zurueckgesetzt');
      sendJson(res, 200, { ok: true });
      return;
    }

    const raw = await readBody(req);
    const isMessages = req.method === 'POST' && path === MESSAGES_PATH;
    const body = isMessages ? parseJson(raw) : null;
    const key = body ? sessionKey(body) : null;

    if (key && store.isFlagged(key)) {
      logLine(`sitzung ${key} -> lokal (${config.localModel})`);
      // Bewusst ohne x-api-key/authorization: der Anthropic-Schluessel geht nie an Ollama.
      await forward({
        target: `${config.local}${MESSAGES_PATH}`,
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'anthropic-version': req.headers['anthropic-version'] || '2023-06-01',
        },
        body: Buffer.from(JSON.stringify(toLocalBody(body, config.localModel))),
        res,
      });
      return;
    }

    const sniffer = refusalSniffer();
    await forward({
      target: `${config.upstream}${req.url}`,
      method: req.method,
      headers: filterHeaders(req.headers),
      body: raw,
      res,
      onChunk: isMessages ? (chunk) => sniffer.push(chunk) : null,
    });
    if (sniffer.refused && key) {
      store.flag(key);
      logLine(`refusal: sitzung ${key} fuer ${config.ttlMin} min lokal`);
    }
  }

  return http.createServer((req, res) => {
    handle(req, res).catch((err) => {
      logLine(`fehler: ${err.message}`);
      if (!res.headersSent) {
        sendJson(res, 502, {
          type: 'error',
          error: { type: 'api_error', message: 'flag-guard: Ziel nicht erreichbar' },
        });
      } else {
        res.destroy();
      }
    });
  });
}

module.exports = {
  createGuard,
  readConfig,
  sessionKey,
  toLocalBody,
  refusalSniffer,
  createFlagStore,
};

if (require.main === module) {
  const config = readConfig();
  createGuard(config).listen(config.port, config.host, () => {
    log(`lauscht auf ${config.host}:${config.port} -> ${config.upstream}; bei refusal lokal ${config.localModel}`);
  });
}
