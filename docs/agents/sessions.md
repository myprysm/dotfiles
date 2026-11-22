# Sessions

This file says which command a session runs, how it hands off mid-work, and how it ends. Map
bookkeeping (`## Next sessions`, `## Route`, the map write discipline) is in `issue-tracker.md`.

## Which command

| Situation | Command |
|---|---|
| A map has an open decision ticket | `/wayfinder #<map> #<ticket>` |
| Map end: no decision is open, and no spec exists | `/to-spec #<map>` |
| A spec is published, and it has no tickets | `/to-tickets #<spec>` |
| A spec has open implementation tickets | `/implement-spec #<spec>`. One session walks the whole ticket graph. |
| A lone ticket: an open issue that belongs to no map and no spec | `/implement #<ticket>` |

A spec's tickets do not get one `/implement` session each, unless the operator asks for it.

A map whose Notes carry execution ends with its last task ticket. It has no spec.

Put the command on the first line of the prompt, at column 0. Claude Code runs a slash command
only there. With a space before it, or inside pasted text, it is plain text.

## `/implement` and `/implement-spec` in this repo

1. Branch from an up-to-date `main`: `<type>/<ticket>-<slug>` (`fix/101-deny-paths`). An
   `/implement-spec` run uses one integration branch, named after the spec.
2. Run the related suites in `tests/`, then `/code-review`.
3. Open a PR for review with the `/pr` skill. Use `Refs #<n>`, never a closing keyword (see
   `AGENTS.md` › Commits). Do not open a draft PR that closes the spec and its tickets. A PR
   that serves a map goes on the map's milestone.
4. Land with the current rule: a PR for review, then a signed local fast-forward of `main`,
   then a push after operator approval. A GitHub merge drops the signature (PR #72). Do not
   decide this rule again here.
5. Close a ticket only after operator approval, with a comment that gives the SHA.

A `ready-for-human` ticket: the session prepares what it can, and gives the rest to the operator
in its final message.

## Hand-off

- **When**: prepare a hand-off at ~180k of context. At ~200k, start no new work. Also write one
  when the work moves between WSL and the Mac, or when the operator asks.
- **Where**: a comment on the driving issue. In a map session or an `/implement` session,
  that is the ticket. In an `/implement-spec` run, it is the spec. Do not use
  the OS temp directory of `/handoff`: the other machine cannot read it.
- **Contents**, pointers only:
  - the resume prompt, with the command on its first line;
  - each operator instruction since the last hand-off, marked done or deferred;
  - the commits, with SHAs, pushed or not;
  - the sub-agents that still run;
  - the machine, and whether Orca reaches the Mac;
  - the vault state: `bw` unlocked or not, `op` signed in or not;
  - `chezmoi apply` done and pending, for each machine;
  - the open decisions, and who takes them.

## Session end

Before you tell the operator that the session can be cleared, do these checks in this order:

1. `git status --short`, `git stash list`, `git worktree list`, and the local branches other
   than `main`.
2. Unpushed commits: `git log --oneline @{u}..`.
3. `chezmoi status` on WSL. Also run it on the Mac (Orca, `GIT_PAGER=cat`) if the session
   touched the Mac, or changed a file under `home/` that applies to the Mac. Do not run
   `chezmoi apply` at session end. List the pending applies.
4. The background Bash tasks, sub-agents and Orca terminals that the session started. Stop
   them without asking. Exception: a sub-agent that still works for the operator.

A pending apply, an extra worktree or an extra branch blocks `Prêt pour /clear.`. If the
operator accepts to keep it, it goes to `Open notes:`.

**Push.** The session commits its work. Before the final message, it asks the operator to
approve the push, and it gives the SHAs. With approval, it pushes. Without approval, the
unpushed SHAs go to `Open notes:`. They do not block `/clear`.

**Map sessions** and `/implement` sessions on a lone ticket update `## Next sessions`
(`issue-tracker.md` › Session close-out rule).

**Final message**, in this order:

1. The next prompt, word for word. If the session needs a model, a `/model` line comes first.
   The command is in a code block, at column 0. A map session copies it from the
   `## Next sessions` entry that it wrote.
2. `Open notes: …`, each note with its home, or `none`.
3. `Prêt pour /clear.`, or what still blocks it.
