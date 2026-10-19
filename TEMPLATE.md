# World Monitor v2 Global Intelligence Dashboard — Railway template spec

## Listing

| Field | Value |
|---|---|
| Name | **World Monitor v2 Global Intelligence Dashboard** (`v2` = World Monitor major version; source pinned to `v2.11.1`) |
| Description | Real-time news, conflict and market signals on one AI-powered map. (66 chars) |
| Category | Analytics |
| Tags | worldmonitor, osint, geopolitics, dashboard, news, maps, markets, intelligence, mcp |
| Icon | `https://cdn.jsdelivr.net/gh/koala73/worldmonitor@v2.11.1/public/favico/android-chrome-512x512.png` (HTTP 200, image/png, checked 2026-10-20) |
| User input at deploy | **None.** Every secret is generated. All API keys are optional (see "Data sources and API keys"). |
| Repo for built services | `baranberkay96/worldmonitor-railway` (`/services/gateway`, `/services/worldmonitor`, `/services/worker`, `/services/redis-rest`) |

**Listing wording check.** Without any key the dashboard shows live news (RSS digest), conflict and protest signals (GDELT, which drives the Country Instability Index since v10/v11), and market data (Yahoo quotes via the relay, crypto, stablecoins, prediction markets, ETF flows). "AI-powered" holds without paid keys, with a caveat that README states plainly: server-side AI briefs, summaries and news threat labels need an LLM, which can be a free OpenRouter key, your own Ollama, or any OpenAI-compatible endpoint. The in-browser model (Transformers.js) can also be switched on in the dashboard's settings. Ship tracking needs a free aisstream.io key. The description was kept.

## Base market templates

| Code | Name | Stats (2026-10-20) | Verdict |
|---|---|---|---|
| `world-monitor-self-hosted` | "World Monitor Self-Hosted" (`protemplate/worldmonitor`, branch `railway-stable`) | 3 projects, 0 active | **Structural base.** It runs the real self-hosted stack (app, relay, redis-rest, Redis, seeders, Caddy login gateway). Kept: that service split, the basic-auth gateway idea, Redis eviction policy, `UPSTASH_ALLOW_INSECURE_HTTP` on the relay. Fixed: see "Improvements". |
| `worldmonitor` | "worldmonitor" (`xiaosong233/worldmonitor-railway:latest`) | 3 projects, 3 active | Not used. A third-party `:latest` nginx image that forwards every API call to the hosted `api.worldmonitor.app`: no self-hosted data, no pinning, no healthcheck. |

Nothing was copied from either market template. The protemplate fork was read for ideas only; every file under `services/` was written for this template (see NOTICE.md).

## Pinned versions

| Component | Source | Version | Date | Checked |
|---|---|---|---|---|
| World Monitor app, API sidecar, relay, seed scripts | `koala73/worldmonitor` tag `v2.11.1` → commit `39e02521cda64be65c3bcf7ec313645a3d09445b`, fetched as the codeload tarball of that commit | 2.11.1 | 2026-10-19 | 2026-10-20 (`gh api`: latest release, tag → commit, `compare v2.11.1...main` = 0 ahead / 0 behind) |
| Redis REST proxy | `docker/redis-rest-proxy.mjs` at the same commit, raw.githubusercontent by commit + SHA-256 `ab30fffa…55edb` | 2.11.1 | 2026-10-19 | 2026-10-20 |
| Node base (all World Monitor images) | `node:24.21.0-alpine3.24@sha256:ebfe2f90…ec1c1` — the exact digest upstream pins in every v2.11.1 Dockerfile | 24.21.0 | 2026-09-18 | 2026-10-20 (Docker Hub, amd64 present) |
| node-redis (redis-rest) | npm `redis@4.7.1` (upstream installs `redis@4`; 4.7.1 is the current 4.x) | 4.7.1 | — | 2026-10-20 (npm `maintenance-v4`) |
| Gateway | `caddy:2.11.7-alpine` | 2.11.7 | 2026-10-03 release, image 2026-10-06 | 2026-10-20 |
| Redis | `redis:8.2.10` (Railway base uses `redis:8.2`; concrete patch tag here) | 8.2.10 | 2026-10-06 | 2026-10-20 |

Upstream publishes no image for the self-hosted stack. `ghcr.io/koala73/worldmonitor` (tags `2.11.0`, `2.11`, `latest`; no `2.11.1` yet) is built from `docker/Dockerfile`, the frontend-only image that proxies `/api` to the hosted `api.worldmonitor.app`. So the app, relay and proxy are built from the tagged source.

**Upgrade path.** Change `WM_SRC_VERSION` and `WM_SRC_COMMIT` in `services/worldmonitor/Dockerfile` and `services/worker/Dockerfile`, and `WM_SRC_COMMIT` + `REDIS_REST_SHA256` in `services/redis-rest/Dockerfile` (or set those names as service variables: Railway passes them as build args). Every patch asserts its anchor, so a moved anchor fails the build instead of shipping a half-patched image. Re-check `docker-compose.yml`, `SELF_HOSTING.md`, the seed tier lists against `scripts/seed-*.mjs` and `scripts/railway-services.json` for the new tag.

## Architecture

