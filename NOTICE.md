# Notice

## Upstream software

| Component | Source | License |
|---|---|---|
| World Monitor (dashboard, API sidecar, AIS relay, seed scripts, Redis REST proxy) | [koala73/worldmonitor](https://github.com/koala73/worldmonitor), tag `v2.11.1`, commit `39e02521cda64be65c3bcf7ec313645a3d09445b` | GNU Affero General Public License v3.0 (AGPL-3.0) |
| Caddy | `caddy:2.11.7-alpine` (Docker official image) | Apache-2.0 |
| Redis | `redis:8.2.10` (Docker official image) | Redis 8: RSALv2, SSPLv1 or AGPLv3, at the user's choice |
| node-redis | npm `redis@4.7.1` | MIT |
| Node.js base image | `node:24.21.0-alpine3.24` (Docker official image) | MIT (Node.js) and the licenses of the Alpine packages |

The images are built at deploy time from these sources. This repository does not contain World Monitor's source code, apart from the short snippets the patch scripts search for and replace.

## Verified against

Checked on 2026-10-20 against the current stable release, **v2.11.1** (published 2026-10-19; `main` was 0 commits ahead of the tag):

- `docker-compose.yml`, `SELF_HOSTING.md`, `.env.example`, `.dockerignore`
- `Dockerfile` (full self-hosted image), `Dockerfile.relay`, `docker/Dockerfile` (frontend-only image), `docker/Dockerfile.redis-rest`, `Dockerfile.seed-bundle-*`
- `docker/entrypoint.sh`, `docker/nginx.conf`, `docker/supervisord.conf`, `docker/render-nginx-realip.mjs`, `docker/validate-session-secret.mjs`, `docker/redis-rest-proxy.mjs`
- `src-tauri/sidecar/local-api-server.mjs` (SSRF guard, Docker mode), `server/gateway.ts` (relay and seed-refresh keys), `server/_shared/llm.ts` (LLM providers), `api/mcp/auth.ts` (MCP key check)
- `scripts/ais-relay.cjs`, `scripts/run-seeders.sh`, `scripts/_bundle-runner.mjs`, `scripts/seed-*.mjs`, `scripts/railway-services.json`, `docs/railway-seed-consolidation-runbook.md`
- `.github/workflows/docker-publish.yml` (what `ghcr.io/koala73/worldmonitor` contains)

Tag and commit came from the GitHub API; the local reference copy matched the tag's blob SHAs for the files above that were compared.

## AGPL-3.0 notes

World Monitor is licensed under the AGPL-3.0. This template builds it from the unmodified upstream release and then applies four small, documented modifications at build time:

| Patch script | Modified upstream file | Change |
|---|---|---|
| `services/worldmonitor/patches/patch-app.mjs` | `src-tauri/sidecar/local-api-server.mjs` | Trusts the configured private `WS_RELAY_URL` origin in Docker mode |
| `services/worldmonitor/patches/patch-app.mjs` | `docker/nginx.conf` | Includes an optional `listen [::]:8080;` |
| `services/worker/patches/patch-relay.mjs` | `scripts/ais-relay.cjs` | Four warm-ping URLs follow `API_BASE_URL` |
| `services/redis-rest/patches/patch-redis-rest.mjs` | `docker/redis-rest-proxy.mjs` | Token-free `GET /healthz`, configurable listen host |

What this means for operators (practical guidance, not legal advice; get professional advice for your situation):

- The deployed services are a **modified version** of World Monitor, so AGPL-3.0 applies to them. Section 13 asks that users who interact with the program over a network can get its Corresponding Source. For this deployment that is the upstream v2.11.1 source plus the patch scripts and Dockerfiles in this repository. Keep this repository (or your fork of it) public, and keep World Monitor's own source links in the UI.
- If you change the World Monitor code further, publish those changes under the AGPL-3.0 as well.
- The files in `services/` that patch, build or start World Monitor are offered under the AGPL-3.0 (they carry `SPDX-License-Identifier: AGPL-3.0-only` where they are scripts), so the whole build recipe is available under the same terms as the program.

## Written for this template

Everything in this repository was written for this template, using upstream's documentation and source as reference:

- `services/worldmonitor/Dockerfile`: re-creates the build steps and order of upstream's root `Dockerfile` (same commands, stages and runtime layout) around a pinned source download.
- `services/worker/Dockerfile`: relay and seed image; follows the runtime set-up of upstream's `Dockerfile.relay` and the "ship the whole tree" approach of upstream's seeder Dockerfiles.
- `services/redis-rest/Dockerfile`: follows `docker/Dockerfile.redis-rest`.
- `services/worker/run-seeders.sh` and `tiers/*.txt`: the cron runner and schedules. The idea comes from upstream's `scripts/run-seeders.sh` and production cron table; no code was copied.
- `services/gateway/*`, all patch scripts, `TEMPLATE.md`, `template.json`, `README.md`, this file.

## Reference only (not copied)

- Railway marketplace template "World Monitor Self-Hosted" and its source fork `protemplate/worldmonitor` (branch `railway-stable`): read for ideas (service split, basic-auth gateway, relay insecure-HTTP flag). No files, scripts or text were copied.
- Railway marketplace template "worldmonitor" (`xiaosong233/worldmonitor-railway`): reviewed, not used.
- Railway base definition for Redis (`templates/_railway-base/redis.json`): service shape and variables reused as the standard asks.

## Trademarks

"World Monitor" and its logo belong to their respective owners. The template icon is World Monitor's own favicon, loaded from the upstream repository. This is a community template, not affiliated with, made, endorsed or supported by the World Monitor authors, Redis Ltd. or the Caddy project.
