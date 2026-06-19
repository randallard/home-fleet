# 2026-06-19 (2) — decisions firmed, Phase 0 inventory, and a cleanup script

_Also documents commit `862c0b5` (this progress landed alongside the scaffold in the first
commit; this entry is the narrative for the work done after the kickoff)._

## Decisions firmed up

The open questions from kickoff got answers (recorded in PROGRESS.md §5):

- **acer = headless Arch**, mirroring tenx's FIPS-enforced SSH transport **verbatim** — same
  algorithm set, host-key pin. A new transport ADR only if it ends up diverging.
- **Replication = both** — a `post-receive` hook (near-real-time, fires on every accepted push)
  **and** a scheduled full sweep (catches anything missed).
- **Monitoring = deferred, with a floor:** replication state surfaces in the `gr status` table at
  minimum; anything richer comes later.
- **Companion published:** the Omarchy setup repo is now on GitHub (scrubbed of its work ties in
  its own repo), and the README link is live.

## Phase 0 — inventory (read-only)

Surveyed the existing homes. The fleet is **small (~2.6 GB total)** — trivial against acer's
1 TB, so the seed itself is a non-event. The value was catching the *mess* before copying it
onto a fresh box:

- A **name split**: one repo's working copy pushes to a differently-named home than the one
  holding its latest commit (a clean fast-forward, the misnamed one a strict subset).
- An **orphaned home**: `git-redundancy`'s home is current, but the working copy had no local
  `data` remote (it backs up to GitHub).
- A repo with **no home yet**.

**Membership decided:** everything joins the fleet (each repo gets an acer home). The detailed,
per-repo inventory — which includes internal/work repo names — lives in a **git-ignored** private
note, never the public catalog; PROGRESS.md refers to those repos only generically.

## A conservative cleanup script

Drafted a one-shot `tenx-cleanup.sh` (git-ignored — it names an internal repo) to reconcile the
three gaps before seeding acer. It is deliberately careful, in the spirit of `gr`:

- **dry-run by default** (`--apply` to execute, prompts once),
- **fast-forward only**, never force,
- **verifies every precondition** and aborts on any surprise,
- **never deletes a home** — moves it aside and bundles it first.

Dry-run passes cleanly. A follow-up is noted: the public Omarchy repo was exported from the
*older* tip, so it needs a re-export/re-scrub from the canonical tip (2 commits ahead, incl. a
cert update) before its first push.

## Workflow note

Settled a commit gate so automation stays clear of work data: repos on the internal work host
(or named for internal projects) are hands-off — I make those commits myself; the personal/public
repos (this one, `git-redundancy`, the public Omarchy repo) can be committed for me. That's why
home-fleet now has its first real commits.

## Next

Phase 1 — stand up acer as a home server (headless Arch, 1 TB at `/data`, FIPS transport
matching tenx).
