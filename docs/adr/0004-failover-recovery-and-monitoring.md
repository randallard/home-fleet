# ADR-0004: Failover, recovery, and the monitoring floor
- Status: Accepted
- Date: 2026-06-19
- Deciders: Ryan

## Context
Once acer is the primary ([ADR-0002](0002-fleet-topology-acer-primary-tenx-backup-controller.md))
and tenx is a hardened, replicated backup ([ADR-0003](0003-replication-mechanism-hook-sweep-ff-only-snapshots.md)),
two operational questions remain (Phases 5–6): what happens when **acer is lost**, and how do we
know the backup is actually keeping up. The fleet is a personal, two-box setup — a single user,
no HA requirement — so the answer should favor *simple and certain* over *automatic*.

## Decision

**Failover is manual, not automatic.** There is no auto-failover/quorum. If acer is down, the
user runs `promote-tenx.sh` on each client to repoint `data*` back at the preserved
`tenx-lan`/`tenx` restore remotes, and flips gr's `[server].aliases` to tenx. Work keeps being
backed up — to tenx — until acer returns. Rationale: with one operator and no uptime SLA,
automatic failover adds moving parts and split-brain risk for no real benefit; an explicit human
decision is safer and the outage window is acceptable.

**Recovery reuses the migration scripts (no new machinery).** Rebuilding acer after a loss is
the same path as the original build, with tenx now the source of truth:
`SETUP-acer.md` (stand up) → `seed-acer.sh` (re-seed **from tenx**) → `SETUP-replication.md`
(re-wire acer→tenx) → `cutover-client.sh` (fail clients back to acer). Because the seed and
replication scripts are direction-stable and idempotent, recovery is just re-running them.

**Demoting tenx is by convention + integrity, not lockout.** After cutover, no client targets
tenx for writes (verified: `data*` point at acer; tenx kept only as a restore remote). tenx's
homes already reject non-ff/deletes ([ADR-0003](0003-replication-mechanism-hook-sweep-ff-only-snapshots.md)),
so integrity holds regardless of writer; the operator's own key retains admin access (needed,
and needed for promotion). We do **not** lock tenx to acer-only at the cost of the operator's
access.

**Monitoring floor — a healthcheck, exit-code first.** `fleet-healthcheck.sh` (run on tenx via a
timer) checks two things per home: **replication lag** (refs acer has that tenx is missing) and
**snapshot freshness** (newest bundle age). It exits non-zero on any drift. That exit code is the
alerting primitive now, and the same signal is what later surfaces in the `gr status` table
(PROGRESS §5). Anything richer (push alerting, a dashboard) stays deferred.

**The contingency drill is a periodic, scheduled exercise.** Phase 6 isn't one-and-done:
simulate acer loss, promote tenx, confirm no committed work is lost, measure time-to-restore,
then fail back — on a recurring basis, so recovery is known-good rather than hoped-for (CP).

## Consequences
- **Simple and certain:** no auto-failover machinery to misfire; recovery is re-running known
  scripts; a single healthcheck gives a yes/no on backup health.
- **Operator-in-the-loop:** an acer outage needs a human to run `promote-tenx.sh` — accepted for
  a personal fleet; documented in `SETUP-failover.md`.
- **Drill discipline required:** the guarantees are only real if the drill is actually run; left
  un-exercised, recovery decays. Scheduling it is part of the decision.
- Monitoring is intentionally minimal now; the healthcheck exit code is the seam to grow from.
