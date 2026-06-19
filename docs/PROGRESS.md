# home-fleet — progress & plan

> The build log and migration plan for the redundant home-git fleet. Decisions are recorded
> as ADRs in [`docs/adr/`](adr/README.md) (read those for the authoritative *why*); this doc
> is the working overview and the phased migration plan. Companion to
> [git-redundancy](https://github.com/randallard/git-redundancy) (the `gr` tool) — see its
> `docs/PROGRESS.md` for the client-side backup story this fleet serves.

**Status:** kickoff (2026-06-19). Topology decided
([ADR-0002](adr/0002-fleet-topology-acer-primary-tenx-backup-controller.md)); migration not
yet started. acer-arch is racked and on Tailscale; tenx-rltec is the existing, working home.

**Decisions locked (see ADRs):** use ADRs ([0000](adr/0000-record-architecture-decisions.md)) ·
assurance standards — provable Rust / strict TS / audited / FISMA-aligned
([0001](adr/0001-assurance-standards-provable-rust-strict-ts-fisma-aligned.md)) · fleet
topology — **acer primary + controller, tenx hardened backup**
([0002](adr/0002-fleet-topology-acer-primary-tenx-backup-controller.md)).

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
- [ ] OS/baseline on acer: **headless Arch** (Omarchy's Arch base, server profile, no desktop;
      cf. git-redundancy ADR-0008); 1 TB drive mounted at the `/data` home root; `git` ≥ 2.38.
- [ ] FIPS-enforced `sshd` + transport, host-key pinned, SSH aliases (`acer-lan` / `acer-ts`)
      mirroring tenx (git-redundancy ADR-0009) **verbatim** — same FIPS algorithm set + host-key
      pin. New ADR only if acer's transport ends up diverging from tenx.
- [ ] `/data/git` home root created; confirm reachable over LAN (mDNS) and Tailscale.

### Phase 2 — Seed acer from tenx (one-time)
- [ ] Mirror-clone every bare home from tenx → acer (`git clone --mirror`), so acer starts as a
      faithful copy. Verify ref-by-ref (`git ls-remote` diff) per repo.
- [ ] Fix the known name mismatches during the seed (canonical home names).

### Phase 3 — Wire acer → tenx replication (the controller path)
- [ ] On tenx: install the **receive-only forced-command key** for acer; deny non-ff / force.
- [ ] On acer: `post-receive` hook that mirror-pushes the updated repo to tenx (ff-only), plus a
      scheduled full sweep to catch anything missed; replication is **audit-logged** on acer.
- [ ] Add tenx-side **snapshot/bundle** job (read-only history protection).
- [ ] Verify: push to acer → lands on tenx within the hook window; lag monitoring in place.

### Phase 4 — Cut clients over to acer
- [ ] Repoint each client's primary remote to acer (`acer-lan`/`acer-ts`); keep tenx as a
      read/restore fallback. Update each box's `gr` config (`default_remotes`, `[server]`).
- [ ] `gr push` / `gr status` green against acer on every client.

### Phase 5 — Demote tenx & harden
- [ ] tenx stops accepting client writes (receive-only from acer); confirm no client still
      writes to it directly.
- [ ] Document restore drill: acer down → repoint clients to tenx, promote tenx, rebuild acer.

### Phase 6 — Verify & drill
- [ ] **Contingency drill (CP):** simulate acer loss, restore from tenx end-to-end, measure.
- [ ] Replication-lag + snapshot-freshness monitoring alerting.

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
- [x] **Replication mechanism** → **both.** A `post-receive` hook (fires on every accepted push,
      near-real-time) **and** a scheduled full sweep (catches anything the hook missed). Still to
      pin down in testing: exact ff-only enforcement on tenx + snapshot cadence/retention.
- [~] **Monitoring** → left open, but the **decided floor:** replication state (per-repo lag /
      "is this backed up to tenx?") surfaces in the **`gr status` table** at minimum. Anything
      richer (a dedicated checker, a `home-fleet` crate, alerting) is deferred.
- [ ] **Off-site tier** — a third, off-site copy later (encrypted bundles to cloud)? Out of
      scope for this migration; note as a future ADR.
- [x] ~~**omarchy-setup publication**~~ → resolved: https://github.com/randallard/omarchy-setup
      (home-fleet README link updated).
