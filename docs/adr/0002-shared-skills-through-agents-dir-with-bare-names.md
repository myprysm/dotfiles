# Shared skills through `~/.agents` with bare names, not the marketplace plugin

The Matt Pocock skills reach Claude Code, codex and opencode from one chezmoi external: a
sha archive of `mattpocock/skills` at `~/.local/share/mattpocock-skills`. chezmoi symlinks
each skill of the pin's manifest list to `~/.agents/skills/<name>` (codex and opencode) and
to `~/.claude/skills/<name>` (Claude Code). Every agent sees the same bare name. Upstream
recommends the marketplace plugin, but Anthropic picks its sha, so the repo cannot pin it,
and it serves Claude Code only (#109). opencode takes the exact frontmatter `name` and never
adds a prefix (#107), so one name on all three agents means no `mattpocock-skills:` prefix
anywhere, unless the skills are edited (#110).

## Considered Options

- **Marketplace plugin**: rejected. Anthropic sets the sha, the manifest `version` gates the
  cache, and only Claude Code loads it.
- **A dotfiles marketplace with `sha`, or `CLAUDE_CODE_PLUGIN_DIRS`**: rejected. Both keep
  the prefix on Claude Code only, so the name depends on the agent.
- **skills CLI at a full sha**: rejected. It needs `npx` at apply time, its global lock
  cannot restore, and `50-claude-skills` would need a rewrite to re-apply a changed pin
  (#108). The external reuses the pin pattern of `.chezmoiexternal`.

## Consequences

- A bare name can collide with a built-in. The Claude Code bundled `code-review` and the
  Matt Pocock `code-review` collide.
- These skills are global on all three agents, so Loop sessions see them. Loop sessions must
  hide them and keep project skills: a scratch `HOME` for codex and opencode, and
  `skillOverrides` for each name in the Claude Code `--settings` file. These are proposals
  to the Loop. `OPENCODE_DISABLE_EXTERNAL_SKILLS` is not one of them, because it also drops
  project skills.
- opencode reads each skill twice, through `~/.claude/skills` and `~/.agents/skills`. Both
  paths lead to the same payload.
- Skills under `in-progress/` at the pin are not delivered, because they are not in the
  manifest list.
- The payload must not hold the plugin manifest. codex prefixes each skill under a plugin
  manifest with the plugin name, and it finds `.claude-plugin/plugin.json` from the symlink
  target. The external excludes `.claude-plugin/`.
