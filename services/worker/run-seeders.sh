#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
#
# World Monitor seed runner for Railway cron services (community template).
#
# Upstream's self-hosting guide runs scripts/run-seeders.sh from the host every
# 30 minutes. Railway has no host, so each seed-* cron service runs one tier of
# upstream's seed scripts and exits:
#
#   run-seeders.sh live|hourly|4h|daily|bundles
#
# The tier lists live in /opt/railway/tiers/<tier>.txt. Variables:
#   SEEDERS          replace the tier list (comma or space separated names)
#   SEEDERS_EXTRA    add names to the tier list
#   SEEDERS_SKIP     remove names from the tier list
#   SEED_TIMEOUT     wall-clock cap per seeder in seconds (tier default)
#   SEED_PARALLEL    seeders run at the same time (tier default)
#   SEED_ROTATE      true/false: rotate the start position every tick
#   SEED_VERBOSE     true: print each seeder's full log, not just the last line
#   SEED_MIN_INTERVAL   seconds a successful seeder is not re-run (0 = always run;
#                       tier default). Lets slow tiers tick hourly, so a new
#                       install fills within the first hour, while each seeder
#                       still runs at its own cadence. Recorded in Redis.
#   SEED_RETRY_INTERVAL seconds before a failed or timed-out seeder is retried
# A name is the part between "seed-" and ".mjs" in upstream's scripts/ folder,
# e.g. "earthquakes" or "bundle-climate".
set -u

APP_DIR="${WM_APP_DIR:-/app}"
TIERS_DIR="${SEED_TIERS_DIR:-/opt/railway/tiers}"
SELF="$0"

log() { printf '[seed-%s] %s\n' "${SEED_RUN_TAG:-run}" "$*"; }

is_uint() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) [ "$1" -gt 0 ] ;;
  esac
}

# One Redis command through redis-rest (Upstash JSON protocol). Prints the
# result (empty for null); exits non-zero on any transport or command error.
redis_cmd() {
  node -e '
    const base = process.env.UPSTASH_REDIS_REST_URL.replace(/\/+$/, "");
    fetch(base, {
      method: "POST",
      headers: {
        Authorization: "Bearer " + process.env.UPSTASH_REDIS_REST_TOKEN,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(process.argv.slice(1)),
      signal: AbortSignal.timeout(5000),
    }).then((r) => (r.ok ? r.json() : Promise.reject(new Error("HTTP " + r.status))))
      .then((j) => { if (j.error) process.exit(2); process.stdout.write(j.result == null ? "" : String(j.result)); })
      .catch(() => process.exit(2));
  ' "$@"
}

# Freshness gate: a key per seeder that expires when the seeder is due again.
gate_key() { printf 'railway-template:seed-gate:v1:%s' "$1"; }
# Prints the stored "ok:<epoch>" / "fail:<epoch>" while the gate is closed.
gate_value() {
  [ "${SEED_RUN_MIN_INTERVAL:-0}" -gt 0 ] || return 1
  redis_cmd GET "$(gate_key "$1")" || return 1
}
# gate_set <name> <ok|fail> <ttl-seconds>
gate_set() {
  [ "${SEED_RUN_MIN_INTERVAL:-0}" -gt 0 ] || return 0
  [ "$3" -gt 0 ] || return 0
  redis_cmd SET "$(gate_key "$1")" "$2:$(date +%s)" EX "$3" >/dev/null || true
}

# One seeder (used through xargs for parallel runs). Prints one result line.
run_one() {
  name="$1"
  script="$APP_DIR/scripts/seed-$name.mjs"
  if [ ! -f "$script" ]; then
    log "$name: SKIP (no scripts/seed-$name.mjs in this release)"
    return 0
  fi
  gate=$(gate_value "$name" 2>/dev/null || true)
  case "$gate" in
    ok:*) log "$name: FRESH (succeeded less than ${SEED_RUN_MIN_INTERVAL}s ago)"; return 0 ;;
    fail:*) log "$name: DEFER (failed less than ${SEED_RUN_RETRY_INTERVAL}s ago; retried later)"; return 0 ;;
  esac
  out="$SEED_RUN_LOG_DIR/$name.log"
  start=$(date +%s)
  ( cd "$APP_DIR" && exec timeout -k 30 "$SEED_RUN_TIMEOUT" node "$script" ) > "$out" 2>&1
  rc=$?
  took=$(( $(date +%s) - start ))
  last=$(tr -d '\r' < "$out" | grep -v '^[[:space:]]*$' | tail -n 1 | cut -c1-200)
  if [ "${SEED_VERBOSE:-false}" = "true" ]; then
    sed "s/^/[seed-$SEED_RUN_TAG][$name] /" "$out"
  fi
  case "$rc" in
    0) log "$name: OK (${took}s)"; gate_set "$name" ok "${SEED_RUN_MIN_INTERVAL:-0}" ;;
    124|137) log "$name: TIMEOUT after ${SEED_RUN_TIMEOUT}s"; gate_set "$name" fail "${SEED_RUN_RETRY_INTERVAL:-0}" ;;
    *) log "$name: FAIL rc=$rc (${took}s) ${last}"; gate_set "$name" fail "${SEED_RUN_RETRY_INTERVAL:-0}" ;;
  esac
  return 0
}

