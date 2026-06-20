# 2026-06-19 (3) — Phase 2 seed script + Phase 3 replication drafted

_Documents commits `3450543` (Phase 2 seed script) and `4a9a2bf` (Phase 3 replication)._

With Phase 0 done and the migration plan grounded, I prepped the two phases that *don't* need
acer to exist yet, so once acer is racked the build is mostly execution.

## Phase 2 — the seed script

`scripts/seed-acer.sh` (committed, public-safe — it globs `/data/git/*.git`, no repo names):
runs **on tenx**, mirror-pushes each home to acer over the FIPS alias, sets each home's HEAD to
match, and verifies refs ref-by-ref. Dry-run by default; idempotent; **refuses to clobber** an
acer home that already differs (so a re-run after clients start pushing can't overwrite newer
work). It fails closed if acer isn't reachable — which is exactly what the dry-run does today.

## Phase 3 — replication mechanism

The piece with the real security nuance. [ADR-0002](../adr/0002-fleet-topology-acer-primary-tenx-backup-controller.md)
had set the shape (acer controls, tenx receives, hook + sweep); the open specifics are now
pinned in **[ADR-0003](../adr/0003-replication-mechanism-hook-sweep-ff-only-snapshots.md)** and
drafted as scripts:

- **acer → tenx:** a per-home `post-receive` hook (near-real-time, never blocks the client) plus
  a **15-min sweep** that catches anything missed. Both push ff-only / never-force / never-delete
  and append to an audit log.
- **tenx hardening, three independent layers:** an SSH **forced-command** that allows only
  git-receive/upload-pack scoped to `/data/git/*.git` (rejects shells), per-home
  `denyNonFastForwards`/`denyDeletes`, and a `pre-receive` hook rejecting non-ff/deletes. For the
  backup to be corrupted, all three would have to fail.
- **snapshots:** daily `git bundle --all` per home, 14-deep — the recovery floor if a bad update
  ever slips past ff-only.

All of `scripts/replication/` is generic (glob-based), so it lives in the public repo; only the
keys and host identities are machine-local. The wiring (dedicated ed25519 key, systemd timers,
verification drill) is in **[SETUP-replication.md](../SETUP-replication.md)**.

## Workflow

These landed as proper commits (home-fleet is on the personal/public side of the commit gate),
and the seed-script commit was pushed to GitHub. The private cleanup script + inventory stay
git-ignored.

## Next

The critical path is now **Phase 1 — physically standing up acer** (you-driven; checklist ready).
After that: run the cleanup, `seed-acer.sh --apply` (Phase 2), then wire replication per
SETUP-replication.md (Phase 3) and run the verification drill.