```
Internet --HTTPS--> gateway (Caddy, only public domain, :8080)
                     |- /gateway-health            -> 200 (gateway itself)
                     |- /api/mcp, /api/mcp/*        -> worldmonitor (no login; upstream requires X-WorldMonitor-Key)
                     '- everything else             -> basic-auth login -> worldmonitor
worldmonitor (nginx :8080 + Node API sidecar :46123 on loopback, supervisord)
   |- static dashboard (Vite build), /api/* -> sidecar (~50 handler families)
   |- -> redis-rest (Upstash REST protocol)  http://redis-rest.railway.internal:8079
   '- -> ais-relay (vessels, flights, Telegram, OREF, relay-backed market data)  http://ais-relay.railway.internal:3004
ais-relay (Node :3004) -> outbound AIS websocket (aisstream.io), RSS/Telegram/OREF polling,
                          ~30 in-process seed loops -> redis-rest; warm-pings + digest read -> worldmonitor
redis-rest (Node :8079, command allowlist) -> Redis (:6379, volume /data)
seed-live / seed-hourly / seed-4h / seed-daily / seed-bundles (Railway cron, exit when done)
   -> public data APIs -> redis-rest; some read worldmonitor and ais-relay
```

### Deviations from upstream `docker-compose.yml` (v2.11.1) and why

- **Seeders run as Railway cron services.** Upstream runs `./scripts/run-seeders.sh` on the host from cron every 30 minutes. Railway has no host, so five cron services run upstream's seed scripts in tiers that follow upstream's production cadences (`scripts/railway-services.json`, `docs/railway-seed-consolidation-runbook.md`). See "Seed schedule".
- **A login gateway in front.** Upstream binds the app to the host port and leaves access control to the operator. On a public URL, anonymous visitors could trigger LLM briefs and keyed data calls on the operator's keys, so the template adds Caddy with basic auth (bcrypt) and makes it the only public service.
- **`WORLDMONITOR_RELAY_KEY` is generated and shared** by worldmonitor, ais-relay and the seed services. Compose leaves it empty, which makes the relay's news-classify digest read and the warm-pings return 401 (upstream documents this in `SELF_HOSTING.md`).
- **`WORLDMONITOR_VALID_KEYS` and `WORLDMONITOR_SEED_REFRESH_KEY` are generated**, so the MCP server, the detailed `/api/health` and the resilience-ranking seeder work out of the box.
- **Real client IPs.** `WM_TRUSTED_PROXY_CIDRS` lists private ranges and the gateway sends one trusted `X-Forwarded-For`, so upstream's per-IP limits (for example 50 LLM country briefs per IP per UTC day) count real clients instead of one gateway address.
- **Redis**: Railway base service (`redis:8.2.10`, password, volume `/data`) plus upstream's `--maxmemory … --maxmemory-policy allkeys-lru`. The cap is a variable (default `512mb`, upstream `256mb`, because the template runs the whole seeder fleet on a schedule). Snapshots use `--save 300 1` instead of the base's `--save 60 1`: seeders write constantly and the data set is reproducible, so a fork every minute would cost CPU for little benefit.
- **Build context keeps `tests/fixtures/`.** Upstream's `.dockerignore` drops `tests/`, but since #9391 (2026-10-19) `src/e2e/country-qualified-signals-harness.ts` imports `tests/fixtures/qualified-country-signals`, and `tsconfig.json` type-checks all of `src/`. Upstream's own v2.11.1 Docker publish failed on exactly this (`TS2307` at `npx tsc`; that is why ghcr has no 2.11.1 image), and so did this template's first deploy test. Upstream CI type-checks a full checkout and passed on the tag commit. The worldmonitor source stage therefore keeps `tests/fixtures/` (5.7 MB, type-checked only, not a Vite entry, so the dashboard output is unchanged), drops the rest of `tests/`, and fails early with a clear message if `src/` imports any other pruned test file.
- **redis-rest memory limit**: compose sets `mem_limit: 512m`. Railway templates cannot set per-service limits; set one in the service settings if wanted.
- **Template patches** (below) for private-network relay access, dual-stack listeners, a redis-rest healthcheck and self-hosted warm-pings.

### Template patches to upstream code

All patches are small Node scripts in `services/*/patches/` that replace one exact snippet each, fail the build if a snippet is missing, ambiguous or already patched, and are followed by `node --check`. They were applied to copies of the v2.11.1 files and syntax-checked locally (see "Static verification").

