#!/usr/bin/env bash
#
# promote-tenx.sh [--apply] — FAILOVER: when acer is down, point a client's backup back at
# tenx so work keeps getting backed up. The inverse of cutover-client.sh; relies on the
# `tenx-lan` / `tenx` restore remotes that cutover preserved.
#
# Run ON each client during an acer outage. For every working copy whose data* points at acer:
#   data-lan <- (tenx-lan's URL)     data <- (tenx's URL)
# Then set gr's [server].aliases back to tenx and push. When acer is rebuilt, re-seed it from
# tenx and run cutover-client.sh again to fail back (see docs/SETUP-failover.md).
#
# SAFE: dry-run by default; idempotent; reversible. Generic — no repo names; safe to publish.
set -euo pipefail

IFS=' ' read -r -a ROOTS <<< "${ROOTS:-$HOME/Development}"
APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1

c_grn=$'\033[0;32m'; c_yel=$'\033[1;33m'; c_dim=$'\033[2m'; c_off=$'\033[0m'
info() { printf '%s[*]%s %s\n' "$c_grn" "$c_off" "$*"; }
skip() { printf '%s[-]%s %s\n' "$c_dim" "$c_off" "$*"; }
run()  { if [ "$APPLY" -eq 1 ]; then printf '%s[run]%s %s\n' "$c_grn" "$c_off" "$*"; "$@";
         else printf '%s[dry]%s %s\n' "$c_dim" "$c_off" "$*"; fi; }

[ "$APPLY" -eq 1 ] || printf '%s[!]%s DRY-RUN — re-run with --apply.\n' "$c_yel" "$c_off"

moved=0
for root in "${ROOTS[@]}"; do
  [ -d "$root" ] || { skip "root not present: $root"; continue; }
  for repo in "$root"/*/; do
    [ -d "$repo/.git" ] || continue
    name="$(basename "$repo")"
    cur="$(git -C "$repo" remote get-url data 2>/dev/null || true)"
    [ -n "$cur" ] || { skip "$name: no data remote"; continue; }
    case "$cur" in *acer*) : ;; *) skip "$name: data not on acer (already on tenx?)"; continue ;; esac
    t_lan="$(git -C "$repo" remote get-url tenx-lan 2>/dev/null || true)"
    t_ts="$(git -C "$repo" remote get-url tenx 2>/dev/null || true)"
    if [ -z "$t_lan" ] && [ -z "$t_ts" ]; then
      skip "$name: no tenx restore remote to promote to — skipping"; continue
    fi
    info "$name: promoting data* -> tenx"
    [ -n "$t_lan" ] && run git -C "$repo" remote set-url data-lan "$t_lan"
    [ -n "$t_ts" ]  && run git -C "$repo" remote set-url data     "$t_ts"
    moved=$((moved+1))
  done
done

printf '\n%s== summary ==%s promoted=%d\n' "$c_grn" "$c_off" "$moved"
cat <<NOTE

Then on this client:
  * gr config: [server].aliases = ["tenx-lan","tenx"], default_remotes stays ["data-lan","data"].
  * gr push   # now backs up to tenx while acer is down.
When acer returns: re-seed it from tenx (seed-acer.sh), re-wire replication (SETUP-replication.md),
then cutover-client.sh --apply to fail back to acer. See docs/SETUP-failover.md.
NOTE
