# Architecture Decision Records (ADRs)

This directory records the significant decisions for **home-fleet**, one file per decision,
with the context and consequences — so the *why* survives, not just the *what*. Same form and
conventions as the companion [git-redundancy](https://github.com/randallard/git-redundancy)
project's ADRs.

## What this is

The recognized practice is the **ADR — Architecture Decision Record** (Michael Nygard, 2011),
commonly written with the **MADR** (Markdown Any Decision Records) template. We use a MADR-lite
form below. For *security-control* decisions specifically, NIST RMF uses heavier system-level
artifacts (SSP, POA&M); ADRs are the right grain here, and where a decision touches a control
we cite the relevant NIST 800-53 family inline.

## Conventions

- Files: `NNNN-kebab-title.md`, zero-padded, monotonically increasing.
- **Immutable in substance:** to change a decision, write a *new* ADR that supersedes the old
  one and flip the old one's status to `Superseded by ADR-XXXX`. Don't rewrite history.
- Status values: `Proposed` · `Accepted` · `Superseded` · `Deprecated`.

## Template

```markdown
# ADR-NNNN: <title>
- Status: Proposed | Accepted | Superseded by ADR-XXXX
- Date: YYYY-MM-DD
- Deciders: <names>

## Context
<forces at play, constraints, what makes this non-obvious>

## Decision
<what we chose, stated plainly>

## Consequences
<results, good and bad; what this commits us to>
```

## Index

| ADR | Title | Status |
|-----|-------|--------|
| [0000](0000-record-architecture-decisions.md) | Record architecture decisions (use ADRs) | Accepted |
| [0001](0001-assurance-standards-provable-rust-strict-ts-fisma-aligned.md) | Assurance standards: provable Rust, strict TS, audited, FISMA-aligned | Accepted |
| [0002](0002-fleet-topology-acer-primary-tenx-backup-controller.md) | Fleet topology: acer primary + replication controller, tenx hardened backup | Accepted |
| [0003](0003-replication-mechanism-hook-sweep-ff-only-snapshots.md) | Replication mechanism: post-receive hook + sweep, ff-only, snapshotted | Accepted |
| [0004](0004-failover-recovery-and-monitoring.md) | Failover (manual), recovery via the migration scripts, and the monitoring floor | Accepted |
