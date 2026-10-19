# World Monitor app for Railway (community template).
#
# Builds the full self-hosted image (nginx serving the Vite dashboard + the Node
# API sidecar under supervisord) from the pinned upstream release, following the
# build steps of upstream's root Dockerfile at the same tag. Upstream publishes
# no image for this stack: ghcr.io/koala73/worldmonitor is the frontend-only
# image that proxies every API call to the hosted api.worldmonitor.app.
#
# Template changes on top of upstream (see patches/patch-app.mjs):
#   * the API sidecar trusts the configured private WS_RELAY_URL origin
#   * nginx also listens on [::]:8080 when the container has IPv6
#
# Upgrade: set WM_SRC_VERSION and WM_SRC_COMMIT to a newer release tag and the
# commit it points to, then re-check the patch anchors (the build fails loudly
# if one moved).

# ── Stage 1: pinned upstream source ─────────────────────────────────────────
FROM node:24.21.0-alpine3.24@sha256:ebfe2f90462722a7a4de65e91990e97fe0d401c70e0e762c5b53302f905ec1c1 AS source
ARG WM_SRC_VERSION=2.11.1
ARG WM_SRC_COMMIT=39e02521cda64be65c3bcf7ec313645a3d09445b
ADD https://codeload.github.com/koala73/worldmonitor/tar.gz/${WM_SRC_COMMIT} /tmp/worldmonitor.tar.gz
# Extract, check the version, then mirror upstream's .dockerignore so the build
# sees the same tree as upstream's own `docker build .` (root-level patterns
# only, as Docker applies them).
#
# One deliberate difference: tests/fixtures/ is kept. tsconfig.json type-checks
# all of src/, and since upstream #9391 (2026-10-19) src/e2e/
# country-qualified-signals-harness.ts imports
# ../../tests/fixtures/qualified-country-signals. Upstream's .dockerignore drops
# tests/, so `npx tsc` fails with TS2307 in upstream's own v2.11.1 image build
# (the Docker publish run for v2.11.1 failed with that error). Upstream CI
# type-checks a full checkout, where the fixture exists. The fixture is
# type-checked only; it is not part of any Vite entry, so the dashboard output
# is unchanged. The check below fails early if src/ imports a tests/ file that
# is not kept.
RUN set -eux; \
    mkdir -p /tmp/extract; \
    tar -xzf /tmp/worldmonitor.tar.gz -C /tmp/extract; \
    mv /tmp/extract/worldmonitor-* /src; \
    rm -rf /tmp/extract /tmp/worldmonitor.tar.gz; \
    grep -q "\"version\": \"${WM_SRC_VERSION}\"" /src/package.json; \
    cd /src; \
    rm -rf .git .windsurf .agent .agents .claude .factory .planning e2e \
           docs/internal docs/Docs_To_Review dist node_modules secrets \
           src-tauri/target src-tauri/sidecar/node; \
    if [ -d tests ]; then find tests -mindepth 1 -maxdepth 1 ! -name fixtures -exec rm -rf {} +; fi; \
    missing=$(grep -rhoE "['\"](\.\./)+tests/[^'\"]+['\"]" src \
      | sed -E "s/^['\"](\.\.\/)+//; s/['\"]\$//" | sort -u \
      | while read -r p; do \
          [ -e "$p" ] || [ -e "$p.ts" ] || [ -e "$p.js" ] || [ -e "$p.mjs" ] || [ -e "$p.json" ] || echo "$p"; \
        done); \
    if [ -n "$missing" ]; then echo "src/ imports test files that were pruned: $missing" >&2; exit 1; fi; \
    rm -f .npmrc docker-compose.override.yml; \
    find . -maxdepth 1 -type f -name '*.md' ! -name README.md ! -name CHANGELOG.md -exec rm -f {} +; \
    find . -maxdepth 1 \( -name '.env*' -o -name '*.log' -o -name '*.key' -o -name '*.pem' \) -exec rm -rf {} +; \
    if [ -d .github ]; then \
      find .github -mindepth 1 -maxdepth 1 ! -name workflows -exec rm -rf {} +; \
      if [ -d .github/workflows ]; then \
        find .github/workflows -mindepth 1 ! -name '*.yml' ! -name '*.yaml' -exec rm -rf {} +; \
      fi; \
    fi

