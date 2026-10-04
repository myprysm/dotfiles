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

**Typed-input store**:
A file a tool maintains of what a human typed or yanked, so it can be recalled: shell histories, `.viminfo` (its registers hold yanked text), `.lesshst`, McFly's SQLite database. Never adopted, on any layer — the reason is not that it is a shell but that a secret was typed once and the tool wrote it down.
_Avoid_: command history (excludes the vim and pager stores by its own wording)

**Redaction rule**:
Published artifacts carry no secret values and no infrastructure identifiers; hostnames, key names, and remote names reduce to counts.

**Bootstrap**:
The one-liner (`bootstrap.sh`) taking a fresh machine to a working shell: brew, chezmoi, init prompts, apply.
_Avoid_: install, provision

**Drop-in dir**:
A typed fragment directory (`env.d/`, `aliases.d/`, `rc.d/`, `completions.d/`) under `~/.config/zsh`; adding behavior means dropping a file. All four are sourced from `.zshrc`, so all four are **interactive-only**, `env.d` included despite the name.

**Bundle**:
A named group of packages, configs and scripts a machine opts into at init (`work`, `go`, `ops`, `rust`, …), stored in that machine's chezmoi data. A bundle that is off leaves everything behind it out of the target state, so a gated tool is not installed and its scripts do not run.
_Avoid_: profile, feature flag, module

**Domain**:
The owner of a secret, which fixes the manager it lives in: **personal** secrets in Bitwarden, **work** secrets in 1Password. Every secret has exactly one domain, and the domain decides the manager, not the machine. The work domain reaches only a machine with the work bundle on.
_Avoid_: vault as a synonym for domain (a vault is a manager's container, not a secret's owner), account, environment

**Repo-visible ref**:
A vault item name that appears in the public repo (templates, `secrets.yaml`, scripts). Must stay generic under the redaction rule: kebab-case `<consumer>-<artifact>`, no domain suffix.

**Vault-only name**:
An item name that exists only inside a secret manager (SSH keys, restore items). Never appears in the repo; may be specific and descriptive.

**Self-describing restore item**:
A vault item that carries its own destination as private fields (`path`, optional `mode`); the restore script discovers it by folder/tag enumeration, so no names or paths live in the repo.

**Secret guard**:
The `block-secret-reads` PreToolUse hook. It stops the model's tool calls from reading secret-bearing paths. It does not stop a mod: every installed mod runs before it and can read any file the user can.
_Avoid_: sandbox, permission system

**Mod**:
A Claude Code plugin whose `hooks/hooks.json` names a module under `modules`. It runs in process, with the user's full access. Trusted code, not checked by the secret guard.
_Avoid_: plugin as a synonym (most plugins ship only command hooks, skills or servers), extension

**Mod admission**:
The review a mod passes before it is enabled, and again after each update. A mod is refused if it hooks `tool.call`, `classic.PreToolUse` or `tool.check`, or calls `fs.read` or `process.run`. The only control on which code runs ahead of the secret guard.
_Avoid_: audit (reserved for the secrets drift check), approval

**Mod check**:
The session-start scan that finds every installed plugin that ships a mod, so that it goes through mod admission. It reports; it does not block, because the mod has already loaded.
_Avoid_: audit (reserved for the secrets drift check), scan as a noun

**Shared skill**:
A skill that reaches Claude Code, codex and opencode under one bare name, from one skill pin.
_Avoid_: global skill, plugin skill

**Agent-specific skill**:
A skill that only one agent reads, because its subject is that agent.
_Avoid_: personal skill (Claude Code's name for any skill in its home dir)

**Skill pin**:
The one upstream commit of a skill repo that every agent uses. Only a repo commit changes it.
_Avoid_: version (the manifest version does not identify the content)

**Skill bump**:
A change of the skill pin. The operator makes it by hand, and a collision check comes first. The dotfiles skill pin and the Loop's skill pin are bumped apart and can differ.
_Avoid_: update, upgrade (reserved for a new version of an agent)

**Hindsight pin**:
The one exact version of the hindsight-coding-agents runtime that every enrolled machine runs. Only a repo commit changes it; the runtime never updates itself.
_Avoid_: latest, version range

**Hindsight bump**:
A change of the hindsight pin. The operator makes it by hand, after the bump checks pass.
_Avoid_: update (the runtime's own self-update), upgrade (reserved for a new version of an agent)

**Collision check**:
The comparison of the skill pin's names with the built-in skills of Claude Code, codex and opencode and with the other skills in the agents' home dirs. Done before each skill bump and after an agent upgrade.
_Avoid_: conflict check
