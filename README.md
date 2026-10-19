# Deploy and Host World Monitor with Railway

World Monitor is an open-source global intelligence dashboard: live news, conflict and protest signals, markets, ships, aircraft, natural events and infrastructure on one interactive map. This community template runs the complete self-hosted stack from release v2.11.1 behind a login, with scheduled data jobs and no required API keys.

## About Hosting World Monitor

Self-hosting World Monitor means more than serving the web app. The dashboard reads from your own Redis, which three kinds of processes keep filled: the API sidecar inside the app container, the AIS relay (vessel stream, feed relays and about thirty background loops) and upstream's seed scripts. This template builds the app, relay and Redis REST proxy from the tagged upstream source, runs the seed scripts as five Railway cron jobs on upstream's own cadences, and puts a password-protected gateway in front as the only public endpoint. Secrets are generated at deploy and every internal call stays on Railway's private network.

## Common Use Cases

- A private situation room for analyst, risk, newsroom or security teams
- Monitoring conflicts, shipping chokepoints, energy and markets for a region or supply chain
- A keyless public-data dashboard for earthquakes, weather alerts, crypto and prediction markets
- A data source for AI agents through the built-in MCP server at `/api/mcp`

## Dependencies for World Monitor Hosting

- Redis with a persistent volume (included), reached through upstream's Upstash-compatible REST proxy (included)
- No API key is required. Optional free keys add layers: aisstream.io (ships), NASA FIRMS (wildfires), FRED and EIA (macro and energy), Finnhub and Alpha Vantage (equities), ACLED (conflict events), OpenSky and AviationStack (aircraft), Cloudflare Radar (outages)
- AI briefs, summaries and news threat labels need an LLM: an OpenRouter key (free models exist), your own Ollama, or any OpenAI-compatible endpoint. A browser-side model can also be switched on in the dashboard settings.

### Deployment Dependencies

- [World Monitor on GitHub](https://github.com/koala73/worldmonitor) (AGPL-3.0)
- [Release v2.11.1](https://github.com/koala73/worldmonitor/releases/tag/v2.11.1)
- [Upstream self-hosting guide](https://github.com/koala73/worldmonitor/blob/v2.11.1/SELF_HOSTING.md)
- [aisstream.io](https://aisstream.io) for the free ship-tracking key
- [OpenRouter](https://openrouter.ai) or [Ollama](https://ollama.com) for AI features

### Implementation Details

| Service | What it does | Public |
|---|---|---|
| gateway | Caddy with a basic-auth login; the only public domain | yes |
| worldmonitor | nginx serving the dashboard plus the Node API sidecar (built from v2.11.1) | no |
| ais-relay | AIS vessel stream, RSS, Telegram and alert relays, in-process seed loops | no |
| redis-rest | Upstash-compatible REST proxy with a command allowlist | no |
| Redis | Data store with a volume at `/data` | no |
| seed-live, seed-hourly, seed-4h, seed-daily, seed-bundles | Cron jobs that run upstream's seed scripts every 10 min, hourly, every 4 h, daily and every 15 min | no |

**First login**

1. Wait for all builds. The worldmonitor image compiles the whole dashboard and takes the longest.
2. Open the gateway variables and copy `WM_UI_PASSWORD`. The user name is `admin` (`WM_UI_USERNAME`).
3. Open `https://{your-domain}` and sign in. Panels fill as the first cron ticks finish; the 15-minute bundles take a few ticks to cover everything on a new install.
4. Optional: add keys on the **worldmonitor** service (for example `AISSTREAM_API_KEY`, `OPENROUTER_API_KEY`) and deploy the staged changes. The relay and seed services reference those variables.

**MCP for agents:** send `X-WorldMonitor-Key: {WORLDMONITOR_VALID_KEYS}` to `https://{your-domain}/api/mcp`. This path skips the login prompt because World Monitor itself rejects MCP calls without a valid key.

**Costs to know about:** setting an LLM key also enables scheduled LLM jobs (insights hourly, forecasts every 4 hours, weekly regional briefs). Remove the key reference on the seed services if you want AI only on demand. `WM_PUBLIC_DASHBOARD=true` on the gateway removes the login; anyone with the URL could then use your keys' quotas.

**Scaling:** worldmonitor is stateless and can run several replicas. Keep ais-relay at one replica (one AIS socket and Telegram session) and give it more memory if you track ships. Seed jobs scale with `SEED_PARALLEL`, and `SEEDERS_EXTRA` / `SEEDERS_SKIP` move seed scripts between schedules.

**Versions:** the source is pinned to v2.11.1 by commit (`WM_SRC_VERSION` / `WM_SRC_COMMIT` build args), with Caddy 2.11.7, Redis 8.2.10 and Node 24.21.0. To upgrade, change those build args and redeploy; the template's small patches check their anchors and stop the build if upstream moved them.

### Why Deploy World Monitor on Railway?

Railway runs the whole World Monitor stack, including its cron jobs, persistent Redis and private networking, from one template with no server to maintain. You get HTTPS, logs and per-service scaling, and you pay for the resources the dashboard and its data jobs actually use.

This is a community template. It is not made, endorsed or supported by the World Monitor authors.
