# home-fleet — progress & plan

> The build log and migration plan for the redundant home-git fleet. Decisions are recorded
> as ADRs in [`docs/adr/`](adr/README.md) (read those for the authoritative *why*); this doc
> is the working overview and the phased migration plan. Companion to
> [git-redundancy](https://github.com/randallard/git-redundancy) (the `gr` tool) — see its
> `docs/PROGRESS.md` for the client-side backup story this fleet serves.

**Status:** designed end-to-end (2026-06-19). All decisions recorded (ADRs 0000–0004) and
**every phase (0–6) is planned & scripted**: Phase 0 (inventory) done; Phase 1
([SETUP-acer.md](SETUP-acer.md)); Phase 2 ([seed-acer.sh](../scripts/seed-acer.sh)); Phase 3
([SETUP-replication.md](SETUP-replication.md) + `scripts/replication/`); Phase 4
([SETUP-cutover.md](SETUP-cutover.md) + [cutover-client.sh](../scripts/cutover-client.sh)); Phases
5–6 ([SETUP-failover.md](SETUP-failover.md) + `promote-tenx.sh`/`fleet-healthcheck.sh`). The
`tenx-cleanup` script is dry-run-clean and awaiting `--apply`. **The only remaining blocker is
physically standing up acer (Phase 1);** after that it's execution. acer-arch is racked and on
Tailscale but not yet a home server; tenx-rltec is the existing, working home.

**Decisions locked (see ADRs):** use ADRs ([0000](adr/0000-record-architecture-decisions.md)) ·
assurance standards — provable Rust / strict TS / audited / FISMA-aligned
([0001](adr/0001-assurance-standards-provable-rust-strict-ts-fisma-aligned.md)) · fleet
topology — **acer primary + controller, tenx hardened backup**
([0002](adr/0002-fleet-topology-acer-primary-tenx-backup-controller.md)) · replication mechanism —
**hook + sweep, ff-only, snapshotted** ([0003](adr/0003-replication-mechanism-hook-sweep-ff-only-snapshots.md)) ·
failover/recovery/monitoring — **manual promotion, recovery via the migration scripts, healthcheck floor**
([0004](adr/0004-failover-recovery-and-monitoring.md)).

---

## 1. Goal

Every repo I care about should live on **two independent home boxes**, so the loss of either
one loses no committed work — without trusting a cloud and without manual copy rituals. The
new 1 TB **acer-arch** becomes the authoritative **primary** home; the existing **tenx-rltec**
becomes a **backup** that only ever *receives*. Clients keep using
[`gr`](https://github.com/randallard/git-redundancy) exactly as before; only their remote
target moves.

Non-goals (for now): a hosting UI, multi-user access, off-site/cloud replication (a possible
later tier), automated failover of *clients* between nodes.

---

## 2. Topology (decided — ADR-0002)

```
        push (ff-only, gr)                 mirror (post-receive hook + scheduled sweep)
client ───────────────────────▶  acer-arch  ───────────────────────────────────▶  tenx-rltec
 (one remote: the controller)   PRIMARY/CTRL   (acer holds the only cross-node key)   BACKUP
                                /data/git/*.git                                   /data/git/*.git
                                                                                  receive-only + snapshots
```

- **acer is the controller**: it initiates and governs replication. Clients hold exactly one
  push credential (to acer); tenx holds none into acer. Security rationale (AC least-privilege,
  trust direction / SC, centralized AU, contingency / CP) is in ADR-0002.
- **tenx is receive-only**: a forced-command SSH key restricted to `git-receive-pack`,
  **fast-forward only / never force** (carrying gr's no-force principle onto the replication
  path), plus periodic read-only snapshots/bundles so a bad mirror push can't destroy backup
  history.
- **Read/restore failover preserved**: clients *may* fall back to read from tenx (like gr's
  `data-lan`/`data`), but normal writes go only to acer.

---

## 3. Migration plan (phased)

Each phase is independently reversible and leaves the fleet in a working state. We do **not**
decommission anything on tenx until acer is proven and replicating.

### Phase 0 — Inventory & baseline *(do first, no changes)*
- [x] Enumerate bare homes on tenx + clients pointing at them — done 2026-06-19 (read-only).
- [ ] Record current SSH transport (tenx aliases, host-key pin, FIPS algorithm set) — see
      git-redundancy [ADR-0009](https://github.com/randallard/git-redundancy/blob/main/docs/adr/0009-ssh-transport-aliases-mdns-hostkey-pinned.md)
      / SETUP.md; dump acer's to match in Phase 1.
- [x] Note name mismatches / wiring gaps to fix in flight (below).

**Inventory (2026-06-19): the fleet is small — ~2.6 GB across all homes**, trivial against
acer's 1 TB, so the seed is fast and headroom is enormous. **Decision:** every current home plus
the personal repos joins the fleet (all get an acer home). The repos split into:

- **Public / personal** (named here): `omarchy-setup`,
  [`omarchy-setup-public`](https://github.com/randallard/omarchy-setup), `home-fleet`,
  [`git-redundancy`](https://github.com/randallard/git-redundancy).
- **Private** (work; **not named in this public doc** — kept in local `docs/inventory.private.md`,
  which is git-ignored): several internal repos that hold the **bulk of the bytes**. The
  migration treats them like any other home; their identities just stay out of the public
  catalog.

**Wiring gaps / cleanup to settle before seeding acer** (full per-repo detail in the private
notes):
- **omarchy-setup name split** — the working copy pushes to a differently-named home than the
  one holding its latest commit. Canonicalize to `omarchy-setup.git`, repoint the working remote,
  retire the stray home + a leftover non-bare backup dir.
- **Follow-up — re-export the public omarchy-setup repo.** The public
  [`omarchy-setup`](https://github.com/randallard/omarchy-setup) snapshot was scrubbed/exported
  from the *older* working tip; the canonical home is **2 commits ahead** (the latest is a
  zscaler-root-cert update worth having public). After the working copy is fast-forwarded,
  re-run the genericize/scrub from the new tip and refresh the public repo *before its first
  push* (or, if already pushed, as a follow-up commit).
- **git-redundancy** — its home is orphaned (the working copy has no `data` remote; it backs up
  to GitHub only). Re-wire to acer as part of the seed.
- **Private repos** — home wiring varies (one has no home yet); reconcile during the seed.
  Details in `docs/inventory.private.md`.

### Phase 1 — Stand up acer as a home server
> Step-by-step checklist (mirrors tenx's transport verbatim): **[SETUP-acer.md](SETUP-acer.md)**.

- [ ] OS/baseline on acer: **headless Arch** (Omarchy's Arch base, server profile, no desktop;
      cf. git-redundancy ADR-0008); 1 TB drive mounted at the `/data` home root; `git` ≥ 2.38.
- [ ] FIPS-enforced `sshd` + transport, host-key pinned, SSH aliases (`acer-lan` / `acer-ts`)
      mirroring tenx (git-redundancy ADR-0009) **verbatim** — same FIPS algorithm set + host-key
      pin. New ADR only if acer's transport ends up diverging from tenx.
- [ ] `/data/git` home root created; confirm reachable over LAN (mDNS) and Tailscale.

### Phase 2 — Seed acer from tenx (one-time)
> Script (run **on tenx**, after Phase 1 + cleanup): **[scripts/seed-acer.sh](../scripts/seed-acer.sh)**
> — globs `/data/git/*.git`, mirror-pushes each to acer over the FIPS alias, sets each home's
> HEAD to match, verifies refs. Dry-run by default; **never clobbers** a divergent acer home.

- [ ] Name mismatches are already resolved by the cleanup step (Phase 0), so the seed just
      copies the clean, canonical set — no in-flight renaming needed.
- [ ] Run `seed-acer.sh --apply` once acer is up (Phase 1) and `tenx-cleanup.sh --apply` has run.
- [ ] Confirm the summary shows every home **seeded + verified** (ref sets identical), then
      spot-check a `git ls-remote acer-lan:/data/git/<repo>.git`.

### Phase 3 — Wire acer → tenx replication (the controller path)
> Mechanism decided in **[ADR-0003](adr/0003-replication-mechanism-hook-sweep-ff-only-snapshots.md)**;
> step-by-step in **[SETUP-replication.md](SETUP-replication.md)**; scripts in
> [`scripts/replication/`](../scripts/replication/) (all generic/public-safe).

- [ ] On tenx: install the **receive-only forced-command key** for acer (`tenx-receive-only-command.sh`),
      and harden every home — `denyNonFastForwards` + `denyDeletes` + `pre-receive` (`tenx-harden-homes.sh --apply`).
- [ ] On acer: `post-receive` hook (`acer-post-receive`) in each home + a **15-min sweep**
      (`acer-sweep.sh` via systemd timer); ff-only, never-force, **audit-logged** on acer.
- [ ] tenx-side **daily snapshots** (`tenx-snapshot.sh`, 14-deep bundles) for read-only history protection.
- [ ] Verify: push to acer → lands on tenx within the hook window; force/shell attempts rejected;
      snapshot bundles present. (Lag/freshness becomes the monitoring signal — PROGRESS §5.)

### Phase 4 — Cut clients over to acer
> Step-by-step (canary first, per client): **[SETUP-cutover.md](SETUP-cutover.md)**; remote
> repointing via [`scripts/cutover-client.sh`](../scripts/cutover-client.sh) (generic, dry-run,
> reversible). **Start only after Phase 3 replication is verified.**

- [ ] Per client, run `cutover-client.sh --apply`: preserves the tenx targets as `tenx-lan`/`tenx`
      (restore-only) and points `data-lan`/`data` at acer.
- [ ] Update each box's `gr` config: `default_remotes`/`transport` → acer, `[server].aliases =
      ["acer-lan","acer-ts"]` (also fixes tenx's `?` lifecycle column).
- [ ] `gr push` / `gr status` green against acer on every client, and each push round-trips to
      tenx via replication. Restore path (`tenx*` remotes) still works.

### Phase 5 — Demote tenx & harden
> Runbook: **[SETUP-failover.md](SETUP-failover.md)** (Phase 5 section); decisions in
> **[ADR-0004](adr/0004-failover-recovery-and-monitoring.md)**.

- [ ] Confirm no client writes to tenx directly (every `data*` points at acer; tenx kept only as
      a `tenx*` restore remote). Integrity already enforced by Phase 3 hardening.
- [ ] `tenx-snapshot.timer` active and bundles fresh (`fleet-healthcheck.sh`).

### Phase 6 — Verify & drill
> Drill + monitoring: **[SETUP-failover.md](SETUP-failover.md)** (Phase 6); scripts
> [`promote-tenx.sh`](../scripts/promote-tenx.sh) + [`fleet-healthcheck.sh`](../scripts/fleet-healthcheck.sh).

- [ ] **Contingency drill (CP), run regularly:** simulate acer loss → `promote-tenx.sh` (clients →
      tenx) → verify zero committed-work loss → rebuild acer by re-running the migration scripts
      (`SETUP-acer` ▸ `seed-acer` ▸ `SETUP-replication` ▸ `cutover-client`) → measure RTO.
- [ ] **Monitoring floor:** `fleet-healthcheck.sh` on a timer (replication lag + snapshot
      freshness, exit-code alerting); later surface the same signal in `gr status` (§5).

---

## 4. Standards (decided — ADR-0001)

Any tooling added here (replication scripts, monitoring, a future fleet dashboard) inherits
git-redundancy's posture: provable/testable Rust (functional core, `proptest` + Kani,
`#![forbid(unsafe_code)]`), strict TypeScript for any UI, audit logging, supply-chain gates
(`cargo-deny`/`-audit`/`-vet`, SBOM), and FISMA-High *alignment* (not a certification claim)
with NIST 800-53 families cited inline in ADRs. Shell glue (hooks, snapshot jobs) is the
pragmatic exception — kept small, reviewed, and audited where it mutates state.

---

## 5. Open decisions / questions

- [x] **acer transport** → **matches tenx's FIPS setup.** acer runs **headless Arch** (Omarchy's
      Arch base, server profile, no desktop), so it mirrors tenx's FIPS-enforced `sshd` /
      SSH-alias / host-key-pinned transport (git-redundancy
      [ADR-0009](https://github.com/randallard/git-redundancy/blob/main/docs/adr/0009-ssh-transport-aliases-mdns-hostkey-pinned.md))
      verbatim. (→ confirm the exact `sshd` algorithm set when acer is configured; a new ADR
      only if it ends up diverging.)
- [x] **Replication mechanism** → **pinned in [ADR-0003](adr/0003-replication-mechanism-hook-sweep-ff-only-snapshots.md)**:
      `post-receive` hook + 15-min sweep (both); ff-only enforced three ways on tenx (forced-command
      + `denyNonFastForwards`/`denyDeletes` + `pre-receive`); daily 14-deep snapshot bundles; audit
      on acer. Scripts drafted in [`scripts/replication/`](../scripts/replication/); validation
      happens when acer is up (Phase 3).
- [x] **Monitoring** → floor in place. **`gr status` now shows a `Bkp` column** — per-repo backup
      *presence* (`ok`/`miss`/`?`) via a `[backup]` server block (git-redundancy ADR-0015). The
      deeper signal — replication **lag** + **snapshot freshness** — stays in `fleet-healthcheck.sh`
      on tenx (it can see the filesystem; a client can't honestly observe it). Still deferred:
      richer alerting (push/dashboard).
- [ ] **Off-site tier** — a third, off-site copy later (encrypted bundles to cloud)? Out of
      scope for this migration; note as a future ADR.
- [x] ~~**omarchy-setup publication**~~ → resolved: https://github.com/randallard/omarchy-setup
      (home-fleet README link updated).
