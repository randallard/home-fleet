# Dev journal

A dated, narrative worklog — the *story over time* that the other docs don't capture: commit
messages are per-commit, [`../adr/`](../adr/README.md) is per-decision, PROGRESS.md is the
current-state overview. This is the running "what we did and why, in order." Same convention as
the companion [git-redundancy](https://github.com/randallard/git-redundancy) journal.

## Convention

- One file per entry: `YYYY-MM-DD-kebab-title.md`. Multiple entries in a day get a `-2`, `-3`
  suffix.
- Each entry names the **commit(s) it documents** by short hash. Entries are append-only;
  correct mistakes in a later entry, don't rewrite old ones.

## Journaling with commit hashes (the self-reference rule)

A commit **cannot contain its own hash** (the hash is derived from the content). So a journal
entry references the **work commit it documents**, and is itself landed in a **follow-up
commit**:

```
commit A  ── the work
commit B  ── "journal: document commit A"   (entry references A's hash)
```

This keeps referenced hashes real and stable, with no history rewriting.
