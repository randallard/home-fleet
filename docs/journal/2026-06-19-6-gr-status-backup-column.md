# 2026-06-19 (6) — the monitoring floor lands in `gr status`

_Documents home-fleet commit `7ed346d` and git-redundancy commit `b7e216e` (ADR-0015)._

Folded the backup signal into `gr status` — the deferred §5 monitoring item.

## What changed in the tool

`gr status` gained a **`Bkp` column** (git-redundancy ADR-0015): with a `[backup]` server block
configured (aliases → tenx), each repo shows `ok` (its home is on the backup too), `miss` (red — a
redundancy gap), or `?` (backup unreachable). It reuses the existing home-listing machinery — one
cheap extra SSH listing, joined on the same home-name identity the lifecycle column uses — and
`--json` carries a per-repo `backup` field; `--offline` skips it.

## The boundary I kept

`gr` shows **presence**, not lag. A client running `gr status` can't honestly observe ref-level
replication lag or snapshot age across two servers, so that stays in `fleet-healthcheck.sh` on
tenx, which can see the filesystem. The split is deliberate and written into ADR-0015: `gr`
answers "is each repo *on* the backup?"; the on-tenx healthcheck answers "how far behind / how
stale?". Together they are the monitoring floor.

## Quality

Implemented across config → io → render → cli → json with tests; 58 tests green, clippy clean,
the `gr` binary reinstalled. Verified live: with `[backup]` set and acer down, the column renders
`?` for every repo (graceful degradation), exactly as intended.

## State

§5 monitoring moves to done (floor). The home-fleet migration remains designed end-to-end
(Phases 0–6); the only blocker is still physically standing up acer.
