# Secrets policy

> Decided in issues #6 and #11; the scripts it describes were implemented in #19,
> and their work/`op` half in #47.
> Written under the redaction rule: no hostnames, key names, or identifying counts.

## Rules

1. **No secrets in this repo, in any form.** No plaintext, no `encrypted_` files, no
   infrastructure identifiers (hostnames, remote names, key ids, usernames).
2. **Line-by-line review** of every file before `chezmoi add`. Scanners catch token
   formats, not an internal URL inside an alias.
3. **Vault-first**: any new or rotated durable secret enters the manager at creation
   time. The machine is a checkout of the vault, never the canonical copy.
4. **The vault's filename is canonical.** One key, one name: where a machine holds the
   same key under a different filename, the machine is renamed to match the vault and
   its `~/.ssh/config` repointed — never the reverse.

## Per-domain routing

| Domain | Manager | CLI |
|---|---|---|
| personal | Bitwarden (self-hosted) | `bw` |
| work | 1Password | `op` (installs only with the work bundle) |
| escape hatch | HashiCorp Vault | generic `output` template function, documented, not wired in |

## Class roster

- **Vaulted** (durable, non-reissuable): SSH private keys, `~/.ssh/config`,
  GPG secret keys + ownertrust, Ansible Vault password files, triaged loose env files.
- **Re-auth instead** (ephemeral / re-issuable): gh, docker, npm/composer, vault-token,
  argocd, cloudflared, cloud CLIs, the managers' own state.

## The work domain (1Password)

`op` has no folders, so the personal vault's folder paths are mirrored as **tags**:
`dotfiles`, `dotfiles/ssh`, `dotfiles/restore`, all inside the built-in `Employee` vault.
The two are **not** interchangeable, and scripts must not treat them as such:

- A `bw` folder is exact. An `op` tag is **prefix-inclusive** — `--tags dotfiles` also
  returns everything tagged `dotfiles/ssh` and `dotfiles/restore`. Every enumeration
  filters the tag exactly, client-side.
- An `op` SSH Key item stores the key natively and has **no filename**, where a `bw`
  keypair is an attachment whose filename places it. Work SSH items therefore carry the
  same `path` field the restore items use, and it is mandatory: without it the item can
  be neither restored nor compared. Its public half is **derived**, not stored, so one
  item yields two files — the private key at 600 and the public half at 644.
- `op` publishes each key's fingerprint as item metadata, in the same SHA256 form
  `ssh-keygen` prints. The audit compares work keys with **no download at all**, a
  stronger form of the never-read-private-material rule than the personal arm's
  fetch-only-`.pub`.

**Authorization is interactive and it blocks.** With the desktop app integration, `op`
raises an approval prompt and waits — roughly two minutes before failing with
`authorization timeout`. A *locked* 1Password app instead fails immediately with
"account is not signed in" and raises no prompt at all. `op whoami` never prompts and
reports "not signed in" even when the very next read would succeed, so it is useless as
a gate: the only honest test is whether a read works. Every `op` call the repo makes is
bounded by `timeout` for this reason.

**No local backup, by design.** `op` has no export command — the whole command surface
was checked, not assumed. A work archive would have to be assembled item by item, which
means writing the employer's secrets onto a personal machine to guard against a loss the
employer already guards against. The audit says so explicitly rather than leaving a
domain silently absent from its freshness section.

## Procedures

- **Restore**: `scripts/secrets-restore.sh` — explicit invocation, on the post-bootstrap
  checklist, never wired into `chezmoi apply`. On WSL the GPG secret key is imported
  into **both** keyrings: the native one, and the Windows store that git signs through.
  Importing only the former leaves a machine that looks restored and then cannot commit.
- **Audit**: `scripts/secrets-audit.sh` — compares local state against vault item names;
  reports unbacked local items and unrestored vault items; nags when the last local
  backup is older than 30 days. Both domains share **one** SSH table rather than getting
  a section each: a key held in one domain and checked out under the other is exactly the
  drift worth catching, and auditing them separately makes it invisible. Each entry
  carries its side (`bw`, `op`, `local`). Where a work key's fingerprint also appears in
  the personal vault, that is reported as a note and not a finding — during a domain move
  both legitimately hold it, and the point is to be able to state that the `op` copy is
  fingerprint-verified before anything is deleted from `bw`.
