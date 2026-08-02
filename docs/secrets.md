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
- gitleaks pre-commit hook — **not built yet**, tracked in #18. Nothing in this repo installs a hook today, so a fresh clone has no automatic scan. What exists is manual: the `/adopt` skill runs `gitleaks git --pre-commit --staged` on the staged diff before every commit it makes, and the written line-by-line review rule stands regardless. Do not rely on this line as a guarantee until #18 closes.
- No custom scanner rules encoding internal patterns — that would publish the patterns.

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

The threat model is a **careless** agent, not an adversarial one — an agent doing ordinary
work that would otherwise sweep a secret into context by accident. The guardrail is a speed
bump on that path. It is not a containment boundary and must not be relied on as one.

Known cost, accepted: a **local** `rsync` of a named secret is denied, since the rule tests
the command and not the destination. Use `cp` or `tar`.
