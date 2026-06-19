# home-fleet

A catalog of the personal **redundant git-hosting fleet** — the home servers that hold the
bare "home" remotes, how they replicate for redundancy, and the decisions behind the build.
This repo is the *map and logbook* for the construction; the tooling that operates the fleet
lives in companion projects.

> Status: kickoff. Standing up a second home server (**acer-arch**, 1 TB) as the new
> **primary** home remote, with the existing server (**tenx-rltec**) demoted to a hardened
> **backup** — so every repo lives on two independent boxes. See
> [docs/PROGRESS.md](docs/PROGRESS.md) for the plan and current state.

## The fleet

| Node | Tailscale | Role | Notes |
|---|---|---|---|
| **acer-arch** | `100.65.74.108` | **primary** home remote + replication **controller** | recycled box, 1 TB HDD, headless Arch |
| **tenx-rltec** | `100.107.98.89` | **backup** (receive-only, snapshotted) | existing home (`/data/git`), TB drive |

Redundancy flows from the controller: clients push to **acer** (the authoritative copy), and
acer mirrors each accepted update to **tenx**. The *why* — and the security trade-offs weighed
the NIST 800-53 way — is recorded in
[ADR-0002](docs/adr/0002-fleet-topology-acer-primary-tenx-backup-controller.md).

## Companion projects

- **[git-redundancy](https://github.com/randallard/git-redundancy)** — the `gr` CLI that keeps
  local working copies backed up to their bare home remotes (status table, safe easy-push,
  `create`/`clone`/`sync` lifecycle). This is the tool the fleet is built *for*.
- **[omarchy-setup](https://github.com/randallard/omarchy-setup)** — the Omarchy (Arch-based)
  desktop/server setup used on both ends (see git-redundancy
  [ADR-0008](https://github.com/randallard/git-redundancy/blob/main/docs/adr/0008-os-omarchy-on-both-ends.md)).

## Standards

Everything built here carries the same assurance posture as git-redundancy
([ADR-0001](docs/adr/0001-assurance-standards-provable-rust-strict-ts-fisma-aligned.md)):
**testable and provable Rust** (functional core, `proptest` + Kani, `#![forbid(unsafe_code)]`),
**strict TypeScript** where a UI is involved, **audited** (append-only logs, `cargo-deny`/
`-audit`/`-vet`, SBOM), and **FISMA-High–aligned, not certified** — with FISMA/NIST arguments
weighed transparently in the ADRs rather than asserted.

## Layout

```
docs/
  PROGRESS.md        # the plan + current state (start here)
  adr/               # Architecture Decision Records (the durable "why")
  journal/           # dated narrative worklog
```
