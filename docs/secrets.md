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
  checklist, never wired into `chezmoi apply`.
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
- gitleaks pre-commit hook, installed automatically on fresh clones.
- No custom scanner rules encoding internal patterns — that would publish the patterns.
