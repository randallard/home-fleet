#!/usr/bin/env bash
#
# acer-mirror-one.sh <bare-home-path> — replicate ONE acer home to the tenx backup.
#
# Controller path (ADR-0002 / ADR-0003): acer is the authoritative copy; this ff-only,
# never-force, never-delete push mirrors a single home to tenx. Used by both the
# per-home post-receive hook (real-time) and the scheduled sweep (catch-up). Audited.
#
# Generic — no repo names; safe to publish.
set -euo pipefail

HOME_DIR="${1:?usage: acer-mirror-one.sh /data/git/<repo>.git}"
TENX="${TENX:-tenx-backup}"            # ssh alias to tenx's receive-only key (SETUP-replication.md)
DEST_ROOT="${DEST_ROOT:-/data/git}"    # home root on tenx
AUDIT="${AUDIT:-/data/git/.replication/audit.log}"

name="$(basename "$HOME_DIR")"
dest="$DEST_ROOT/$name"
ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
mkdir -p "$(dirname "$AUDIT")"

# ff-only by construction: plain (non-+) refspecs, so a non-fast-forward ref is REJECTED,
# never forced. No deletes (we never push :ref). tenx enforces the same server-side.
if out="$(git -C "$HOME_DIR" push "$TENX:$dest" \
            'refs/heads/*:refs/heads/*' 'refs/tags/*:refs/tags/*' 2>&1)"; then
  echo "$(ts) OK    $name -> $TENX" >>"$AUDIT"
else
  echo "$(ts) FAIL  $name -> $TENX :: $(printf '%s' "$out" | tr '\n' ' ' | tail -c 240)" >>"$AUDIT"
  exit 1
fi
