// SPDX-License-Identifier: AGPL-3.0-only
//
// Railway template patches for World Monitor's Upstash-compatible Redis REST
// proxy (upstream docker/redis-rest-proxy.mjs, v2.11.1).
//
//   1. GET /healthz answers without the bearer token: 200 while the Redis
//      client is ready, 503 otherwise. Every upstream route requires the
//      token, so Railway's healthcheck had nothing to probe.
//   2. Listen on SRH_LISTEN_HOST (start.sh sets "::" when the container has
//      IPv6) instead of the hardcoded IPv4-only 0.0.0.0. Node's "::" socket is
//      dual-stack, so both IPv4 and IPv6 private-network callers reach it.
//
// The build fails unless every anchor is found exactly once.
//
// Usage: node patch-redis-rest.mjs [proxy-file]

import { readFileSync, writeFileSync } from 'node:fs';

const file = process.argv[2] ?? '/app/redis-rest-proxy.mjs';
let source = readFileSync(file, 'utf8');
if (source.includes('Railway template patch')) {
  console.error(`[patch] redis-rest: ${file} is already patched`);
  process.exit(1);
}

function patchOnce(label, search, replacement) {
  const count = source.split(search).length - 1;
  if (count !== 1) {
    console.error(`[patch] ${label}: expected exactly 1 match in ${file}, found ${count}`);
    process.exit(1);
  }
  source = source.replace(search, () => replacement);
  console.log(`[patch] ${label}: applied`);
}

patchOnce(
  'redis-rest: unauthenticated /healthz',
  '  if (!checkAuth(req)) {\n',
  [
    "  // Railway template patch: token-free readiness probe for Railway's healthcheck.",
    "  if (req.method === 'GET' && req.url === '/healthz') {",
    '    const ready = client.isReady === true;',
    '    res.writeHead(ready ? 200 : 503);',
    "    res.end(JSON.stringify({ status: ready ? 'ok' : 'redis-unavailable' }));",
    '    return;',
    '  }',
    '',
    '  if (!checkAuth(req)) {',
    '',
  ].join('\n'),
);

patchOnce(
  'redis-rest: configurable listen host',
  "server.listen(PORT, '0.0.0.0', () => {\n  console.log(`Redis REST proxy listening on 0.0.0.0:${PORT}`);",
  "const LISTEN_HOST = process.env.SRH_LISTEN_HOST || '0.0.0.0';\n" +
    'server.listen(PORT, LISTEN_HOST, () => {\n' +
    '  console.log(`Redis REST proxy listening on ${LISTEN_HOST}:${PORT}`);',
);

writeFileSync(file, source);
