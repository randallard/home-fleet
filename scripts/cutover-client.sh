#!/usr/bin/env bash
#
# cutover-client.sh [--apply] — Phase 4: point a client's backup remotes at acer (the new
# primary), and keep tenx as a restore-only remote. Run ON each client (incl. tenx itself,
# whose working copies also back up to acer).
#
# For every working copy under the configured roots that has a backup remote:
#   * preserve its current tenx target as `tenx-lan` / `tenx` (restore-only), then
#   * set  data-lan -> acer-lan:/data/git/<name>.git   (primary, LAN)
#          data     -> acer-ts:/data/git/<name>.git    (primary, Tailscale)
# <name> is taken from the existing remote URL, so it follows the canonical home name that
# tenx-cleanup already settled. gr keeps pushing to `data-lan`/`data` (now acer); tenx is
# left wired only for manual restore (replication, not clients, keeps tenx current).
#
# SAFE: dry-run by default; idempotent (a repo already on acer is skipped); reversible
# (the tenx remotes are preserved — to roll back, point data* back at them). Repointing a
# remote is not a commit, so this is fine on every repo including work repos.
#
# Generic — no repo names; safe to publish.
#
# Usage:
#   ./cutover-client.sh                         # dry-run over ~/Development
#   ROOTS="$HOME/Development /data/src" ./cutover-client.sh --apply
set -euo pipefail

IFS=' ' read -r -a ROOTS <<< "${ROOTS:-$HOME/Development}"
ACER_LAN="${ACER_LAN:-acer-lan}"
ACER_TS="${ACER_TS:-acer-ts}"
DEST_ROOT="${DEST_ROOT:-/data/git}"
APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1

c_grn=$'\033[0;32m'; c_yel=$'\033[1;33m'; c_dim=$'\033[2m'; c_off=$'\033[0m'
info() { printf '%s[*]%s %s\n' "$c_grn" "$c_off" "$*"; }
skip() { printf '%s[-]%s %s\n' "$c_dim" "$c_off" "$*"; }
run()  { if [ "$APPLY" -eq 1 ]; then printf '%s[run]%s %s\n' "$c_grn" "$c_off" "$*"; "$@";
         else printf '%s[dry]%s %s\n' "$c_dim" "$c_off" "$*"; fi; }

# set-url if the remote exists, else add it.
set_or_add() { # <repo> <remote> <url>
  if git -C "$1" remote get-url "$2" >/dev/null 2>&1; then run git -C "$1" remote set-url "$2" "$3"
  else run git -C "$1" remote add "$2" "$3"; fi
}

[ "$APPLY" -eq 1 ] || printf '%s[!]%s DRY-RUN — nothing will change. Re-run with --apply.\n' "$c_yel" "$c_off"

cut=0; done_already=0
for root in "${ROOTS[@]}"; do
  [ -d "$root" ] || { skip "root not present: $root"; continue; }
  for repo in "$root"/*/; do
    [ -d "$repo/.git" ] || continue
    name_dir="$(basename "$repo")"

    # current primary backup remote: prefer data-lan, then data
    cur=""
    for r in data-lan data; do
      if u="$(git -C "$repo" remote get-url "$r" 2>/dev/null)"; then cur="$u"; break; fi
    done
    [ -n "$cur" ] || { skip "$name_dir: no data/data-lan remote — not in the fleet"; continue; }

    # already pointing at acer?
    case "$cur" in
      "$ACER_LAN":*|"$ACER_TS":*|*acer*) info "$name_dir: already cut over"; done_already=$((done_already+1)); continue ;;
    esac

    home="$(basename "$cur" .git)"          # canonical home name from the existing URL
    printf '\n%s== %s ==%s  (home: %s.git)\n' "$c_grn" "$name_dir" "$c_off" "$home"

    # preserve current tenx targets as restore-only remotes
    if u="$(git -C "$repo" remote get-url data-lan 2>/dev/null)"; then set_or_add "$repo" tenx-lan "$u"; fi
    if u="$(git -C "$repo" remote get-url data     2>/dev/null)"; then set_or_add "$repo" tenx     "$u"; fi

    # repoint the primary at acer
    set_or_add "$repo" data-lan "$ACER_LAN:$DEST_ROOT/$home.git"
    set_or_add "$repo" data     "$ACER_TS:$DEST_ROOT/$home.git"
    cut=$((cut+1))
  done
done

printf '\n%s== summary ==%s cut-over=%d  already=%d\n' "$c_grn" "$c_off" "$cut" "$done_already"
cat <<NOTE

Next on this client:
  1. Update ~/.config/git-redundancy/config.toml (see docs/SETUP-cutover.md):
       default_remotes = ["data-lan", "data"]
       [transport] order = ["data-lan", "data"]
       [server] root = "/data/git"  aliases = ["acer-lan", "acer-ts"]
  2. gr status            # table over acer, lifecycle populated
  3. gr push --dry-run    # confirm it targets acer, then: gr push
  4. Confirm it reached tenx via replication (acer's audit log / ls-remote tenx).
NOTE
[ "$APPLY" -eq 1 ] || echo "(dry-run — re-run with --apply to make the changes)"