# ── Stage 2: build (same steps and order as upstream's root Dockerfile) ─────
FROM node:24.21.0-alpine3.24@sha256:ebfe2f90462722a7a4de65e91990e97fe0d401c70e0e762c5b53302f905ec1c1 AS builder
WORKDIR /app
ENV npm_config_install_links=true
# Same heap ceiling the upstream GitHub Actions build gets by default.
ENV NODE_OPTIONS=--max-old-space-size=4096
# Site variant baked into the dashboard: full, tech, finance, commodity, happy, energy.
ARG VITE_VARIANT=full
ENV VITE_VARIANT=${VITE_VARIANT}
COPY --from=source /src/ ./
RUN npm ci --ignore-scripts
# Attribution drift gate runs on the pristine tree, before generated files appear.
RUN npm run build:crawlable-corpus && npm run build:sitemap
RUN node scripts/generate-inventory-facts.mjs
RUN node docker/build-handlers.mjs
RUN npm run build:pro
RUN npx tsc && npx vite build
RUN test -s dist/pro/index.html && test -s dist/pro/welcome.html

# ── Stage 3: runtime npm deps for the raw (unbundled) API handlers ──────────
FROM node:24.21.0-alpine3.24@sha256:ebfe2f90462722a7a4de65e91990e97fe0d401c70e0e762c5b53302f905ec1c1 AS runtime-deps
WORKDIR /app
COPY --from=source /src/docker/runtime-package.json ./package.json
COPY --from=source /src/docker/runtime-package-lock.json ./package-lock.json
RUN npm ci --omit=dev --omit=optional --ignore-scripts

# ── Stage 4: runtime (nginx + API sidecar under supervisord) ────────────────
FROM node:24.21.0-alpine3.24@sha256:ebfe2f90462722a7a4de65e91990e97fe0d401c70e0e762c5b53302f905ec1c1 AS final

RUN apk add --no-cache nginx supervisor gettext && \
    mkdir -p /tmp/nginx-client-body /tmp/nginx-proxy /tmp/nginx-fastcgi \
             /tmp/nginx-uwsgi /tmp/nginx-scgi /var/log/supervisor && \
    addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# API sidecar and its runtime inputs (paths as in upstream's image)
COPY --from=builder /app/src-tauri/sidecar/local-api-server.mjs ./local-api-server.mjs
COPY --from=builder /app/src-tauri/sidecar/package.json ./package.json
COPY --from=builder /app/shared/llm-health-providers.js ./shared/llm-health-providers.js
ENV LOCAL_API_RESOURCE_DIR=/app
COPY --from=runtime-deps /app/node_modules ./node_modules
COPY --from=builder /app/api ./api
COPY --from=builder /app/data ./data

# Dashboard static files
COPY --from=builder /app/dist /usr/share/nginx/html

# Upstream nginx, supervisord and entrypoint files
COPY --from=builder /app/docker/nginx.conf /etc/nginx/nginx.conf.template
COPY --from=builder /app/docker/supervisord.conf /etc/supervisor/conf.d/worldmonitor.conf
COPY --from=builder /app/docker/entrypoint.sh /app/entrypoint.sh
COPY --from=builder /app/docker/render-nginx-realip.mjs /app/render-nginx-realip.mjs
COPY --from=builder /app/docker/validate-session-secret.mjs /app/validate-session-secret.mjs

# Railway template files
COPY patches/ /opt/railway/patches/
COPY railway-entrypoint.sh /opt/railway/entrypoint.sh
RUN node /opt/railway/patches/patch-app.mjs /app/local-api-server.mjs /etc/nginx/nginx.conf.template && \
    node --check /app/local-api-server.mjs && \
    chmod 0755 /app/entrypoint.sh /opt/railway/entrypoint.sh && \
    chown -R appuser:appgroup /app /tmp/nginx-client-body /tmp/nginx-proxy \
      /tmp/nginx-fastcgi /tmp/nginx-uwsgi /tmp/nginx-scgi /var/log/supervisor \
      /var/lib/nginx /var/log/nginx

USER appuser

# nginx port (hardcoded upstream). Railway health-checks PORT, so PORT=8080.
EXPOSE 8080

CMD ["/opt/railway/entrypoint.sh"]
