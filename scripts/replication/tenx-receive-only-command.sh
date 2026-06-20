#!/usr/bin/env bash
#
# tenx-receive-only-command.sh — SSH forced-command for acer's replication key on tenx.
#
# Installed via authorized_keys (see SETUP-replication.md):
#   command="/data/git/.replication/tenx-receive-only-command.sh",no-pty,no-port-forwarding,
#   no-agent-forwarding,no-X11-forwarding ssh-ed25519 AAAA...  acer-replication
#
# Restricts acer to git transport ONLY, scoped to /data/git/*.git: it allows
# git-receive-pack (writes) and git-upload-pack (read/verify), and rejects shells and
# everything else (AC: least privilege). ff-only / no-delete is enforced *in addition*
# by per-home receive config + the pre-receive hook (tenx-harden-homes.sh).
#
# Generic — no repo names; safe to publish.
set -euo pipefail

cmd="${SSH_ORIGINAL_COMMAND:-}"
log="/data/git/.replication/tenx-access.log"
ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
mkdir -p "$(dirname "$log")"
deny() { echo "$(ts) DENY ${SSH_CONNECTION%% *} :: ${cmd:-<none>}" >>"$log"; echo "access denied" >&2; exit 1; }

# Only the two git transport verbs.
verb="${cmd%% *}"
case "$verb" in
  git-receive-pack|git-upload-pack) : ;;
  *) deny ;;
esac

# Path must be a single-quoted bare home under /data/git, no traversal.
path="${cmd#"$verb" }"; path="${path//\'/}"
case "$path" in
  /data/git/*.git) : ;;
  *) deny ;;
esac
case "$path" in *..*) deny ;; esac

echo "$(ts) OK   ${SSH_CONNECTION%% *} :: $verb '$path'" >>"$log"
exec git shell -c "$verb '$path'"
