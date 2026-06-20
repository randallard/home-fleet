#!/usr/bin/env bash
#
# acer-sweep.sh — push EVERY acer home to the tenx backup (ff-only). Run by a systemd
# timer (default every 15 min, see SETUP-replication.md) to catch anything a post-receive
# hook missed (e.g. tenx was down). Idempotent: up-to-date homes push nothing.
#
# Generic — no repo names; safe to publish.
set -euo pipefail

GITROOT="${GITROOT:-/data/git}"
SELF="$(dirname "$(readlink -f "$0")")"
AUDIT="${AUDIT:-/data/git/.replication/audit.log}"
ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

rc=0
for h in "$GITROOT"/*.git; do
  [ -d "$h" ] || continue
  "$SELF/acer-mirror-one.sh" "$h" || rc=1
done
mkdir -p "$(dirname "$AUDIT")"
echo "$(ts) SWEEP done (rc=$rc)" >>"$AUDIT"
exit "$rc"
