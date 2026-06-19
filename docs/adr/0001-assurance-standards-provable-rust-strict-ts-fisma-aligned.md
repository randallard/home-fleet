# ADR-0001: Assurance standards — provable Rust, strict TS, audited, FISMA-aligned
- Status: Accepted
- Date: 2026-06-19
- Deciders: Ryan

## Context
home-fleet starts as a docs/catalog repo but will grow operational tooling (replication
scripts, monitoring, possibly a fleet dashboard or a small Rust checker). We want a single,
stated assurance bar so that tooling doesn't drift below the standard the companion
git-redundancy project already holds. The goal, stated up front: **testable and provable
where possible, audited, with FISMA/NIST arguments weighed transparently rather than
asserted.**

The honest caveat (same as git-redundancy
[ADR-0004](https://github.com/randallard/git-redundancy/blob/main/docs/adr/0004-fisma-high-aligned-not-certified.md)):
FISMA categorizes *systems* (FIPS 199) and applies the NIST SP 800-53 **High baseline** to an
authorized boundary with an ATO and continuous monitoring. A personal home-git fleet is **not**
such a boundary, so we do **not** claim it "is FISMA High" — that is an organizational status,
not a code or infra property. We adopt the High-baseline *engineering practices*.

## Decision
Hold all home-fleet work to this bar, scaled to what each component is:

| Concern | Standard |
|---|---|
| **Provable / memory-safe code** | Rust with `#![forbid(unsafe_code)]`, functional core / imperative shell, `proptest` on pure logic, **Kani** for safety-critical invariants — the git-redundancy pattern. |
| **Strict TypeScript** (any UI) | `strict` + `noUncheckedIndexedAccess`, ESLint, Vitest/Playwright. Prefer a Rust core (Tauri/WASM) over re-implementing logic in TS. |
| **SI** (integrity) | input validation; `cargo-audit` in CI; never-force on the replication path. |
| **CM** (config mgmt) | pinned `Cargo.lock`; `cargo-deny` (license + source allowlist); SBOM; reproducible builds. |
| **SR** (supply chain) | `cargo-vet`; minimal deps; optional vendoring. |
| **AU** (audit) | append-only, timestamped logs of every mutating fleet action (replication, snapshot, cutover). |
| **AC** (access) | least privilege: single-controller credential model (ADR-0002); explicit, named hosts only. |
| **SC-13** (FIPS crypto) | enforce FIPS-approved SSH algorithms, fail-closed, host-key pinned (git-redundancy ADR-0005/0009 pattern), per node. |

**Pragmatic exception:** the unavoidable shell glue (git hooks, snapshot/bundle jobs) is kept
small, reviewed, and audited where it mutates state — not held to the Rust/Kani bar, but not
exempt from AU/CM either.

No telemetry. No network beyond the explicit, configured push/fetch/replication paths.

## Consequences
- A clear, inheritable bar: new tooling has a checklist, not a debate.
- Real, demonstrable assurance without a false compliance label; if this fleet ever entered a
  real authorization boundary, these practices map onto control evidence incrementally.
- Some ongoing cost: CI gates, locked deps, and the discipline of writing the FISMA/NIST
  argument in each relevant ADR instead of asserting it.
