---
name: claude-permissions-review
description: Review and prune Claude Code permission settings interactively.
disable-model-invocation: true
---

# Claude permissions review

Interactively prune `permissions.allow` in the current repo's `.claude/settings.local.json`. Never touch any other key or file.

1. Read `.claude/settings.local.json`. If the file or `permissions.allow` is missing, or every entry is a deliberate prefix rule, say the list is clean and stop.
2. Classify every entry:
   - **Dead** — exact one-off literals that will never match again (session-specific paths, one-time commands, argument-pinned invocations), and rules shadowed by a broader `:*` or trailing-`*` rule _in this same file_. Never call a rule shadowed only by a rule in another settings file.
   - **Red** — rules permitting arbitrary execution: interpreter eval flags (`node -e`, `python3 -c`, `php -r`, stdin dashes), `docker exec`, `cd <dir> *`, catch-all wrappers, in-place editors like `sed:*`.
   - **Review** — remaining low-value or occasional entries.
     Recurring prefix rules for the repo's own tooling are keepers — do not list them.
3. Render one table per group, Dead → Red → Review, header `### <Group> (<count>)`, columns **#**, **Rule** (truncate at 60 chars) and **Why** (one short clause). The **#** column carries a stable row ID: `A<n>` for Dead, `B<n>` for Red, `C<n>` for Review, numbered from 1 within each group. Every later reference to a row uses that ID.
4. Below the tables, propose consolidations as a numbered list with IDs `K1`, `K2`, … : each family of ≥3 similar exact entries → one `Bash(<cmd>:*)` prefix rule. Never propose consolidating a Red pattern.
5. Ask: "Delete everything listed, or go group by group?"
6. If group by group, ask once for all groups and accept a single comma-separated answer mixing row and consolidation IDs (e.g. `A4, B2, K1, K3`) — never re-prompt group by group when one list will do. Spell out the convention in the question: row IDs listed are the rows to **keep**, `K` IDs are the consolidations to **add**, and a bare group letter (e.g. `A`) means delete that whole group. Re-render nothing; the tables above already carry the IDs.
7. Apply everything in a single edit to `permissions.allow` only. Verify the file still parses as JSON. If the user declined everything, the file must be byte-identical.
8. Close with a one-line tally, always in this shape — no prose around it:
   `<before> → <after> entries · <n> removed · <n> added`
   Count removals and additions as literal `permissions.allow` lines: an accepted consolidation removes every entry it subsumes (including ones not listed in the tables) and adds each new prefix rule it introduces. A row that is only rewritten still counts as one removed and one added. Report `0 removed · 0 added` when nothing was applied.

When judging deadness, remember: env-var-prefixed, compound (`&&`, `|`), and `./`-prefixed commands each need their own matching rule.
