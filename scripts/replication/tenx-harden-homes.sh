#!/usr/bin/env bash
#
# tenx-harden-homes.sh [--apply] — make every tenx home reject non-ff updates and deletes,
# and install the pre-receive integrity hook. Run ON tenx after the homes are seeded.
#
# Dry-run by default. Generic — no repo names; safe to publish.
set -euo pipefail

GITROOT="${GITROOT:-/data/git}"
SELF="$(dirname "$(readlink -f "$0")")"
APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1

for h in "$GITROOT"/*.git; do
  [ -d "$h" ] || continue
  name="$(basename "$h")"
  if [ "$APPLY" -eq 1 ]; then
    git -C "$h" config receive.denyNonFastForwards true
    git -C "$h" config receive.denyDeletes true
    install -m 0755 "$SELF/tenx-pre-receive" "$h/hooks/pre-receive"
    echo "hardened: $name (denyNonFastForwards + denyDeletes + pre-receive)"
  else
    echo "[dry] would harden: $name (denyNonFastForwards + denyDeletes + pre-receive)"
  fi
done
[ "$APPLY" -eq 1 ] || echo "(dry-run — re-run with --apply)"
