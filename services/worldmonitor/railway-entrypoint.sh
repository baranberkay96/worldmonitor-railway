#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
#
# Railway start wrapper for the World Monitor app image. It checks the
# required variables, writes the optional IPv6 nginx listener, then hands over
# to upstream's own entrypoint (secret bridge, session-secret check, docker
# mode, real-IP rendering, nginx + Node API sidecar under supervisord).
set -eu

log() { printf '[railway-entrypoint] %s\n' "$*"; }
fail() { log "ERROR: $*" >&2; exit 1; }

[ -n "${UPSTASH_REDIS_REST_URL:-}" ] || fail "UPSTASH_REDIS_REST_URL is not set (private URL of the redis-rest service)"
[ -n "${UPSTASH_REDIS_REST_TOKEN:-}" ] || fail "UPSTASH_REDIS_REST_TOKEN is not set (redis-rest SRH_TOKEN)"
[ -n "${RELAY_SHARED_SECRET:-}" ] || fail "RELAY_SHARED_SECRET is not set (reference ais-relay.RELAY_SHARED_SECRET)"
case "${WS_RELAY_URL:-}" in
  http://*|https://*) ;;
  '') log "WS_RELAY_URL is not set: vessels, flights and relay feeds stay empty" ;;
  *) fail "WS_RELAY_URL must start with http:// or https:// (got a different scheme)" ;;
esac

# nginx listens on IPv4 (upstream) and, when the container has IPv6, also on
# [::] so private-network callers using either family reach it.
listen_file=/tmp/nginx-listen-ipv6.conf
if [ "${WM_LISTEN_IPV6:-true}" != "false" ] && [ -s /proc/net/if_inet6 ]; then
  printf 'listen [::]:8080;\n' > "$listen_file"
  log "nginx: listening on 0.0.0.0:8080 and [::]:8080"
else
  printf '# IPv6 listener disabled\n' > "$listen_file"
  log "nginx: listening on 0.0.0.0:8080 only"
fi

exec /app/entrypoint.sh
