# ADR-0000: Record architecture decisions (use ADRs)
- Status: Accepted
- Date: 2026-06-19
- Deciders: Ryan

## Context
home-fleet involves a chain of non-obvious infrastructure and security choices (which node is
authoritative, how redundancy flows, where cross-node trust sits, FIPS transport). Decided in
conversation, the *rationale* would be lost. We want a durable, reviewable record of each
decision and why — consistent with the companion git-redundancy project, which already keeps
its decisions as ADRs.

The recognized format is the **ADR** (Architecture Decision Record, Nygard 2011), commonly
written with the **MADR** Markdown template. There is no government-mandated engineering
decision format; ADR/MADR is the industry de-facto. For security-control decisions we cite the
relevant NIST 800-53 family inline rather than standing up a full SSP/POA&M at this stage.

## Decision
Keep an ADR log under `docs/adr/`, one file per decision, MADR-lite template (see
`README.md`). ADRs are immutable in substance — supersede rather than rewrite. Mirror the
conventions of git-redundancy so the two projects read the same way.

## Consequences
- The *why* is preserved and reviewable in-repo, alongside the infrastructure it governs.
- Small per-decision overhead; a supersession chain instead of edits.
- Decisions touching security controls are traceable to 800-53 families without premature RMF
  paperwork.