| Patch | File (upstream) | Why |
|---|---|---|
| Trust the configured `WS_RELAY_URL` origin in Docker mode | `src-tauri/sidecar/local-api-server.mjs` | The sidecar's SSRF guard only trusts the configured Redis REST and LLM origins. A private relay URL (compose itself uses `http://ais-relay:3004`) is refused, so vessels, military flights, Telegram, OREF alerts, relay-backed market and aviation routes return nothing. The market template worked around this by giving the relay a **public** domain. The patch adds one `addConfiguredPrivateOrigin('WS_RELAY_URL', …)` call, the same mechanism upstream uses for Redis. The relay stays private and every relay route still needs `RELAY_SHARED_SECRET`. |
| Optional `listen [::]:8080` | `docker/nginx.conf` | Upstream nginx listens on IPv4 only. Rule 8.14: the gateway, relay and seeders call this service. The entrypoint writes the IPv6 listener only when the container has IPv6. |
| Warm-pings follow `API_BASE_URL` | `scripts/ais-relay.cjs` | The relay's four cache warm-pings (service statuses, CII risk scores, chokepoint status, cable health) are hard-coded to `https://api.worldmonitor.app` and carry `WORLDMONITOR_RELAY_KEY`. On a self-hosted stack that warms someone else's cache and sends our secret to a third party. Upstream already uses `API_BASE_URL` for the classify loop (#7437); the patch applies it to these four constants. Unset `API_BASE_URL` gives upstream's URLs. |
| Token-free `GET /healthz`, dual-stack listen | `docker/redis-rest-proxy.mjs` | Every upstream route needs the bearer token, so Railway's healthcheck had nothing to probe. `/healthz` returns 200 only while the Redis client is ready. The listener moves from `0.0.0.0` to `SRH_LISTEN_HOST` (`::` when IPv6 exists; Node's `::` socket is dual-stack). |

## Security model

