// SPDX-License-Identifier: AGPL-3.0-only
//
// Railway template patches for the World Monitor app image (upstream v2.11.1).
//
// Each patch replaces one exact upstream snippet. The build fails if a snippet
// is missing or appears more than once, so a future upstream change cannot be
// patched silently in the wrong place.
//
// Usage: node patch-app.mjs [sidecar-file] [nginx-template]

import { readFileSync, writeFileSync } from 'node:fs';

const sidecarFile = process.argv[2] ?? '/app/local-api-server.mjs';
const nginxFile = process.argv[3] ?? '/etc/nginx/nginx.conf.template';

function patchOnce(file, label, search, replacement, marker) {
  const source = readFileSync(file, 'utf8');
  if (source.includes(marker)) {
    console.error(`[patch] ${label}: ${file} is already patched`);
    process.exit(1);
  }
  const count = source.split(search).length - 1;
  if (count !== 1) {
    console.error(`[patch] ${label}: expected exactly 1 match in ${file}, found ${count}`);
    process.exit(1);
  }
  // A function replacement keeps "$" sequences in the new text literal.
  writeFileSync(file, source.replace(search, () => replacement));
  console.log(`[patch] ${label}: applied to ${file}`);
}

// 1. Let the API sidecar reach the AIS relay over Railway's private network.
//    In Docker mode the sidecar's SSRF guard only trusts the configured
//    UPSTASH_REDIS_REST_URL, LLM_API_URL and OLLAMA_API_URL origins, so a
//    private WS_RELAY_URL (upstream compose uses http://ais-relay:3004) is
//    refused and vessels, flights, Telegram, OREF and relay-backed market
//    routes come back empty. This trusts exactly the configured relay origin,
//    using the same mechanism upstream uses for Redis.
const redisOriginLine =
  "addConfiguredPrivateOrigin('UPSTASH_REDIS_REST_URL', 'Redis calls will be SSRF-blocked');";
patchOnce(
  sidecarFile,
  'sidecar: trust configured WS_RELAY_URL origin',
  redisOriginLine,
  `${redisOriginLine}\n` +
    '        // Railway template patch: trust the configured relay origin as well.\n' +
    "        addConfiguredPrivateOrigin('WS_RELAY_URL', 'relay calls will be SSRF-blocked');",
  "addConfiguredPrivateOrigin('WS_RELAY_URL'",
);

// 2. Dual-stack nginx. Upstream listens on IPv4 only ("listen 8080;"). The
//    include file is written at start by railway-entrypoint.sh: it holds
//    "listen [::]:8080;" when the container has IPv6, otherwise a comment.
patchOnce(
  nginxFile,
  'nginx: optional IPv6 listener',
  '    listen 8080;\n',
  '    listen 8080;\n    include /tmp/nginx-listen-ipv6.conf;\n',
  'nginx-listen-ipv6.conf',
);