- **Backup**: `scripts/secrets-backup.sh` — monthly; `bw export --format zip` (which
  now carries the attachment tree, so the per-item download loop #11 specified is no
  longer needed) into one passphrase-encrypted, machine-local archive under
  `~/.local/share/dotfiles-secrets`. Symmetric GPG, so the archive depends on a
  passphrase and no key. Never in this repo. The work manager is not covered — see
  **The work domain** above for why that is a decision rather than a gap.

## Repo guardrails

- GitHub push protection + secret scanning (enabled on the repo).
- gitleaks pre-commit hook — **estate-wide, not repo-scoped** (#18). `~/.gitconfig` sets
  `core.hooksPath = ~/.config/git/hooks`, so `chezmoi apply` arms every repo on the machine
  with no per-clone step; a secret leaks the same from any repo, and a hook that needs a
  manual step is a hook a fresh clone does not have. `pre-commit` scans the staged diff
  (`gitleaks git --pre-commit --staged`, default rules only) and **fails closed** if gitleaks
  is missing — the binary is a core brew, and the script phase installs it before the file
  phase writes the `.gitconfig` that arms the hook, so a bootstrapped machine cannot hit it.
  (That ordering is not an assumption: #13 established it live, where `.chezmoiscripts` sorting
  ahead of `.claude`/`.config`/`.zshrc` meant an aborting script stopped the run before any
  file was written at all.)
  - A global `hooksPath` **shadows every repo's own `.git/hooks`**, so these hooks chain:
    `pre-commit` scans and then delegates to `_chain`, and `commit-msg`, `prepare-commit-msg`,
    `pre-push`, `post-checkout`, `post-commit` and `post-merge` are symlinks to `_chain`, which
    only dispatches. That set is what the tools on this estate install — husky/lint-staged and
    `git lfs install`. **A hook name absent from it silently stops working**, so a tool that
    installs some other name needs a symlink adding here. A repo that sets its own **local**
    `core.hooksPath` (husky) overrides all of this and is untouched.
  - `git commit --no-verify` is the deliberate escape hatch and stays available to you —
    upstream clones do throw false positives. It is denied to **agents** (see below).
  - Verifying it by hand: the AWS documentation example key (`AKIAIOSFODNN7EXAMPLE`) is in
    gitleaks' default **allowlist** and passes. That is the scanner working as configured, not
    the hook failing. Use a correctly-shaped `ghp_` token or a `BEGIN OPENSSH PRIVATE KEY`
    block as a canary.
  - The scan is the last layer, never the only one: the `/adopt` skill still runs its own
    gitleaks gate, and the written line-by-line review rule stands regardless.
- No custom scanner rules encoding internal patterns — that would publish the patterns.

## Typed-input stores

A file a tool maintains of what a human typed or yanked, so it can be recalled. A shell
history is every credential ever typed at a prompt; a vim register is whatever was yanked
out of a file the deny rules already protect. These are never adopted, and the rule is
carried on **three** layers, because none of them covers what the others do (#61):

1. **`home/.chezmoiignore`** — refuses `chezmoi add` whoever asks, and an ignored target is
   never applied. It says nothing about what sits in the *source* tree.
2. **`/adopt`'s deny-list** — covers the gap that leaves. The write gauntlet gates
   `chezmoi add` *and any write under `home/`*, and a hand-written `home/dot_zsh_history`
   reaches the public repo with the ignore rule fully in force and silent.
3. **`Read` deny rules** in `~/.claude/settings.json` — an agent has no business reading one.

The patterns:

```
**/.*_history   **/*_history   .lesshst   .viminfo
.local/share/mcfly/**          Library/Application Support/McFly/**
```

Two properties are load-bearing and neither is obvious:

- **The `**/` prefix.** A bare `.*_history` in `.chezmoiignore` is root-anchored: with it in
  force, `chezmoi add ~/proj/sub/.psql_history` stages the file **with no warning**, and a
  recursive add of the parent does the same — which is exactly the walk `/adopt` performs on
  a full machine.
- **History databases are denied by directory, not by pattern.** The text stores share a
  naming convention; McFly's `history.db` does not, and neither does atuin's. A new
  history-database tool needs a new entry on layers 1–3, since no pattern will catch it.
  Banning `**/history.db` by name was rejected: the name is generic enough that an unrelated
  tool could legitimately use it, and a chezmoi refusal is a warning rather than an error,
  so it would fail quietly.

**Permissions.** McFly creates its store at the ambient umask — 644 on both machines, while
every text history file is 600 because its tool sets it explicitly. `rc.d/30-mcfly.zsh`
tightens the directory to 700 and the database to 600 on every interactive shell, beside the
`.zsh_history` seed and for the same reason: self-healing beats a one-off `chmod`, and the
*directory* matters because SQLite writes sidecar files mid-transaction.

**The limit, stated plainly.** `mcfly search` and `mcfly dump` read the store while naming
no file, and Bash is governed by neither the deny rules nor the hook (#44). Layer 3 is a
speed bump against a careless agent, exactly as the section below describes; layers 1 and 2
are what actually keep the transcript out of the public repo.

## Agent guardrails

A `PreToolUse` hook (`~/.claude/hooks/block-secret-reads.sh`, templated from this repo)
denies agent tool calls that would surface a secret. Its scope is deliberately narrow, and
is stated here so it is not read as wider than it is.

**Covered.** Decided in #42, #44 and #45:

- Secret contents into context — `Read` or `Grep` on a secret path, and a Bash command
  that hands one to a reader utility, POSIX `source`, or input redirection.
- Recursive Bash content search as a class (`grep -r`, `rg`/`ag`/`ack`,
  `find … -exec <reader>`, `xargs` into a reader). These read files they never name, so no
  path rule can see them. Use the `Grep` tool, whose results the permission deny rules
  filter per matched file.
- `ansible-vault view`/`decrypt`/`edit`/`cat`/`rekey`.
- A **named** secret path handed to a transport that leaves the machine: `scp`, `sftp`,
  `rsync`, and `curl`/`wget` with an upload flag. Secrets move through the manager, never
  over a direct transfer, so there is no legitimate case to let through.
- `git commit --no-verify` (and the bundled short form, `-nm`), which would skip the
  estate-wide gitleaks scan above, **and `git -c core.hooksPath=… commit`**, which skips it
  without naming a flag at all. Checked **before** the secret-path gate, since the command
  names no secret. An agent meeting a finding must surface it, not step around it.
  `git push -n` is left alone — there `-n` is `--dry-run`.
  Three properties this arm needs, each of which it lacked when first shipped and a code
  review caught (all three now pinned by `tests/test-block-secret-reads.sh`): a separator
  glued to the flag (`--no-verify;echo x`) ends the command exactly as a space does; `commit`
  must be the **subcommand**, so only git's own global options may precede it, or read-only
  work like `git log --grep commit -n 5` is refused; and the match runs against a
  **quote-stripped** copy, so a commit *message* mentioning a flag is not itself a bypass.

**Not covered.** Each is a deliberate limit, not an oversight:

- **Local copies.** `cp`, `mv`, `tar`, `zip` of a secret are allowed, including the two
  probes that opened #45. A local copy crosses no boundary — the bytes stay on a machine
  that already held them — and becomes harmful only when something reads the copy, which
  is a second, deliberate act.
- **Transfers that never name the secret.** The hook matches path patterns in the command
  string, so a whole-directory `rsync` to a remote is invisible to it. Same blindness #44
  found in recursive readers; there a class-deny was justified because the `Grep` tool was
  a safe replacement to steer to, and no such replacement exists for `rsync`.
- **Interpreters.** `sh -c`, a script file, or `python3 -c` walks a tree without naming
  anything. `python3 -c` is allow-listed in settings.
- **Other routes to an unscanned commit.** `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_n` can set
  `core.hooksPath` from the environment, and any interpreter can call git directly. The
  `-c core.hooksPath=` form is denied because it is the one an agent reaches for; the rest
  are the same speed-bump-not-boundary limit as everything else in this section.

The threat model is a **careless** agent, not an adversarial one — an agent doing ordinary
work that would otherwise sweep a secret into context by accident. The guardrail is a speed
bump on that path. It is not a containment boundary and must not be relied on as one.

Known cost, accepted: a **local** `rsync` of a named secret is denied, since the rule tests
the command and not the destination. Use `cp` or `tar`.
