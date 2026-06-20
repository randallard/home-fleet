#!/usr/bin/env bash
#
# seed-acer.sh — Phase 2: one-time mirror of every tenx home onto acer.
#
# Runs ON tenx. For each bare home under /data/git, it creates the matching bare repo on
# acer (over the FIPS-pinned SSH alias from SETUP-acer.md), sets its HEAD to match, pushes
# with mirror semantics, and verifies the ref sets are identical.
#
# PREREQUISITES (in order):
#   1. acer is a reachable home server  — see docs/SETUP-acer.md (Phase 1).
#   2. tenx homes are clean/canonical   — run scripts/tenx-cleanup.sh --apply first.
#
# SAFE BY DEFAULT:
#   * Dry-run unless --apply (prints the plan, changes nothing).
#   * Idempotent: a home already present on acer AND identical is skipped.
#   * NEVER clobbers — if an acer home already exists but DIFFERS (e.g. a client has
#     started pushing to acer), it aborts that repo for you to reconcile by hand.
#   * Verifies every seeded repo ref-by-ref before calling it done.
#
# This file hardcodes no repo names (it globs /data/git/*.git) — safe to publish.
#
# Usage:
#   ./seed-acer.sh                 # dry-run over the LAN alias (acer-lan)
#   ./seed-acer.sh --apply         # do it
#   ACER=acer-ts ./seed-acer.sh --apply    # seed over Tailscale instead of LAN

set -euo pipefail

# ---- config ---------------------------------------------------------------
GITROOT="/data/git"                 # source homes on tenx
DEST_ROOT="${DEST_ROOT:-/data/git}" # home root on acer
ACER="${ACER:-acer-lan}"            # SSH alias to acer (acer-lan = LAN, acer-ts = Tailscale)

APPLY=0
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    --acer=*) ACER="${arg#*=}" ;;
    -h|--help) sed -n '2,33p' "$0"; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

# ---- output helpers -------------------------------------------------------
c_grn=$'\033[0;32m'; c_yel=$'\033[1;33m'; c_red=$'\033[0;31m'; c_dim=$'\033[2m'; c_off=$'\033[0m'
info() { printf '%s[*]%s %s\n' "$c_grn" "$c_off" "$*"; }
warn() { printf '%s[!]%s %s\n' "$c_yel" "$c_off" "$*"; }
die()  { printf '%s[ABORT]%s %s\n' "$c_red" "$c_off" "$*" >&2; exit 1; }
run()  { if [ "$APPLY" -eq 1 ]; then printf '%s[run]%s %s\n' "$c_grn" "$c_off" "$*"; "$@";
         else printf '%s[dry]%s %s\n' "$c_dim" "$c_off" "$*"; fi; }

# ref fingerprints: "<sha> <ref>" lines for heads+tags, sorted, comparable across sides.
fp_local() { git -C "$1" for-each-ref --format='%(objectname) %(refname)' refs/heads refs/tags | sort; }
fp_acer()  { git ls-remote "$ACER:$1" 'refs/heads/*' 'refs/tags/*' | awk '{print $1" "$2}' | sort; }

# ---- preflight ------------------------------------------------------------
[ "$(hostname)" = "tenx-rltec" ] || die "run this ON tenx (hostname=$(hostname))."
[ -d "$GITROOT" ]                || die "$GITROOT not found."
info "checking acer is reachable over '$ACER' (FIPS alias)…"
ssh -o BatchMode=yes "$ACER" true 2>/dev/null || die "cannot reach acer via '$ACER' — finish Phase 1 (SETUP-acer.md) and pin the host key first."
info "acer reachable. Source: $GITROOT/*.git  →  $ACER:$DEST_ROOT/"
[ "$APPLY" -eq 1 ] || warn "DRY-RUN — nothing will change. Re-run with --apply to execute."

# ---- per-repo seed --------------------------------------------------------
seeded=0; skipped=0; planned=0
for src in "$GITROOT"/*.git; do
  [ -d "$src" ] || continue
  name="$(basename "$src")"
  dest="$DEST_ROOT/$name"
  srcrefs="$(fp_local "$src")"
  nrefs="$(printf '%s\n' "$srcrefs" | grep -c . || true)"
  srchead="$(git -C "$src" symbolic-ref HEAD 2>/dev/null || echo 'HEAD?')"
  printf '\n%s== %s ==%s  (%s refs, HEAD=%s)\n' "$c_grn" "$name" "$c_off" "$nrefs" "${srchead#refs/heads/}"

  if ssh -o BatchMode=yes "$ACER" "test -d '$dest'" 2>/dev/null; then
    # exists on acer — compare, never clobber a divergent home
    if [ "$srcrefs" = "$(fp_acer "$dest")" ]; then
      info "already on acer and identical — skipping."; skipped=$((skipped+1)); continue
    else
      warn "acer already has $name but its refs DIFFER from tenx."
      die  "refusing to overwrite (a client may have pushed to acer). Reconcile $name by hand, then re-run."
    fi
  fi

  # not present on acer — create, set HEAD, mirror
  if [ "$APPLY" -eq 0 ]; then
    info "would: init bare on acer, set HEAD=$srchead, push --mirror ($nrefs refs)"; planned=$((planned+1)); continue
  fi
  run ssh -o BatchMode=yes "$ACER" "git init --bare '$dest' >/dev/null && git -C '$dest' symbolic-ref HEAD '$srchead'"
  run git -C "$src" push --mirror "$ACER:$dest"

  # verify ref-by-ref
  if [ "$srcrefs" = "$(fp_acer "$dest")" ]; then
    info "seeded + verified ($nrefs refs match)."; seeded=$((seeded+1))
  else
    die "ref MISMATCH after seeding $name — investigate before trusting acer for this repo."
  fi
done

printf '\n%s== summary ==%s seeded=%d  skipped(in-sync)=%d  planned(dry-run)=%d\n' "$c_grn" "$c_off" "$seeded" "$skipped" "$planned"
[ "$APPLY" -eq 1 ] && info "Next: Phase 3 (acer→tenx replication) and Phase 4 (cut clients over)." \
                   || info "Dry-run complete. Re-run with --apply once acer is up + tenx-cleanup applied."