- **One public domain: `gateway`.** worldmonitor, ais-relay, redis-rest and Redis have no public domain and no TCP proxy.
- **Login:** HTTP basic auth on everything except `/gateway-health` and `/api/mcp`. The password is generated (`secret(24)`, 56-character alphabet) and bcrypt-hashed inside the container at start; Caddy caches verified hashes, so a page load does not pay bcrypt per request. The gateway strips the `Authorization` header before proxying.
- **MCP** (`/api/mcp`) skips the login prompt because MCP clients cannot answer a basic-auth challenge. Upstream rejects any MCP request without a valid `X-WorldMonitor-Key` (checked against `WORLDMONITOR_VALID_KEYS`, timing-safe); OAuth needs the hosted identity service and fails closed here.
- **Admin routes:** upstream forces `LOCAL_API_MODE=docker` in its entrypoint; `/api/local-*` (configuration updates, secret validation, debug) returns 403 at nginx and in the sidecar. Configuration is changed only through Railway variables. The relay refuses to start without `RELAY_SHARED_SECRET`; redis-rest refuses requests without `SRH_TOKEN` and only forwards an allowlist of Redis commands.
- **How the dashboard authenticates its own `/api` calls** (upstream design, `api/_api-key.js`, `api/wm-session.js`, `src/services/wm-session.ts`): the browser holds **no API key**. On load it calls `POST /api/wm-session`, which mints a 12-hour anonymous `wms_` token signed with `WM_SESSION_SECRET` and sets it as an HttpOnly `wm-session` cookie; a fetch interceptor then sends the cookie (and the token as `X-WorldMonitor-Key`) on every same-origin `/api/` call. Public bootstrap tiers (`/api/bootstrap?tier=fast&public=1`, `…tier=slow&public=1`) need no credential at all. Origin, Referer and Sec-Fetch headers are deliberately not trusted (upstream #3541), so a bare `curl` of `/api/bootstrap` or `/api/news/v1/list-feed-digest` answers 401 `API key required`; that is expected and not a template fault. The gateway does **not** inject the operator key: `WORLDMONITOR_VALID_KEYS` is an enterprise credential that bypasses entitlement checks, lifts the anonymous 50-per-IP-per-day LLM cap to the operator ceiling (5,000 direct LLM calls a day) and puts every user into one per-key rate budget. The anonymous session is upstream's supported self-host path. Server-side requirements for it, all met here: `WM_SESSION_SECRET` (≥ 32 chars), Redis reachable for the session rate limiter (`failClosed`), `NODE_ENV` not `production` (nginx rewrites `Origin` to `http://localhost`), HTTPS for the `Secure` cookie (Railway's edge).
- **`WM_PUBLIC_DASHBOARD=true`** removes the login. Upstream's per-IP caps then still apply, but anyone with the URL can spend the configured keys' quotas.
- **Spending keys:** setting `OPENROUTER_API_KEY` (or another LLM) also turns on scheduled LLM seed jobs (insights hourly, forecasts every 4 h, forecast resolutions daily, regional briefs weekly) and the relay's news classification. Clear the reference on the seed services to keep LLM spend to interactive use.

## Services

10 services: 5 long-running, 5 cron. Railway limit is 25.

### gateway

| Setting | Value |
|---|---|
| Source | repo `/services/gateway` (`FROM caddy:2.11.7-alpine`, Caddyfile + entrypoint) |
| Public domain | **yes**, target port 8080 |
| Healthcheck | `/gateway-health`, 120 s |
| Restart | ON_FAILURE ×10 |
| Variables | `PORT=8080`, `WM_APP_UPSTREAM=${{worldmonitor.RAILWAY_PRIVATE_DOMAIN}}:${{worldmonitor.PORT}}`, `WM_UI_USERNAME=admin`, `WM_UI_PASSWORD=${{secret(24, …)}}`, `WM_PUBLIC_DASHBOARD=false` |

### worldmonitor

| Setting | Value |
|---|---|
| Source | repo `/services/worldmonitor`: 4-stage build of the v2.11.1 source (source → build → runtime deps → nginx + sidecar), same steps and order as upstream's root `Dockerfile` |
| Healthcheck | `/api/sidecar-health` (through nginx, so it proves nginx and the sidecar), 300 s |
| Restart | ALWAYS |
| Required (generated) | `WM_SESSION_SECRET` (64 hex), `WORLDMONITOR_VALID_KEYS` (`wm_` + 40 hex), `WORLDMONITOR_RELAY_KEY`, `WORLDMONITOR_SEED_REFRESH_KEY` |
| Wiring | `UPSTASH_REDIS_REST_URL=http://${{redis-rest.RAILWAY_PRIVATE_DOMAIN}}:${{redis-rest.PORT}}`, `UPSTASH_REDIS_REST_TOKEN=${{redis-rest.SRH_TOKEN}}`, `WS_RELAY_URL=http://${{ais-relay.RAILWAY_PRIVATE_DOMAIN}}:${{ais-relay.PORT}}`, `RELAY_SHARED_SECRET=${{ais-relay.RELAY_SHARED_SECRET}}`, `WM_TRUSTED_PROXY_CIDRS` (private ranges) |
| Other | `PORT=8080` (nginx port is hardcoded upstream), `VITE_VARIANT=full` (build arg: full, tech, finance, commodity, happy, energy) |
| Optional keys | all 19 keys in "Data sources and API keys", defined **here** and referenced by ais-relay and the seed services |

### ais-relay

| Setting | Value |
|---|---|
| Source | repo `/services/worker` (default CMD `node scripts/ais-relay.cjs`) |
| Healthcheck | `/health` (public relay route, always 200), 300 s; `PORT=3004`. The relay calls `server.listen(PORT)` without a host, so Node binds dual-stack. |
| Restart | ALWAYS. **One replica only** (Telegram session, AIS socket). |
| Variables | `RELAY_SHARED_SECRET` (generated), `UPSTASH_*`, `UPSTASH_ALLOW_INSECURE_HTTP=true`, `API_BASE_URL` = worldmonitor private URL, `WORLDMONITOR_RELAY_KEY` (ref), `MARKET_YAHOO_REFRESH_INTERVAL_MS=900000`, key refs (AIS, Finnhub, UCDP, OpenRouter, Ollama, OpenSky), optional `TELEGRAM_API_ID/HASH/SESSION` |

### redis-rest

| Setting | Value |
|---|---|
| Source | repo `/services/redis-rest` (upstream proxy by commit + SHA-256, node-redis 4.7.1, patched) |
| Healthcheck | `/healthz`, 600 s (waits for Redis); `PORT=8079` |
| Restart | ALWAYS |
| Variables | `SRH_TOKEN` (generated, 64 hex), `SRH_CONNECTION_STRING=${{Redis.REDIS_URL}}`. Optional `SRH_MAX_BODY_BYTES` (default 16 MB) can be added. |

### Redis

| Setting | Value |
|---|---|
| Source | image `redis:8.2.10` (Railway base definition) |
| Start | base start command + `--save 300 1 --maxmemory $REDIS_MAXMEMORY --maxmemory-policy allkeys-lru` |
| Volume | `/data` |
| Variables | base set (`REDIS_PASSWORD` generated, `REDIS_URL`, …) + `REDIS_MAXMEMORY=512mb` |

### Seed cron services (seed-live, seed-hourly, seed-4h, seed-daily, seed-bundles)

| Setting | Value |
|---|---|
| Source | repo `/services/worker` (same image as ais-relay) |
| Start | `/opt/railway/run-seeders.sh {tier}` |
| Restart | NEVER (cron jobs; a failed tick waits for the next one) |
| Healthcheck / domain | none |
| Variables | `UPSTASH_*`, `API_BASE_URL` and `WM_API_BASE_URL` (worldmonitor private URL), `WORLDMONITOR_RELAY_KEY`, all key refs; seed-live also `WS_RELAY_URL` + `RELAY_SHARED_SECRET` (military CII); seed-bundles also `WORLDMONITOR_VALID_KEYS` + `WORLDMONITOR_SEED_REFRESH_KEY` (resilience scores); optional `SEEDERS_EXTRA`, `SEEDERS_SKIP` |

## Seed schedule

`run-seeders.sh` waits up to 5 minutes for redis-rest (`/ping` with the token), runs the tier list with GNU `timeout` per seeder and a small parallel pool, prints one line per seeder (OK, FAIL with the last log line, TIMEOUT, SKIP, FRESH, DEFER) and exits 0 unless nothing succeeded. Extra variables: `SEEDERS` (replace list), `SEEDERS_EXTRA`, `SEEDERS_SKIP`, `SEED_TIMEOUT`, `SEED_PARALLEL`, `SEED_ROTATE`, `SEED_VERBOSE`, `SEED_MIN_INTERVAL`, `SEED_RETRY_INTERVAL`. Railway skips a tick while the previous run is still going, so a slow first run cannot pile up.

**Fast first fill.** seed-4h and seed-daily tick **hourly** and keep a per-seeder gate in Redis (`railway-template:seed-gate:v1:{name}`, set through redis-rest): after a success the seeder is skipped for 3 h 50 min (4h tier) or 23 h 50 min (daily tier), after a failure or timeout it is retried after 1 h or 6 h. Each seeder still runs at its own cadence, but a new install gets every tier's data in its first hour instead of waiting up to 4 hours or until 03:30 UTC. Losing a gate (Redis eviction, flush) only makes that seeder run one tick early. `SEED_MIN_INTERVAL=0` turns the gate off.

| Service | Cron (UTC) | Pool / cap | Seeders (`scripts/seed-{name}.mjs`) |
|---|---|---|---|
| seed-live | `*/10 * * * *` | 3 / 300 s | earthquakes, gdelt-bulk-materializer, conflict-intel, military-flights, military-cii, commodity-quotes, radiation-watch, imd-cyclone-marine, fire-detections, economy |
| seed-hourly | `5 * * * *` | 2 / 900 s | unrest-events, thermal-escalation, prediction-markets, research, security-advisories, regulatory-actions, cyber-threats, aviation, internet-outages, fred-rates, insights |
| seed-4h | `15 * * * *`, gated 3 h 50 min (retry 1 h) | 2 / 1500 s | supply-chain-trade, sanctions-pressure, forecasts, fx-rates, fx-yoy, fear-greed, hormuz, energy-intelligence, earnings-calendar, economic-calendar, webcams |
| seed-daily | `35 * * * *`, gated 23 h 50 min (retry 6 h) | 2 / 2400 s | aaii-sentiment, cot, market-breadth, trade-flows, comtrade-bilateral-hs4, hs2-chokepoint-exposure, energy-spine, electricity-prices, ember-electricity, fuel-prices, bigmac, grocery-basket, forecast-bets, forecast-resolutions, bundle-regional |
| seed-bundles | `*/15 * * * *` | 3 / 2400 s, start position rotates each tick (upstream runs every bundle as its own concurrent service) | bundle-derived-signals, -market-backup, -canada, -climate, -portwatch, -portwatch-port-activity, -relay-backup, -energy-sources, -health, -ecb-eu, -imf-extended, -macro, -yield-curves, -resilience, -resilience-energy-v2, -resilience-recovery, -static-ref, -static-ref-heavy |

Cadences follow the data's cache TTL in each script and upstream's production cron where it is recorded. Bundles check Redis freshness per section, so most bundle ticks only run what is due.

**Coverage.** All 219 `seed-*.mjs` files at v2.11.1 are accounted for: 46 standalone seeders and 19 bundles run in a tier, the bundles run 136 distinct member scripts (137 sections), `regional-briefs` runs inside `bundle-regional`, and these 17 are left out on purpose:

| Left out | Why |
|---|---|
| market-quotes, crypto-sectors, weather-alerts, chokepoint-flows | The relay seeds these in-process. |
| infra, military-maritime-news, service-statuses | Hard-coded warm-pings of the hosted `api.worldmonitor.app`; on self-host the sidecar computes these on request, and the relay warm-pings statuses (patched to this install). |
| gdelt-intel, iran-events, gta-update | Deprecated, retired or locked disabled upstream. |
| tps-open-data, recall-benchmark | On-demand worker / CI benchmark, not cron seeds. |
| digest-notifications, consumer-prices | Need Convex/Resend or the separate consumer-prices pipeline (hosted only). |
| live-video-resolved | Needs `PROXY_URL`; add with `SEEDERS_EXTRA=live-video-resolved` on seed-4h after setting it. |
| bundle-resilience-validation | Research tooling (benchmarks/backtests) that upstream runs with an 8 GB heap and a tsx loader. |
| yield-curves-shared | Library, not a seeder. |

Seeders whose key is not set fail fast or skip; the runner shows that as FAIL with the seeder's own last log line, which normally names the missing key.

## Health check expectations

`/api/health?compact=1` (behind the login) reports about 326 checks; the compact body lists each failing check under `problems` (and soft ones under `pending`) with its status. `_reports/round4/66-worldmonitor-health-map.tsv` maps the 309 registry checks in `api/health.js` to the template service that produces their data and the credential variables the producer reads:

| Category (309 registry checks) | Count | Expected status |
|---|---|---|
| On-demand (computed when a panel or API route asks) | 57 | `onDemandWarn`, never crit |
| Produced by a template service, no credential read (incl. 19 bundle checks with dynamic key names, and service statuses via the patched relay warm-ping) | 151 | crit only until the first tick that runs them, then OK |
| Produced by a template service whose script reads a credential | 89 | many fill without the key (keys are often optional fallbacks); the rest stay crit until the key is set (for example the FRED-only economic stress index, NASA FIRMS fires, Cloudflare outages, cross-strait via `PROXY_URL`) |
| Produced only by hosted upstream services | 12 | stay crit: consumer prices (6), company-monitoring worker, shipping-webhook worker, digest notifications, news recall benchmark, cross-strait history backfill, Canada alerts aggregate (its members are seeded) |

So right after a deploy most checks are crit because nothing has been seeded yet; that number should fall tick by tick. Wiring faults show up differently: a seeder that fails on every key-free run with an HTTP 401/403/5xx from `redis-rest` or from this install's API, or relay log lines such as `Redis disabled`, `SSRF blocked`, or warm-ping `HTTP 401`.

## Data sources and API keys

All keys are optional; set them on **worldmonitor**, then deploy the staged changes (the relay and seed services reference them).

| Area | Works without keys | Optional keys (free unless noted) |
|---|---|---|
| News | RSS digest of curated global and regional feeds | X / Twitter feed: `X_BEARER_TOKEN` (paid X API; add on ais-relay). Telegram OSINT: `TELEGRAM_API_ID`, `TELEGRAM_API_HASH`, `TELEGRAM_SESSION` (ais-relay) |
| Conflict and unrest | GDELT events and the Country Instability Index (GDELT terms since CII v10) | `ACLED_EMAIL` + `ACLED_PASSWORD` (free for researchers), `UCDP_ACCESS_TOKEN` |
| Ship tracking (AIS) | — | `AISSTREAM_API_KEY` (aisstream.io, free signup). Without it the vessel layer stays empty; all other relay feeds work. |
| Aircraft | Military aircraft from open ADS-B feeds (adsb.lol, airplanes.live, adsb.fi) | `OPENSKY_CLIENT_ID` + `OPENSKY_CLIENT_SECRET` (OpenSky has no anonymous fallback here), `AVIATIONSTACK_API` (free tier) |
| Markets | Yahoo quotes (relay), commodities, crypto, stablecoins, ETF flows, prediction markets, fear & greed, central-bank and Eurostat/IMF/BIS macro | `FINNHUB_API_KEY`, `ALPHA_VANTAGE_API_KEY`, `FRED_API_KEY`, `EIA_API_KEY` |
| Natural events | Earthquakes, weather alerts, NASA EONET/GDACS events, radiation, cyclone bulletins | `NASA_FIRMS_API_KEY` (wildfires / thermal hotspots) |
| Internet outages | — | `CLOUDFLARE_API_TOKEN` (Cloudflare Radar access) |
| AI (server-side) | — | `OPENROUTER_API_KEY` (free models available), or `OLLAMA_API_URL` + `OLLAMA_MODEL`, or `LLM_API_URL` + `LLM_API_KEY` + `LLM_MODEL` (any OpenAI-compatible endpoint) |
| AI (browser) | Transformers.js models, off by default; switch on in the dashboard settings | — |

Groq is no longer a provider in v2.11.1 (only tests mention `GROQ_API_KEY`), so the market template's `GROQ_API_KEY` variable was dropped.

## Improvements over market templates

1. **Pinned, verifiable source.** v2.11.1 by commit SHA (market self-hosted: a fork branch based on 2.10.0; `worldmonitor`: a third-party `:latest` image). Node base pinned to the same digest upstream uses.
2. **One public domain.** The market self-hosted template exposes the relay publicly because of the SSRF guard; here a 1-line, build-checked patch lets the API reach the relay privately.
3. **Relay key wired.** `WORLDMONITOR_RELAY_KEY` generated and shared, so news classification and warm-pings stop returning 401 (unset in the market template).
4. **No secret sent to a third party.** Relay warm-pings go to this install instead of `api.worldmonitor.app`.
5. **Seeders as Railway cron services** on upstream's production cadences: 46 standalone seeders and 19 freshness-gated bundles (137 sections), instead of one long-running loop that runs a fixed keyless subset every 30 minutes.
6. **Healthchecks everywhere a service listens:** gateway, app (nginx + sidecar), relay and redis-rest (new `/healthz`). PORT set on each (Rule 8.1).
7. **Dual-stack listeners** for the app (nginx) and redis-rest (Rule 8.14); relay already dual-stack.
8. **First fill within the hour.** The 4-hour and daily tiers tick hourly behind Redis gates and bundles run three at a time, so a new install does not wait until 03:30 UTC for daily data.
9. **Real client IPs** reach upstream's per-IP limits through trusted proxy ranges (market: every visitor shares the gateway's IP and one LLM budget).
10. **MCP usable** behind the login: `/api/mcp` bypasses basic auth and relies on upstream's key check.
11. **Current LLM options:** OpenRouter, Ollama and generic OpenAI-compatible, matching v2.11.1 (`GROQ_API_KEY` removed).
12. **Resilience scores work:** operator and seed-refresh keys reach the resilience seeder.
13. **Restart policy ALWAYS** on services that depend on others (Rule 8.5), no `restartPolicyMaxRetries` with ALWAYS.
14. **Site variant selectable** at build time (`VITE_VARIANT`).

