#!/usr/bin/env bash
#
# tenx-snapshot.sh — read-only bundle of every tenx home (CP: recoverable point-in-time
# copies; defense against a corrupting/ransoming push slipping past ff-only). Run by a
# systemd timer (default daily, see SETUP-replication.md). Keeps KEEP_DAILY per repo.
#
# Generic — no repo names; safe to publish.
set -euo pipefail

GITROOT="${GITROOT:-/data/git}"
SNAP="${SNAP:-/data/git/.snapshots}"
KEEP_DAILY="${KEEP_DAILY:-14}"
today="$(date -u +%Y%m%d)"

for h in "$GITROOT"/*.git; do
  [ -d "$h" ] || continue
  name="$(basename "$h" .git)"
  d="$SNAP/$name"; mkdir -p "$d"
  if git -C "$h" bundle create "$d/$name-$today.bundle" --all >/dev/null 2>&1; then
    echo "snapshot: $name-$today.bundle"
  else
    echo "snapshot FAILED: $name" >&2
  fi
  # retention: keep the newest $KEEP_DAILY bundles, drop the rest.
  ls -1t "$d"/*.bundle 2>/dev/null | tail -n +"$((KEEP_DAILY + 1))" | xargs -r rm -f
done
