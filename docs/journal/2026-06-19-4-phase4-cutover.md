# 2026-06-19 (4) — Phase 4 client cutover prepped

_Documents commit `9e74016`._

With Phases 1–3 drafted, prepped the next phase that still needs no acer: cutting clients over
from tenx to acer.

## The cutover

`scripts/cutover-client.sh` (generic, public-safe) runs **on each client** and, for every
working copy with a backup remote: preserves the current tenx target as `tenx-lan`/`tenx`
(restore-only), then points `data-lan`/`data` at acer (`acer-lan`/`acer-ts:/data/git/<name>.git`).
`<name>` is derived from the existing remote URL, so it follows the canonical home name the
cleanup settled. Dry-run by default, idempotent, and reversible (the tenx remotes are kept).

The dry-run on tenx confirmed the mechanics — and incidentally showed *why ordering matters*:
one repo still derives its old (pre-cleanup) home name, so the cutover must run after the
canonicalization. The phase ordering (cutover only once Phase 3 is verified) enforces that.

`docs/SETUP-cutover.md` wraps it with the operational care this step needs: **start only after
replication is verified** (otherwise new pushes wouldn't be backed up), a **canary-first** order
(one repo → one client → the rest), the `gr` config change (`default_remotes`/`transport`/
`[server].aliases` → acer, which also fixes tenx's `?` lifecycle column), a verification
round-trip (push to acer → appears on tenx via replication; restore path still works), and a
rollback recipe.

## State

home-fleet now carries the full migration design: Phase 0 done, Phases 1–4 planned and scripted
(setup checklists + seed/replication/cutover scripts + ADRs 0000–0003). The private cleanup
script and inventory stay git-ignored.

## Next

Phases 5–6 (demote/harden tenx, then the contingency drill) are short and mostly follow from the
earlier scripts. The real next step remains physical: **stand up acer (Phase 1)**, then execute.