## Scaling

- **worldmonitor**: stateless (state in Redis), so `numReplicas` can be raised; per-IP limits are counted in Redis.
- **ais-relay**: keep **one** replica (one AIS websocket, one Telegram session). Scale vertically; it is the heaviest service with an AIS key. `RELAY_RATE_LIMIT_MAX` (default 1200 per window per caller IP) can be raised if many users share the app.
- **Seeds**: raise `SEED_PARALLEL` on a tier, or move names between tiers with `SEEDERS_EXTRA` / `SEEDERS_SKIP`. Above about 3 parallel seeders some public APIs start rate limiting.
- **Redis**: raise `REDIS_MAXMEMORY` and the service memory together.

## Resource estimate

Prices: RAM $10/GB-month, vCPU $20/vCPU-month, volume $0.15/GB-month. Cron services are billed only while a tick runs. **Not measured** (no container was run); based on upstream's own numbers (Railway seed services at 1 vCPU / 1 GB, redis-rest bounded at 512 MB, Redis 256 MB) and typical Node footprints.

| Service | Idle RAM | Typical RAM | Idle vCPU | Typical vCPU | Volume |
|---|---|---|---|---|---|
| gateway | 25 MB | 40 MB | 0.005 | 0.02 | — |
| worldmonitor (nginx + sidecar) | 250 MB | 500 MB | 0.02 | 0.15 | — |
| ais-relay | 300 MB | 600 MB (AIS key set) | 0.05 | 0.3 | — |
| redis-rest | 70 MB | 150 MB | 0.01 | 0.05 | — |
| Redis | 150 MB | 400 MB | 0.01 | 0.03 | ~1 GB |
| seed-live (time-averaged) | 150 MB | 250 MB | 0.05 | 0.1 | — |
| seed-bundles (time-averaged) | 60 MB | 100 MB | 0.02 | 0.05 | — |
| seed-hourly, seed-4h, seed-daily (time-averaged) | 45 MB | 80 MB | 0.015 | 0.035 | — |
| **Total** | **≈ 1.05 GB** | **≈ 2.1 GB** | **≈ 0.18** | **≈ 0.74** | **≈ 1 GB** |

