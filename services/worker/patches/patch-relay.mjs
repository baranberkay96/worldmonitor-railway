// SPDX-License-Identifier: AGPL-3.0-only
//
// Railway template patch for the World Monitor AIS relay (upstream v2.11.1).
//
// The relay's four cache warm-ping loops (service statuses, CII risk scores,
// chokepoint status, cable health) call the hosted api.worldmonitor.app and
// send WORLDMONITOR_RELAY_KEY with every ping. On a self-hosted stack that
// warms someone else's cache and hands our relay secret to a third party.
// Upstream already reads API_BASE_URL for the classify loop (#7437); this
// makes the warm-pings use it too. With API_BASE_URL unset the URLs are
// exactly upstream's.
//
// The build fails unless all four constants are found exactly once.
//
// Usage: node patch-relay.mjs [relay-file]

import { readFileSync, writeFileSync } from 'node:fs';

const relayFile = process.argv[2] ?? '/app/scripts/ais-relay.cjs';
const HOSTED = 'https://api.worldmonitor.app';
const CONSTANTS = [
  'SERVICE_STATUSES_RPC_URL',
  'CII_RPC_URL',
  'CHOKEPOINT_RPC_URL',
  'CABLE_HEALTH_RPC_URL',
];

let source = readFileSync(relayFile, 'utf8');

for (const name of CONSTANTS) {
  const pattern = new RegExp(`^const ${name} = '${HOSTED.replace(/[.]/g, '\\.')}(/api/[^']+)';$`, 'gm');
  const matches = [...source.matchAll(pattern)];
  if (matches.length !== 1) {
    console.error(`[patch] relay ${name}: expected exactly 1 definition, found ${matches.length}`);
    process.exit(1);
  }
  const apiPath = matches[0][1];
  const replacement =
    `const ${name} = (process.env.API_BASE_URL || '${HOSTED}').replace(/\\/+$/, '') + '${apiPath}';`;
  source = source.replace(pattern, () => replacement);
  console.log(`[patch] relay ${name}: now follows API_BASE_URL (${apiPath})`);
}

const leftover = source.match(/^const [A-Z_]+_RPC_URL = 'https:\/\/api\.worldmonitor\.app/gm);
if (leftover) {
  console.error(`[patch] relay: unpatched hosted warm-ping constants remain: ${leftover.join(', ')}`);
  process.exit(1);
}

writeFileSync(relayFile, source);
