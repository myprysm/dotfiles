# Secrets policy

> Decided in issues #6 and #11; the scripts it describes were implemented in #19.
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

## Procedures

- **Restore**: `scripts/secrets-restore.sh` — explicit invocation, on the post-bootstrap
  checklist, never wired into `chezmoi apply`. On WSL the GPG secret key is imported
  into **both** keyrings: the native one, and the Windows store that git signs through.
  Importing only the former leaves a machine that looks restored and then cannot commit.
- **Audit**: `scripts/secrets-audit.sh` — compares local state against vault item names;
  reports unbacked local items and unrestored vault items; nags when the last local
  backup is older than 30 days.
- **Backup**: `scripts/secrets-backup.sh` — monthly; `bw export --format zip` (which
  now carries the attachment tree, so the per-item download loop #11 specified is no
  longer needed) into one passphrase-encrypted, machine-local archive under
  `~/.local/share/dotfiles-secrets`. Symmetric GPG, so the archive depends on a
  passphrase and no key. Never in this repo. The work manager is not covered — it has
  no export CLI and its vault is the employer's to back up.

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
