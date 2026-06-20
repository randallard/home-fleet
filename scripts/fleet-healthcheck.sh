#!/usr/bin/env bash
#
# fleet-healthcheck.sh — is the backup current and snapshotted? (Phase 6 monitoring floor.)
#
# Run ON tenx (the backup). For each home it:
#   * compares local refs to acer (the primary / source of truth) and flags replication LAG,
#   * checks the newest snapshot bundle's age and flags STALE snapshots.
# Exits non-zero if anything is behind or stale — so a systemd timer can alert, and the signal
# can later feed the `gr status` table (PROGRESS §5).
#
# Generic — no repo names; safe to publish.
set -euo pipefail

GITROOT="${GITROOT:-/data/git}"
SNAP="${SNAP:-/data/git/.snapshots}"
ACER="${ACER:-acer-lan}"                 # client alias to the primary
SNAP_MAX_AGE_H="${SNAP_MAX_AGE_H:-36}"   # warn if newest bundle older than this

c_grn=$'\033[0;32m'; c_yel=$'\033[1;33m'; c_red=$'\033[0;31m'; c_off=$'\033[0m'
ok()   { printf '%s[ok]%s   %s\n' "$c_grn" "$c_off" "$*"; }
warn() { printf '%s[warn]%s %s\n' "$c_yel" "$c_off" "$*"; warns=$((warns+1)); }
err()  { printf '%s[ERR]%s  %s\n' "$c_red" "$c_off" "$*"; warns=$((warns+1)); }

fp_local() { git -C "$1" for-each-ref --format='%(objectname) %(refname)' refs/heads refs/tags | sort; }
fp_acer()  { git ls-remote "$ACER:$GITROOT/$1.git" 'refs/heads/*' 'refs/tags/*' 2>/dev/null | awk '{print $1" "$2}' | sort || true; }

warns=0
now="$(date +%s)"
for h in "$GITROOT"/*.git; do
  [ -d "$h" ] || continue
  name="$(basename "$h" .git)"

  # --- replication lag: refs acer has that tenx is missing/behind on ---
  acer="$(fp_acer "$name")"
  if [ -z "$acer" ]; then
    warn "$name: cannot read acer ($ACER) — primary unreachable or home absent"
  else
    behind="$(comm -23 <(printf '%s\n' "$acer") <(fp_local "$h") | grep -c . || true)"
    if [ "$behind" -gt 0 ]; then warn "$name: $behind ref(s) behind acer (replication lag)"
    else ok "$name: in sync with acer"; fi
  fi

  # --- snapshot freshness ---
  newest="$(ls -1t "$SNAP/$name"/*.bundle 2>/dev/null | head -1 || true)"
  if [ -z "$newest" ]; then
    warn "$name: no snapshot bundle found under $SNAP/$name"
  else
    age_h=$(( (now - $(stat -c %Y "$newest")) / 3600 ))
    if [ "$age_h" -gt "$SNAP_MAX_AGE_H" ]; then warn "$name: newest snapshot is ${age_h}h old (> ${SNAP_MAX_AGE_H}h)"
    else ok "$name: snapshot ${age_h}h old"; fi
  fi
done

if [ "$warns" -eq 0 ]; then printf '\n%s== healthy ==%s backup in sync + snapshotted.\n' "$c_grn" "$c_off"; exit 0
else printf '\n%s== %d issue(s) ==%s\n' "$c_yel" "$warns" "$c_off"; exit 1; fi
