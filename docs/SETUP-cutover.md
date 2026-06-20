# Phase 4 — cut clients over to acer

The "do it" checklist for moving every client's **primary** backup from tenx to acer, while
keeping tenx wired for **restore** only. After this, clients push to acer (the authoritative
copy) and acer replicates to tenx ([ADR-0002](adr/0002-fleet-topology-acer-primary-tenx-backup-controller.md)
/ [0003](adr/0003-replication-mechanism-hook-sweep-ff-only-snapshots.md)); nothing writes to
tenx directly anymore.

> **Prerequisite — do not start until Phase 3 is verified.** acer must be seeded (Phase 2) and
> *actively replicating* to tenx (Phase 3 verification drill passed). Cutting clients over
> before replication works would leave new pushes un-backed-up.

## Order of operations (canary first)

1. **One repo on one client** — cut over a single repo by hand or with a narrowed `ROOTS`,
   `gr push` it, confirm it lands on acer *and* propagates to tenx. Only then proceed.
2. **The rest of that client.**
3. **Each remaining client**, one at a time (tenx itself is a client too — its working copies
   under `~/Development` back up to acer like any other box).

## Per-client procedure

### 1. Prerequisites on the client
- [ ] acer SSH aliases present + host key pinned (`acer-lan` / `acer-ts`, from
      [SETUP-acer.md](SETUP-acer.md) steps 4–5). Test: `ssh acer-lan 'echo OK $(hostname)'`.

### 2. Repoint the git remotes
Run [`scripts/cutover-client.sh`](../scripts/cutover-client.sh) on the client — it preserves the
current tenx targets as `tenx-lan` / `tenx` (restore-only) and points `data-lan` / `data` at
acer:
```bash
./scripts/cutover-client.sh                 # dry-run (review)
./scripts/cutover-client.sh --apply         # do it
# non-default working-copy locations:
ROOTS="$HOME/Development /data/src" ./scripts/cutover-client.sh --apply
```
Idempotent (skips repos already on acer) and reversible (tenx remotes are kept).

### 3. Update the gr config
Edit `~/.config/git-redundancy/config.toml` so gr pushes to acer and queries acer for the
lifecycle column:
```toml
default_remotes = ["data-lan", "data"]      # data* now point at acer

[transport]
auto = true
order = ["data-lan", "data"]                # LAN first, Tailscale fallback

[server]
root = "/data/git"
aliases = ["acer-lan", "acer-ts"]           # was tenx (or local on tenx); now acer
```
> On **tenx**, this also fixes the `?` lifecycle column we had under the local-only config —
> with `aliases = ["acer-lan","acer-ts"]`, gr reaches a server over SSH and the column
> populates. tenx's working copies now push to acer (the local `/data/git` homes are maintained
> by replication, not by tenx's own pushes).

### 4. Verify
- [ ] `gr status` — table renders over acer; lifecycle column populated (not `?`).
- [ ] `gr push --dry-run` — targets `data-lan`/`data` = **acer**; then `gr push`.
- [ ] **Round-trip:** the pushed commit appears on tenx via replication within the hook/sweep
      window (`git ls-remote tenx:/data/git/<repo>.git`, or acer's
      `/data/git/.replication/audit.log` shows `OK`).
- [ ] **Restore path intact:** `git ls-remote tenx-lan:/data/git/<repo>.git` (or the `tenx`
      remote) still works for recovery.

## Rollback (if needed)
The tenx remotes are preserved, so reverting a repo is just repointing the primary back:
```bash
git -C <repo> remote set-url data-lan "$(git -C <repo> remote get-url tenx-lan)"
git -C <repo> remote set-url data     "$(git -C <repo> remote get-url tenx)"
```
and restore the previous `config.toml` (`aliases`/`default_remotes`).

## Notes
- gr only pushes to `default_remotes` (acer); the `tenx*` remotes are for manual restore, not
  push — tenx stays current via replication, not client writes. (Confirming tenx freshness is
  the deferred monitoring floor — PROGRESS §5.)
- This sets up **Phase 5** (demote/harden tenx): once no client writes to tenx directly, tenx
  becomes receive-only-from-acer.
