#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
#
# Railway start wrapper for World Monitor's Redis REST proxy: check the
# required variables, pick a dual-stack listen address, start the proxy.
set -eu

fail() { printf '[redis-rest] ERROR: %s\n' "$*" >&2; exit 1; }

[ -n "${SRH_TOKEN:-}" ] || fail "SRH_TOKEN is not set (bearer token every caller sends)"
[ -n "${SRH_CONNECTION_STRING:-}" ] || fail "SRH_CONNECTION_STRING is not set (redis://default:<password>@<host>:6379)"

if [ -z "${SRH_LISTEN_HOST:-}" ]; then
  if [ -s /proc/net/if_inet6 ]; then
    SRH_LISTEN_HOST='::'
  else
    SRH_LISTEN_HOST='0.0.0.0'
  fi
fi
export SRH_LISTEN_HOST

exec node /app/redis-rest-proxy.mjs