- **Idle** (no viewers; seeders and relay still run): 1.05 × $10 + 0.18 × $20 + $0.15 ≈ **$14/month**.
- **Typical** (a team using it daily, AIS and an LLM key set): 2.1 × $10 + 0.74 × $20 + $0.15 ≈ **$36/month**, plus egress (dashboard loads are several MB each).
- LLM and data-provider usage is billed by those providers.
- **Minimum plan: Hobby.** Each service fits Trial's 1 GB, but Trial credit would not cover a month, and the app image build is heavy. Pro for many concurrent users.

## Static verification (2026-10-20, no Docker)

- Upstream copy in `_upstream/koala73__worldmonitor` matches tag v2.11.1 (git blob SHAs of Dockerfile, Dockerfile.relay, docker-compose.yml, docker/entrypoint.sh, docker/nginx.conf, sidecar, ais-relay.cjs, run-seeders.sh, redis-rest-proxy.mjs, package-lock.json compared with `gh api …?ref=v2.11.1`).
- Build fix after deploy test 1: confirmed the root cause in upstream's own failed v2.11.1 Docker publish log (same `TS2307`) and in `tsconfig.json` (`include: ["src", …]`); `src/` has exactly one import into `tests/`; the source-stage prune and import check were run with dash on a simulated tree (keeps `tests/fixtures`, removes the rest, fails when the fixture is missing) and against the real v2.11.1 `src/` (no missing imports).
- All four patch scripts applied to copies of the v2.11.1 files; diffs reviewed; `node --check` passes on every patched file; a second run fails with "already patched".
- `sh -n` and `dash -n` on all four shell scripts.
- `run-seeders.sh` exercised with dash against fake seed scripts and a fake redis-rest: OK / FAIL / TIMEOUT / SKIP classification, de-duplication, `SEEDERS`, `SEEDERS_SKIP`, parallel pool, verbose mode, exit 1 when nothing works, giving up when `/ping` fails, rejecting a non-numeric `SEED_TIMEOUT`, rotation arithmetic.
- Seed gates (after deploy test 2): `run-seeders.sh` run with dash against a fake redis-rest that implements `GET` and `SET … EX`: first tick runs and stores `ok:`/`fail:` gates with the tier TTLs (13800/3600 s for 4h, 85800/21600 s for daily), the next tick reports FRESH/DEFER and runs nothing, `SEED_MIN_INTERVAL=0` disables the gate, a non-numeric value is rejected, the live tier has no gate.
- Browser auth path read in v2.11.1 source: `api/_api-key.js` (session, enterprise and user-key kinds), `api/wm-session.js` (mint, cookie, `failClosed` rate limit), `api/bootstrap.js` + `api/_bootstrap-public-tier.js` (credential-free public tiers), `src/services/wm-session.ts` (interceptor matches relative `/api/` paths), `api/_cors.js` (`http://localhost` allowed unless `NODE_ENV=production`), `server/gateway.ts` (enterprise keys skip entitlements, one budget per key).
- Health checks: the 309 registry checks in `api/health.js` mapped to producers (`_reports/round4/66-worldmonitor-health-map.tsv`); the 57 on-demand checks match the `onDemandWarn` count of deploy test 2.
- Gateway entrypoint exercised with a mock `caddy`: login file, public mode, short password, invalid user name, missing upstream.
- Every tier name exists as `scripts/seed-{name}.mjs` at v2.11.1; each of the 219 seed scripts is in a tier, a bundle, or the "left out" table.
- Static import walk of all seed scripts: bare packages are all in `scripts/package.json`; no `.ts` file is reached statically.
- Caddy options checked against Caddy v2.11.7 source (`trusted_proxies_strict`, `client_ip_headers`, basic_auth hash cache, `hash-password` reading stdin).
- `template.json` parses; all 163 `${{service.VAR}}` references resolve to a defined variable or a Railway-provided one; every variable has a description; every healthchecked service defines `PORT`.
- Image tags exist (registry APIs): `node:24.21.0-alpine3.24` (digest matches upstream's pin), `caddy:2.11.7-alpine`, `redis:8.2.10`; source URLs (codeload tarball by commit, raw proxy file by commit, SHA-256 match) answer 200.

## Verification checklist (first deploy)

1. Builds: worldmonitor (longest, full Vite + tsc + pro build), worker (twice: ais-relay and 5 crons), redis-rest, gateway all succeed on `linux/amd64`.
2. Health: gateway `/gateway-health` 200; worldmonitor `/api/sidecar-health` 200; ais-relay `/health` 200; redis-rest `/healthz` 200.
3. Logs: worldmonitor shows `[patch]` lines in the build and `nginx: listening on 0.0.0.0:8080 and [::]:8080` at start; ais-relay shows `WORLDMONITOR_RELAY_KEY configured` and no `Redis disabled` warning; redis-rest shows `listening on :::8079`.
4. Login: open `https://{your-domain}` → browser login prompt → `admin` / `WM_UI_PASSWORD` from the gateway variables → dashboard loads. A wrong password gets 401.
5. Data as the browser gets it (anonymous session, no key):
   - `curl -su admin:{password} "https://{your-domain}/api/bootstrap?tier=fast&public=1"` → 200 with data (public tier, no session needed).
   - `curl -su admin:{password} -c jar -X POST -H 'Content-Type: application/json' -d '{}' https://{your-domain}/api/wm-session` → 200 `{"ok":true,"token":"wms_…"}` and a `wm-session` cookie.
   - `curl -su admin:{password} -b jar "https://{your-domain}/api/news/v1/list-feed-digest?variant=full&lang=en"` → 200.
   - Without the cookie the last call is 401 `API key required`, by upstream design.
   - In a browser, DevTools shows `POST /api/wm-session` 200 followed by 200s on `/api/*`.
6. Health: `curl -su admin:{password} "https://{your-domain}/api/health?compact=1" | jq -r '.problems | to_entries[] | "\(.key)\t\(.value.status)"'` lists failing checks; join them with the health map (see "Health check expectations"). The crit count falls over the first one to two hours; the detailed report needs `-H "X-WorldMonitor-Key: {WORLDMONITOR_VALID_KEYS}"` on `/api/health`.
7. Relay path (the patch): `/api/health` or the sidecar log shows no `SSRF blocked … ais-relay` lines; with `AISSTREAM_API_KEY` set on worldmonitor and ais-relay redeployed, vessels appear.
8. Warm-pings: ais-relay log shows `[CII] Warm-ping` / `[ServiceStatuses] Seed ping OK` against this install, and the `[Classify]` digest read is not a 401.
9. Cron: each seed service shows a `done in …: ok=…` summary; seed-bundles rotates its start position.
10. MCP: `POST https://{your-domain}/api/mcp` with `X-WorldMonitor-Key: {WORLDMONITOR_VALID_KEYS}` and a `tools/list` body works without basic auth; without the key it is refused.
11. Persistence: redeploy Redis; data survives (volume `/data`).
12. Real IP: worldmonitor nginx access log shows client IPs, not the gateway's private address.

## Open questions

- **Nothing has run yet.** The real test is the first Railway deploy: the app image build (memory and time on Railway's builder; `NODE_OPTIONS=--max-old-space-size=4096` is set for it), the codeload `ADD`, and all runtime paths.
- **Relay origin patch** is reasoned from source (the SSRF guard and the allowlist call); the end-to-end result on Railway is unverified.
- **Private IPv4:** the sidecar forces IPv4 for its trusted private origins (upstream code). New Railway environments resolve private names to IPv4 as well; a legacy IPv6-only environment would break Redis and relay calls from the sidecar.
- **Railway edge source address:** trusting `private_ranges` + `100.64.0.0/10` assumes the edge reaches the gateway from private space. If it does not, every client shares the edge IP for per-IP limits (fails toward stricter limits, not open).
- **Seeder behaviour without keys** was read from source, not run; some may exit non-zero every tick and show as FAIL (expected, harmless).
- **Upstream's comment that "Railway kills cron containers at 10 minutes"** (in `_bundle-runner.mjs`) contradicts Railway's docs (the next tick is skipped, the running one is not terminated). If a 10-minute limit applies, long first runs of seed-bundles and seed-daily would be cut and finish over several ticks (bundles keep completed sections; the rotation spreads the rest).
- **Pruned folders in the worker image** (docs, public, src-tauri, cli, sdk, tests, …): a static search found no runtime reads; a seeder that did read one would fail on its own without affecting others.
- **Redis size** under the full seeder fleet is unknown; watch `evicted_keys`.
- **seed-bundles memory** with 3 bundles in parallel (each spawns Node child processes per section) is unmeasured; a 0.6–0.9 GB peak is plausible. Set `SEED_PARALLEL=1` on seed-bundles if it is tight.
- **Alpine DNS:** the market template set `ENABLE_ALPINE_PRIVATE_NETWORKING=true` on its Alpine services. It is a legacy flag for musl resolvers on IPv6-only private networks and is not set here; if `*.railway.internal` names fail to resolve in the Node services, set it to `true` on them.