if [ "${1:-}" = "--one" ]; then
  run_one "$2"
  exit 0
fi

TIER="${1:-${SEED_TIER:-}}"
[ -n "$TIER" ] || { echo "usage: run-seeders.sh live|hourly|4h|daily|bundles" >&2; exit 2; }
SEED_RUN_TAG="$TIER"
export SEED_RUN_TAG

: "${UPSTASH_REDIS_REST_URL:?UPSTASH_REDIS_REST_URL is required (private URL of redis-rest)}"
: "${UPSTASH_REDIS_REST_TOKEN:?UPSTASH_REDIS_REST_TOKEN is required (redis-rest SRH_TOKEN)}"

# Gates: 4h and daily ticks run hourly; a seeder that succeeded is skipped
# until its cadence (minus 10 minutes of slack) has passed, a failed one is
# retried after the retry interval.
case "$TIER" in
  live)    def_timeout=300;  def_parallel=3; def_rotate=false; def_gate=0;     def_retry=0 ;;
  hourly)  def_timeout=900;  def_parallel=2; def_rotate=false; def_gate=0;     def_retry=0 ;;
  4h)      def_timeout=1500; def_parallel=2; def_rotate=false; def_gate=13800; def_retry=3600 ;;
  daily)   def_timeout=2400; def_parallel=2; def_rotate=false; def_gate=85800; def_retry=21600 ;;
  bundles) def_timeout=2400; def_parallel=3; def_rotate=true;  def_gate=0;     def_retry=0 ;;
  *)       def_timeout=900;  def_parallel=1; def_rotate=false; def_gate=0;     def_retry=0 ;;
esac
SEED_RUN_TIMEOUT="${SEED_TIMEOUT:-$def_timeout}"
PARALLEL="${SEED_PARALLEL:-$def_parallel}"
ROTATE="${SEED_ROTATE:-$def_rotate}"
SEED_RUN_MIN_INTERVAL="${SEED_MIN_INTERVAL:-$def_gate}"
SEED_RUN_RETRY_INTERVAL="${SEED_RETRY_INTERVAL:-$def_retry}"
is_uint "$SEED_RUN_TIMEOUT" || { log "SEED_TIMEOUT must be a positive integer (seconds)"; exit 2; }
is_uint "$PARALLEL" || { log "SEED_PARALLEL must be a positive integer"; exit 2; }
case "$SEED_RUN_MIN_INTERVAL$SEED_RUN_RETRY_INTERVAL" in
  *[!0-9]*) log "SEED_MIN_INTERVAL and SEED_RETRY_INTERVAL must be whole seconds (0 disables)"; exit 2 ;;
esac
export SEED_RUN_TIMEOUT SEED_RUN_MIN_INTERVAL SEED_RUN_RETRY_INTERVAL

# Names: drop comments and blanks, accept "seed-x" / "x.mjs", keep first occurrence.
normalize() {
  sed -e 's/#.*//' | tr ', \t' '\n\n\n' | sed -e 's/^seed-//' -e 's/\.mjs$//' \
    | grep -E '^[a-z0-9][a-z0-9-]*$' | awk '!seen[$0]++'
}

