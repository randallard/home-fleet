# Phases 5–6 — demote tenx, failover/recovery, drill & monitoring

Operational runbook for after the migration is live ([ADR-0004](adr/0004-failover-recovery-and-monitoring.md)):
keep tenx as a clean backup (Phase 5), know exactly how to survive an acer loss and rebuild
(Phase 6 drill), and watch that the backup is actually keeping up (monitoring floor).

---

## Phase 5 — demote tenx & confirm it's a clean backup

1. **No client writes to tenx directly.** After Phase 4, every client's `data*` points at acer;
   tenx is kept only as a `tenx-lan`/`tenx` restore remote (not in gr's `default_remotes`).
   Confirm on each client:
   ```bash
   for r in ~/Development/*/; do
     git -C "$r" remote get-url data 2>/dev/null | grep -q acer || echo "CHECK: $r data not on acer"
   done
   ```
2. **Integrity already enforced.** tenx homes reject non-ff/deletes (Phase 3 hardening), and the
   only automated writer is acer's receive-only key. The operator's own key keeps admin access
   (needed for promotion) — we deliberately do **not** lock tenx to acer-only.
3. **Snapshots running.** Confirm the `tenx-snapshot.timer` is active and bundles are fresh
   (`fleet-healthcheck.sh`, below).

---

## Phase 6a — the failover drill (run it regularly, not once)

Goal: prove that losing acer loses **no committed work**, and measure time-to-restore.

1. **Simulate acer loss** — stop acer (or block the alias).
2. **Promote tenx** on each client:
   ```bash
   ./scripts/promote-tenx.sh            # dry-run
   ./scripts/promote-tenx.sh --apply    # data* -> tenx restore remotes
   ```
   Set gr `[server].aliases = ["tenx-lan","tenx"]`, then `gr push` — work now backs up to tenx.
3. **Verify no data loss** — every commit that was on acer is present on tenx (it was, via
   replication); new work since the outage is now going to tenx.
4. **Rebuild acer** (the recovery loop reuses the migration scripts, tenx as source of truth):
   - `SETUP-acer.md` — stand up acer (or a replacement box).
   - `seed-acer.sh --apply` — **re-seed acer from tenx**.
   - `SETUP-replication.md` — re-wire acer→tenx replication.
   - `cutover-client.sh --apply` — fail clients back to acer; restore gr `[server].aliases`.
5. **Measure** — record time-to-restore (RTO) and confirm zero committed-work loss. Note anything
   that slowed it down; fix the runbook.

> Do this on a schedule (e.g. quarterly). Un-exercised recovery decays — the guarantee is only as
> good as the last drill (ADR-0004, CP).

## Phase 6b — monitoring floor

`fleet-healthcheck.sh` runs **on tenx** and, per home, flags **replication lag** (refs acer has
that tenx is missing) and **stale snapshots** (newest bundle older than `SNAP_MAX_AGE_H`, default
36h). It exits non-zero on any issue.

- Manual: `./scripts/fleet-healthcheck.sh`
- Scheduled (systemd, alerts via the non-zero exit / your notifier):
  ```ini
  # fleet-healthcheck.service
  [Service]
  Type=oneshot
  ExecStart=%h/path/to/fleet-healthcheck.sh
  ```
  ```ini
  # fleet-healthcheck.timer  → hourly
  [Timer]
  OnCalendar=hourly
  Persistent=true
  [Install]
  WantedBy=timers.target
  ```

This exit-code signal is the seam for the deferred work: surface the same per-repo "backed up?
how stale?" state in the **`gr status` table** (PROGRESS §5). Richer alerting (push/dashboard)
stays out of scope.

---

## Quick reference — the recovery loop

```
acer lost ─▶ promote-tenx.sh (clients → tenx) ─▶ keep working (backup = tenx)
          ─▶ rebuild acer: SETUP-acer ▶ seed-acer ▶ SETUP-replication ▶ cutover-client
          ─▶ back to steady state (clients → acer ─replicate▶ tenx)
```
