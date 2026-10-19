# World Monitor Redis REST proxy for Railway (community template).
#
# World Monitor talks to Redis only through the Upstash REST protocol. This is
# upstream's hardened proxy (command allowlist, byte-pinned EVAL scripts, body
# limit) from docker/redis-rest-proxy.mjs at the pinned release, fetched by
# commit and checked by SHA-256, with node-redis 4 as in upstream's
# docker/Dockerfile.redis-rest (pinned here to 4.7.1, the current 4.x).
#
# Template changes (patches/patch-redis-rest.mjs): token-free GET /healthz for
# Railway's healthcheck, and a dual-stack listen address.
#
# Upgrade: change WM_SRC_COMMIT and REDIS_REST_SHA256 together.
FROM node:24.21.0-alpine3.24@sha256:ebfe2f90462722a7a4de65e91990e97fe0d401c70e0e762c5b53302f905ec1c1

ARG WM_SRC_COMMIT=39e02521cda64be65c3bcf7ec313645a3d09445b
ARG REDIS_REST_SHA256=ab30fffa01a49c8f6712929a0da85f51ba9887008fa89a3be0ae301d52c55edb

WORKDIR /app
RUN npm init -y >/dev/null && \
    npm install --no-audit --no-fund --omit=dev redis@4.7.1 && \
    npm cache clean --force

ADD https://raw.githubusercontent.com/koala73/worldmonitor/${WM_SRC_COMMIT}/docker/redis-rest-proxy.mjs /app/redis-rest-proxy.mjs
RUN echo "${REDIS_REST_SHA256}  /app/redis-rest-proxy.mjs" | sha256sum -c -

COPY patches/ /opt/railway/patches/
COPY start.sh /opt/railway/start.sh
RUN node /opt/railway/patches/patch-redis-rest.mjs /app/redis-rest-proxy.mjs && \
    node --check /app/redis-rest-proxy.mjs && \
    chmod 0644 /app/redis-rest-proxy.mjs && \
    chmod 0755 /opt/railway/start.sh && \
    sh -n /opt/railway/start.sh

USER node
ENV PORT=8079
EXPOSE 8079

CMD ["/opt/railway/start.sh"]
