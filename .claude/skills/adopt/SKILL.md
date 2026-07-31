---
name: adopt
description: Use when taking a machine's config, tool, package, or shell setup into this dotfiles repo — a full-machine migration or a single item ("adopt my k9s config"). Also use before any `chezmoi add` or any write under home/ sourced from a live machine.
---

# Adopt

Take configs, packages, and shell setup from a machine into this **public**, chezmoi-managed repo. Two modes, one procedure: **full-machine** (inventory → migration plan → per-group approval → adopt) and **incremental** (one tool/config; skip the inventory, keep everything else).

**The repo is public. Every layer below is mandatory in both modes, every run, no matter how small the change or how much of a hurry anyone is in.**

## Procedure

### Full-machine mode

1. **Inventory** — sweep the machine with the checklist below. The inventory is a session working artifact (scratchpad or session dir): it is never committed, never lands in `docs/inventory/`, and anything quoted from it into an issue or doc follows the redaction rule (no secret values, no infrastructure identifiers — hostnames, key names, remote names reduce to counts).
2. **Classify** every finding: `adopt` / `adopt-as-template` (secret or OS variance inside) / `package` (goes in `packages.yaml`) / `per-machine` (untracked `~/.zshrc.local`, `settings.local.json`) / `purge` (dead on this machine, propose deletion) / `deny` (matches [deny-list.md](deny-list.md)) / `report` (foreign — no home in this repo's shape).
3. **Migration plan** — group the classified findings (shell, packages, tool configs, agent tooling, …) and present them group by group. **The human approves each group before any write in that group.** No approval, no write — a "just get it in" or "I'm in a hurry" from the user does not waive this; it is the reason this repo has stayed clean.
4. **Adopt** each approved item through the write gauntlet below.
5. **Commit locally.** Never push — pushing needs explicit user approval and is not part of this skill.

### Incremental mode

Steps 2–5 for the named item only: classify it, show a mini-plan, get one approval, run the gauntlet, commit locally.

## The write gauntlet (every file, both modes)

1. **Deny-list check** — if the source path matches [deny-list.md](deny-list.md), hard-refuse to stage it. No exceptions for "the value is fake/expired/already rotated": shape decides, not validity.
2. **Strip-and-review** — read every line of the file's content before `chezmoi add` or writing into `home/`. Secrets hide *inside* legitimate configs (a real rc file on this estate carried an inline tunnel credential). Strip credential-shaped lines, internal hostnames, and work-specific values; show the human the stripped result and what was removed (by line reference, not by quoting the secret).
3. **Map** the destination with [mapping.md](mapping.md) — no improvised layouts.
4. **Gitleaks gate** — after staging, before committing: `gitleaks git --pre-commit --staged` (install via `brew install gitleaks` if absent). A finding blocks the commit; gitleaks is the last layer, never the only one.

## Inventory checklist

- **Packages**: brew leaves + casks, apt manual installs, npm globals *per node version*, `~/go/bin` binaries, krew plugins, SDKMAN candidates, helm repos, rustup/cargo, composer globals, hand-copied binaries (`/usr/local/bin`, `/usr/local/go`, JVM dirs).
- **Shell**: rc files (`.zshrc`, `.zprofile`, `.zshenv`, `.profile`, bash files), sourced fragments (`.zfunc`, custom dirs), omz plugin list — mark each plugin live or dead (declared but tool absent, or vice versa).
- **Tool configs**: `~/.config/*`, macOS `~/Library/Application Support` + `~/Library/Preferences`, top-level dotfiles in `$HOME`.
- **Secret scan**: deny-list matches, mode-600 files, credential-shaped content in everything classified `adopt`.

## Boundaries

- Assumes this repo's shape: zsh + brew-first. Bash aliases/functions map into the zsh drop-in dirs after a syntax check. Fish or other foreign setups are inventoried and **reported, not adopted** — do not invent repo layout for them.
- Local commits only. Never push.
- IDE configs, kube/cloud contexts, browser profiles, agent-tool state dirs: out of scope (see deny-list).

## Red flags — stop if you think any of these

| Thought | Reality |
|---|---|
| "User is in a hurry, skip the approval round" | The gate survives urgency. Plan first, always. |
| "This token is fake/expired, it can ship" | Shape decides. Strip it. |
| "It's just a config file, not a secret file" | The inline-credential incident was in an rc file. Review every line. |
| "gitleaks passed, no need for manual review" | Scanners miss internal URLs and hostnames. Both layers run. |
| "Commit the inventory so we keep it" | Session artifact. Never committed. |
| "Push so the other machine can pull" | Never. Pushing is a separate, human-approved act. |
