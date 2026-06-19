# 2026-06-19 — kickoff: a redundant home-git fleet, topology decided

_Documents commit `862c0b5` (the initial scaffold + plan)._

## What happened

Stood up the **home-fleet** repo to catalog building out a redundant home-git fleet. The
trigger: a recycled box, **acer-arch** (1 TB HDD), is now on Tailscale (`100.65.74.108`)
alongside the existing **tenx-rltec** (`100.107.98.89`). The plan is to make acer the new
**primary** home remote and demote tenx to a **backup**, so every repo lives on two independent
boxes.

Cloned the empty `git@github.com:randallard/home-fleet.git` and scaffolded it to mirror the
companion [git-redundancy](https://github.com/randallard/git-redundancy) project: a README, a
phased `docs/PROGRESS.md`, an `docs/adr/` log, and this journal.

## The decision that took the most thought: who is the controller

We deliberated *how redundancy should flow* before writing it down, because it's a security
decision. Three options:

- **A — clients push to both servers:** doubles credential sprawl across the fleet (AC), audit
  evidence scattered and incomplete (AU), homes drift on partial failure (CP/SI).
- **B — tenx pulls from acer:** clean pattern, but hands the *less-hardened backup* read keys
  into the *crown-jewel primary* (SC) — wrong trust direction for our case.
- **C — acer pushes to tenx (acer is the controller):** clients hold one ff-only credential
  (AC), the only cross-node key is held by the node that already has the data and points *into*
  the backup (SC), one authoritative replication log (AU), and redundancy enforced by a hook on
  every accepted push (CP/SI).

Since acer is the trusted primary and tenx is the backup, the trust-direction argument settled
it: **the controller should be the primary → Option C.** Recorded as
[ADR-0002](../adr/0002-fleet-topology-acer-primary-tenx-backup-controller.md), with tenx
hardened receive-only (forced-command, ff-only, snapshots) to cover C's one downside (acer
holding a key into tenx).

Also locked the standing assurance bar
([ADR-0001](../adr/0001-assurance-standards-provable-rust-strict-ts-fisma-aligned.md)): provable
Rust, strict TS, audited, FISMA-aligned-not-certified — inherited from git-redundancy so future
fleet tooling can't drift below it.

## Next

Phase 0 of the migration plan: inventory every bare home on tenx and every client pointing at
it, and record the current FIPS/SSH transport — all *before* any change. See
[PROGRESS.md §3](../PROGRESS.md).
