# ADR-0003: Replication mechanism — post-receive hook + sweep, ff-only, snapshotted
- Status: Accepted
- Date: 2026-06-19
- Deciders: Ryan

## Context
[ADR-0002](0002-fleet-topology-acer-primary-tenx-backup-controller.md) settled the *shape*:
acer is the primary and the replication **controller**, tenx is a hardened, receive-only
backup, replication is **both** a `post-receive` hook and a scheduled sweep. It left the
**specifics** open (PROGRESS §5): exactly how ff-only is enforced on tenx, the snapshot
cadence/retention, and the sweep interval. This ADR pins them so Phase 3 is buildable.

The threat to design against: a stale backup (silent failure), and a compromised/buggy
controller corrupting or erasing the backup (acer holds a write key into tenx).

## Decision

**Trigger — hook + sweep (both).**
- A per-home `post-receive` hook on acer mirrors that home to tenx in near-real-time. It
  pushes *all* heads+tags (self-healing, not just the changed ref) and never blocks the
  client: the client's push to acer has already succeeded, so a backup hiccup is logged and
  left to the sweep.
- A **systemd timer sweep every 15 min** on acer pushes every home to tenx, catching anything
  the hook missed (tenx down, transient failure). Idempotent.

**Push semantics — fast-forward only, never force, never delete.** Pushes use plain
(non-`+`) refspecs `refs/heads/*` and `refs/tags/*`, so a non-fast-forward ref is *rejected*,
never forced; refs are never deleted. This carries gr's no-force principle onto the
replication path (**SI**).

**tenx enforcement — three independent layers (defense in depth):**
1. **SSH forced-command** (`tenx-receive-only-command.sh`) on acer's key: allows only
   `git-receive-pack` / `git-upload-pack` scoped to `/data/git/*.git`; rejects shells and all
   else (**AC** least privilege). The key is a dedicated ed25519 replication key, not a login
   key.
2. **Per-home receive config:** `receive.denyNonFastForwards=true`, `receive.denyDeletes=true`.
3. **Per-home `pre-receive` hook** rejecting any non-ff or delete — redundant with (2) on
   purpose.

**Snapshots — daily read-only bundles, 14-deep (CP).** `tenx-snapshot.sh` (systemd timer,
daily) writes `git bundle --all` per home under `/data/git/.snapshots/<repo>/`, keeping the
newest 14. This is the recovery floor if a bad update ever slips past ff-only (ransomware /
corruption defense), independent of the live homes.

**Audit (AU).** Every replication action is appended (UTC, repo, result) to
`/data/git/.replication/audit.log` on acer; tenx logs every access decision to
`tenx-access.log`. Matches the assurance posture of
[ADR-0001](0001-assurance-standards-provable-rust-strict-ts-fisma-aligned.md).

**Transport.** acer→tenx reuses the FIPS-enforced, host-key-pinned SSH alias pattern
(`tenx-backup`), mirroring [SETUP-acer.md](../SETUP-acer.md) in reverse (**SC-13**).

## Consequences
- **Strong, layered integrity:** for the backup to be corrupted, the forced-command, the
  receive config, *and* the pre-receive hook would all have to fail — and snapshots still hold
  a 14-day floor.
- **Liveness is observable:** the audit log + a stale-snapshot check are the signal that feeds
  the deferred monitoring floor (replication state in `gr status`, PROGRESS §5).
- **New surface to operate:** a dedicated key, two systemd timers, and the `.replication` /
  `.snapshots` dirs to keep healthy. Tunables (`15 min`, `KEEP_DAILY=14`) are env-overridable.
- **Scripts are generic** (glob `/data/git/*.git`, no repo names) so they live in the public
  repo; only the *keys* and host identities are machine-local.
- Leaves room for the off-site third tier (PROGRESS §5): another controller-initiated target,
  same mechanism.
