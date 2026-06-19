# ADR-0002: Fleet topology — acer primary + replication controller, tenx hardened backup
- Status: Accepted
- Date: 2026-06-19
- Deciders: Ryan

## Context
We have two home boxes and want every repo on both, so losing either loses no committed work:

- **acer-arch** (`100.65.74.108`) — recycled box, 1 TB HDD, **new** and treated as the trusted
  primary.
- **tenx-rltec** (`100.107.98.89`) — the **existing** home (`/data/git/*.git`), to become "a
  bit of redundancy."

Clients already back up via [`gr`](https://github.com/randallard/git-redundancy), which can
push to multiple remotes and fail over between them. The question is *how redundancy flows*, and
it is a security decision as much as an operational one. Three topologies were weighed
(NIST 800-53 families in parentheses):

**A. Clients push to both servers.** Every client holds credentials to *both* acer and tenx and
pushes to each.
- ✓ No server-to-server trust path; each server only ever receives.
- ✗ **(AC)** Credential sprawl doubles across the fleet — every laptop holds keys to both
  homes; a stolen client key reaches both. **(AU)** "Did the backup happen?" evidence is
  scattered across clients and silently incomplete when a client's second push fails.
  **(SI/CP)** The two homes drift whenever one push fails; redundancy is hoped-for client
  behavior, not enforced.

**B. tenx pulls from acer** (the **backup** is the initiator).
- ✓ Pull-based backup is a clean classic pattern; acer needs no credential to tenx.
- ✗ **(SC, the decisive flaw)** It hands the **less-hardened backup node read access into the
  crown-jewel primary**. If tenx is compromised, the attacker has read keys into acer. You only
  want pull-from-backup when the backup is the *more* trusted node — which is the opposite of
  our case.

**C. acer pushes to tenx** (the **primary** is the controller). acer initiates and governs
replication; clients talk only to acer.
- ✓ **(AC)** Clients hold exactly **one** push credential (to acer), fast-forward-only — minimal
  fleet-wide credential surface. **(SC)** The only cross-node credential is held by acer (which
  already holds all the data), pointing *into* the backup — near-zero incremental exposure, and
  tenx never gets keys into acer. **(AU)** One authoritative node logs every replication event.
  **(CP/SI)** Replication is a deterministic property of acer's lifecycle (a hook fires on every
  accepted push), so "if it's on acer, it's on tenx" is enforceable, and the homes converge
  transactionally.
- ✗ acer holds a write key into tenx — if acer is compromised, tenx is reachable, and a bad
  push could corrupt the backup. Mitigable (below).

Because acer is the **more trusted / authoritative** node and tenx is the backup, the
trust-direction argument (SC) is decisive: the controller should be the primary.

## Decision
**Topology C: acer-arch is the primary home *and* the replication controller; tenx-rltec is a
hardened, receive-only backup.**

- **Clients** push only to acer (one remote/credential, ff-only via `gr`); they *may* fall back
  to **read/restore** from tenx, but never write to it directly.
- **acer → tenx replication** is controller-initiated: a `post-receive` hook mirror-pushes each
  accepted update to tenx (fast-forward only), backed by a scheduled full sweep; every
  replication action is **audit-logged on acer** (AU).
- **tenx is hardened receive-only:** a forced-command SSH key restricted to `git-receive-pack`,
  **never-force / ff-only** (carrying gr's no-force principle onto the replication path), plus
  periodic **read-only snapshots/bundles** so a malicious or buggy mirror push cannot destroy
  backup history (ransomware-style defense).
- FIPS-enforced, host-key-pinned SSH transport per node (git-redundancy ADR-0005/0009 pattern).

## Consequences
- **Security posture is strongest of the three:** least client-side credential surface (AC),
  correct trust direction (SC), single authoritative audit trail (AU), enforceable redundancy
  (CP/SI). The full reasoning lived in the kickoff deliberation and is preserved here.
- **New obligations:** acer holds a key into tenx → tenx must enforce receive-only + ff-only +
  snapshots, and we must **monitor replication lag** (a stale backup is a silent failure).
- **Mirrors the known client-side-vs-mandatory tension** from git-redundancy ADR-0005:
  client-side ff-only is a strong default but overridable; the tenx-side forced-command is the
  server-side, fail-closed counterpart.
- Mechanism specifics (hook vs. sweep cadence, exact ff-only enforcement, snapshot
  retention) are deferred to a follow-up ADR once tested — see PROGRESS.md §5.
- Leaves room for a later **off-site third tier** (encrypted bundles) without revisiting this
  decision: that would be another controller-initiated push target.
