# dotfiles

Cross-machine environment setup for Linux/Mac, managed with chezmoi.

## Code comments

In this repo, this section replaces the global "no comments unless asked" rule (#33).

A comment records a trap the code cannot show: external behaviour that is wrong or
undocumented, a failure that cost a session to find, or a shape that looks wrong on purpose.
Its length follows the trap. A line that restates the code, a banner, or history ("was X, now
Y") is not a trap. A session that edits a file trims the comments in that file that fail this
test; nobody sweeps the tree for them.

A comment must not assert the current state of code it is not adjacent to. Name the trap,
not the inventory. Comments saying what another file now did, or that a list below them was
still empty, went stale four times (#29) — each true when written, none revisited when the
code under it moved.

A comment resting on a decision cites that decision's ticket (`#<n>`).

That citation is only worth carrying if something reads it, so: **a session that amends or
reverses an earlier decision runs `git grep '#<n>'` and reviews every hit before closing.**
This is the control. #21 measured a change, reverted it, and never looked for who was citing
it, so the comment asserting the reverted behaviour stayed shipped.

## Commits

Conventional commits, `type(scope): subject` (#37). Types: `feat`, `fix`, `docs`, `refactor`,
`test`, `chore`, `ci`, `build`, `perf`, `style`, `revert`.

Every commit carries one scope from this list. A commit that opens a new area adds its scope
here in the same commit. A change that spans two scopes is two commits.

- `bootstrap` — `bootstrap.sh`
- `packages` — `packages.yaml` and every package run script
- `secrets` — `scripts/secrets-*`, `docs/secrets.md`
- `rclone` — the rclone config
- `zsh` — `.zshrc` and the zsh drop-ins
- `git` — gitconfig and the estate-wide git hooks
- `claude` — `~/.claude` settings, statusline, hooks, skill restore
- `secret-guard` — the guard binary and its release
- `externals` — `.chezmoiexternal`
- `agents` — `AGENTS.md`, `docs/agents/`, the repo's `.claude/skills/`
- `context` — `CONTEXT.md`, `docs/adr/`
- `repo` — the repo as a whole
- `opencode` — `~/.config/opencode`
- `codex` — `~/.codex` config and global instructions
- `skills` — the skill pin, its `.chezmoiexternal` entry, the shared-skill symlinks in
  `~/.agents/skills` and `~/.claude/skills`, and the bump runbook
- `hindsight` — the `hindsight` bundle, the `~/.hindsight` config, the hindsight pin and its
  external entry, `docs/runbooks/bump-hindsight-pin.md`, and the hindsight build spec
- `<tool>` — a tool config under its own name (`k9s`, `starship`); list it on first use

A doc or a test takes the scope of what it covers: `docs(secrets)`, `test(rclone)`.

A ticket reference goes in a trailer: `Refs #<n>`. Use `Refs` only. GitHub closes an issue
when a commit reaches `main` with a closing keyword before `#<n>` anywhere in its message —
any form of close, fix or resolve — and closing needs the operator's approval.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for myprysm/dotfiles (gh CLI). See `docs/agents/issue-tracker.md`.

**Never create an issue without the operator's approval.** This rule has no exception. It
also covers an issue that a skill tells you to create, and an issue that holds text from a
ticket you are about to close. Write the proposal in the conversation instead. Give the
title, the question, and the reason. The operator decides.

The reason: three issues were created in one session without a request. The operator then
had to read and judge work he never asked for. He states the rule as "you propose, I decide".
An agent that opens issues also makes the tracker unreadable, and an unreadable tracker
stops the operator from reviewing any of it.

Two related rules, so the proposal path is not a way around them:

- Do not close or re-scope an existing issue without approval either.
- Write every issue body, every resolution comment and every map entry in Simplified
  Technical English (ASD-STE100). Short sentences. One idea in each sentence. Active voice.
  Keep every technical fact. The dense style became unreadable, which is what made the
  unapproved issues costly.

Open work, and the order it is taken in, live in the Notes of the wayfinder map
(issue #1) — not in this file, and not in the ticket numbers. Read them there
before picking anything up; the order is authoritative over the
`wayfinder:grilling` / `wayfinder:task` labels, several of which are wrong.

### Triage labels

Default five-label vocabulary (needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: root CONTEXT.md + docs/adr/. See `docs/agents/domain.md`.

### Adopting configs into the repo

Any adoption of a machine's config, package, or shell setup into this repo — full-machine
migration or a single item — follows the `/adopt` skill at `.claude/skills/adopt/SKILL.md`
(deny-list and mapping rules beside it). The repo is public: the skill's secret-safety
layers are mandatory for every write under `home/`.

### Runbooks

Procedures with a fixed order and steps that must be verified live in `docs/runbooks/`.
Read the relevant one before starting rather than reconstructing the steps:

- `relocate-a-secret-file.md` — moving a secret whose location was published.
- `bump-skill-pin.md` — moving the Matt Pocock skills to a new upstream commit, and the
  collision check after an agent upgrade.
