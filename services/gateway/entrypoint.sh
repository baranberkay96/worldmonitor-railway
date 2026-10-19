#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
#
# Writes the login block for the Caddyfile, then starts Caddy.
set -eu

fail() { printf '[gateway] ERROR: %s\n' "$*" >&2; exit 1; }

[ -n "${WM_APP_UPSTREAM:-}" ] || fail "WM_APP_UPSTREAM is not set (private host:port of the worldmonitor service)"

auth_dir=/tmp/wm-gateway
auth_file="$auth_dir/auth.caddy"
mkdir -p "$auth_dir"

if [ "${WM_PUBLIC_DASHBOARD:-false}" = "true" ]; then
  printf '[gateway] WM_PUBLIC_DASHBOARD=true: NO login. Anyone with the URL can use the dashboard and its API on your keys.\n' >&2
  # A no-op handler keeps the import non-empty.
  printf 'vars wm_login off\n' > "$auth_file"
else
  user="${WM_UI_USERNAME:-}"
  pass="${WM_UI_PASSWORD:-}"
  [ -n "$user" ] || fail "WM_UI_USERNAME is empty (or set WM_PUBLIC_DASHBOARD=true to drop the login)"
  [ -n "$pass" ] || fail "WM_UI_PASSWORD is empty (or set WM_PUBLIC_DASHBOARD=true to drop the login)"
  case "$user" in
    *[!A-Za-z0-9._@-]*) fail "WM_UI_USERNAME may only contain letters, digits and . _ @ -" ;;
  esac
  [ "${#pass}" -ge 12 ] || fail "WM_UI_PASSWORD must be at least 12 characters"
  # Read from stdin so the password never appears in a process list.
  hash=$(printf '%s\n' "$pass" | caddy hash-password) || fail "could not hash WM_UI_PASSWORD"
  case "$hash" in
    '$2'*) ;;
    *) fail "unexpected output from caddy hash-password" ;;
  esac
  printf 'basic_auth bcrypt "World Monitor" {\n\t%s %s\n}\n' "$user" "$hash" > "$auth_file"
  printf '[gateway] login enabled for user %s\n' "$user"
fi

exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
