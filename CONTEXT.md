# Dotfiles

Cross-machine dev environment (zsh, brew-first) managed with chezmoi in a public repo. Configs and package intent are versioned; secrets never are.

## Language

**Adopt**:
Take a config, tool, or package from a machine into the repo, mapped onto the repo's layout (drop-in dirs, `packages.yaml`, scripts).
_Avoid_: import, migrate a file

**Migration**:
Adopting a whole machine: inventory, plan, approve, adopt, until the machine runs from the repo.
_Avoid_: sync, setup

**Inventory**:
The full-machine sweep cataloguing packages, shell files, tool configs, and secret-bearing paths. A session working artifact, not a committed doc.
_Avoid_: audit (reserved for the secrets drift check)

**Migration plan**:
The per-item proposed mapping of inventory findings onto the repo layout, approved by the human group-by-group before any adoption write.

**Deny-list**:
The set of secret-bearing path patterns (from the machine inventories) the adopt skill refuses to stage, ever.
_Avoid_: blocklist, exclusion set

**Redaction rule**:
Published artifacts carry no secret values and no infrastructure identifiers; hostnames, key names, and remote names reduce to counts.

**Bootstrap**:
The one-liner (`bootstrap.sh`) taking a fresh machine to a working shell: brew, chezmoi, init prompts, apply.
_Avoid_: install, provision

**Drop-in dir**:
A typed fragment directory (`env.d/`, `aliases.d/`, `rc.d/`, `completions.d/`) under `~/.config/zsh`; adding behavior means dropping a file.

**Repo-visible ref**:
A vault item name that appears in the public repo (templates, `secrets.yaml`, scripts). Must stay generic under the redaction rule: kebab-case `<consumer>-<artifact>`, no domain suffix.

**Vault-only name**:
An item name that exists only inside a secret manager (SSH keys, restore items). Never appears in the repo; may be specific and descriptive.

**Self-describing restore item**:
A vault item that carries its own destination as private fields (`path`, optional `mode`); the restore script discovers it by folder/tag enumeration, so no names or paths live in the repo.
