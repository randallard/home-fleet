# 2026-06-19 (5) — Phases 5–6 prepped: failover, recovery drill, monitoring

_Documents commit `e9ec881`._

Finished scripting the migration end-to-end by prepping the operational tail: demoting tenx,
surviving an acer loss, and watching that the backup keeps up. The one real decision here got an
ADR.

## The decision (ADR-0004): manual failover

For a personal, single-operator, two-box fleet, **automatic failover isn't worth it** — it adds
split-brain risk for no uptime requirement. So: failover is a human running `promote-tenx.sh`,
and **recovery reuses the migration scripts** (rebuild acer = `SETUP-acer` ▸ `seed-acer` ▸
`SETUP-replication` ▸ `cutover-client`, with tenx now the source of truth). "Demoting" tenx is by
convention + the Phase 3 integrity hardening, not by locking out the operator's own key.

## The scripts

- **`promote-tenx.sh`** — failover: repoints a client's `data*` back to the `tenx-lan`/`tenx`
  restore remotes that cutover preserved, so work keeps being backed up (to tenx) while acer is
  down. Inverse of cutover; reversible.
- **`fleet-healthcheck.sh`** — the monitoring floor: on tenx, per home, flags replication lag
  (refs acer has that tenx lacks) and stale snapshots, exiting non-zero. Caught a real bug while
  testing — under `set -euo pipefail` an unreachable peer killed the script instead of warning;
  fixed so it degrades gracefully (the dry test on tenx today correctly warns "primary
  unreachable, no snapshots yet" and exits 1).

`SETUP-failover.md` ties it together: the Phase 5 demote checks, the Phase 6 **contingency drill**
(run regularly — simulate acer loss, promote tenx, verify zero committed-work loss, rebuild,
measure RTO), and the healthcheck timer. Both scripts are generic/glob-based, so they're public.

## State

The whole migration is now **designed and scripted, Phases 0–6**, with ADRs 0000–0004. Phase 0 is
done; everything else waits on the one physical step. The private cleanup script + inventory stay
git-ignored.

## Next

Nothing left to design — the next move is hands-on: **stand up acer (Phase 1)**, then execute the
scripted phases in order. Optional future polish: fold `fleet-healthcheck`'s signal into the
`gr status` table (§5).