if [ -n "${SEEDERS:-}" ]; then
  list=$(printf '%s\n' "$SEEDERS" | normalize)
else
  list_file="$TIERS_DIR/$TIER.txt"
  [ -f "$list_file" ] || { log "unknown tier '$TIER' (no $list_file); set SEEDERS"; exit 2; }
  list=$(normalize < "$list_file")
fi
if [ -n "${SEEDERS_EXTRA:-}" ]; then
  list=$(printf '%s\n%s\n' "$list" "$SEEDERS_EXTRA" | normalize)
fi
if [ -n "${SEEDERS_SKIP:-}" ]; then
  skip=$(printf '%s\n' "$SEEDERS_SKIP" | normalize)
  list=$(printf '%s\n' "$list" | grep -vxF "$skip" || true)
fi
count=$(printf '%s\n' "$list" | grep -c . || true)
[ "$count" -gt 0 ] || { log "nothing to run"; exit 0; }

if [ "$ROTATE" = "true" ] && [ "$count" -gt 1 ]; then
  offset=$(( $(date +%s) / 900 % count ))
  list=$(printf '%s\n' "$list" | awk -v off="$offset" '{ a[NR] = $0 } END { for (i = 1; i <= NR; i++) print a[(i + off - 1) % NR + 1] }')
fi

# Wait for redis-rest. Services start in parallel and repo builds finish at
# different times, so the first tick can come before the proxy is up.
wait_max="${SEED_REDIS_WAIT_SECONDS:-300}"
is_uint "$wait_max" || wait_max=300
waited=0
until node -e '
  const base = process.env.UPSTASH_REDIS_REST_URL.replace(/\/+$/, "");
  fetch(base + "/ping", {
    headers: { Authorization: "Bearer " + process.env.UPSTASH_REDIS_REST_TOKEN },
    signal: AbortSignal.timeout(5000),
  }).then((r) => process.exit(r.ok ? 0 : 1), () => process.exit(1));
'; do
  if [ "$waited" -ge "$wait_max" ]; then
    log "redis-rest did not answer /ping within ${wait_max}s; giving up this tick"
    exit 1
  fi
  sleep 5
  waited=$((waited + 5))
done

SEED_RUN_LOG_DIR=$(mktemp -d /tmp/seed-run.XXXXXX)
export SEED_RUN_LOG_DIR
trap 'trap - TERM INT; log "stopping (signal)"; kill 0 2>/dev/null; exit 143' TERM INT

started=$(date +%s)
log "tick: $count seeders, parallel $PARALLEL, cap ${SEED_RUN_TIMEOUT}s each, re-run gate ${SEED_RUN_MIN_INTERVAL}s"
printf '%s\n' "$list" | xargs -r -n 1 -P "$PARALLEL" "$SELF" --one > "$SEED_RUN_LOG_DIR/results" 2>&1
cat "$SEED_RUN_LOG_DIR/results"

ok=$(grep -c ': OK ' "$SEED_RUN_LOG_DIR/results" || true)
failed=$(grep -c ': FAIL ' "$SEED_RUN_LOG_DIR/results" || true)
timedout=$(grep -c ': TIMEOUT ' "$SEED_RUN_LOG_DIR/results" || true)
skipped=$(grep -c ': SKIP ' "$SEED_RUN_LOG_DIR/results" || true)
fresh=$(grep -c ': FRESH ' "$SEED_RUN_LOG_DIR/results" || true)
deferred=$(grep -c ': DEFER ' "$SEED_RUN_LOG_DIR/results" || true)
log "done in $(( $(date +%s) - started ))s: ok=$ok failed=$failed timeout=$timedout fresh=$fresh deferred=$deferred skipped=$skipped"
log "a FAIL usually means a missing optional API key or an upstream outage; see the line above it"
rm -rf "$SEED_RUN_LOG_DIR"

# Fail the cron run only when nothing worked at all (wrong token, no network).
if [ "$ok" -eq 0 ] && [ $((failed + timedout)) -gt 0 ]; then
  exit 1
fi
exit 0
