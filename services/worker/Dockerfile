# World Monitor worker image for Railway (community template).
#
# One image, two roles:
#   * ais-relay   - upstream's scripts/ais-relay.cjs (default CMD): AIS vessel
#                   stream, RSS/Telegram/OREF relays and the in-process seed loops
#   * seed-* crons - /opt/railway/run-seeders.sh <tier>: upstream's seed scripts
#                   on a schedule (upstream self-hosting runs them from host cron)
#
# Upstream's Dockerfile.relay copies a hand-picked file list; its seeder images
# ship the whole scripts/ tree because cherry-picking kept breaking imports.
# This image ships the pinned source tree (minus docs, tests, desktop and web
# build inputs) with the scripts/ runtime dependencies, so relay and seeders
# resolve every import the same way upstream's repo-root Railway services do.
#
# Template change on top of upstream (patches/patch-relay.mjs): the relay's
# cache warm-pings follow API_BASE_URL instead of the hosted API.
#
# Upgrade: change WM_SRC_VERSION and WM_SRC_COMMIT, then rebuild.

FROM node:24.21.0-alpine3.24@sha256:ebfe2f90462722a7a4de65e91990e97fe0d401c70e0e762c5b53302f905ec1c1 AS source
ARG WM_SRC_VERSION=2.11.1
ARG WM_SRC_COMMIT=39e02521cda64be65c3bcf7ec313645a3d09445b
ADD https://codeload.github.com/koala73/worldmonitor/tar.gz/${WM_SRC_COMMIT} /tmp/worldmonitor.tar.gz
# Extract and check the version, generate the inventory facts the relay loads
# at startup (Node builtins only; it scans the whole tree, so it runs before
# pruning, like upstream's relay image), then drop what neither the relay nor
# the seeders read.
RUN set -eux; \
    mkdir -p /tmp/extract; \
    tar -xzf /tmp/worldmonitor.tar.gz -C /tmp/extract; \
    mv /tmp/extract/worldmonitor-* /src; \
    rm -rf /tmp/extract /tmp/worldmonitor.tar.gz; \
    grep -q "\"version\": \"${WM_SRC_VERSION}\"" /src/package.json; \
    cd /src; \
    node scripts/generate-inventory-facts.mjs; \
    test -s scripts/shared/inventory-facts.generated.json; \
    rm -rf .git .github .agents .audit .husky blog-site docs e2e tests demos \
           pro-test src-tauri public cli sdk; \
    find . -maxdepth 1 \( -name '.env*' -o -name '*.log' -o -name '*.key' -o -name '*.pem' \) -exec rm -rf {} +

FROM node:24.21.0-alpine3.24@sha256:ebfe2f90462722a7a4de65e91990e97fe0d401c70e0e762c5b53302f905ec1c1

# curl: OREF polling in the relay (upstream installs it too).
# coreutils/findutils: GNU timeout and xargs -P for the seed runner.
RUN apk add --no-cache curl coreutils findutils

WORKDIR /app
COPY --from=source --chown=node:node /src/ /app/

# Railway template files (root-owned, read-only for the app user)
COPY patches/ /opt/railway/patches/
COPY tiers/ /opt/railway/tiers/
COPY run-seeders.sh /opt/railway/run-seeders.sh
RUN node /opt/railway/patches/patch-relay.mjs /app/scripts/ais-relay.cjs && \
    node --check /app/scripts/ais-relay.cjs && \
    chmod 0755 /opt/railway/run-seeders.sh && \
    sh -n /opt/railway/run-seeders.sh

USER node
# scripts/ runtime dependencies, installed the way upstream's relay image does
# (no install scripts, no optional native helpers; tsx is a regular dependency).
RUN npm ci --prefix scripts --omit=dev --omit=optional --ignore-scripts && \
    npm cache clean --force

# Upstream's Railway seeder setting: some data providers have broken IPv6.
ENV NODE_OPTIONS=--dns-result-order=ipv4first

EXPOSE 3004

CMD ["node", "scripts/ais-relay.cjs"]
