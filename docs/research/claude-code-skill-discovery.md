# How does Claude Code 2.1.289 find skills, which source wins on a name collision, and can a session hide an entry of `~/.claude/skills`?

Ticket: myprysm/dotfiles#105

Versions tested: Claude Code 2.1.289 (`claude --version` -> `2.1.289 (Claude Code)`, binary `~/.local/share/claude/versions/2.1.289`). The docs are from code.claude.com, read 2026-10-04. The docs are not versioned. The doc gate for `CLAUDE_CODE_PLUGIN_DIRS` is v2.1.280, which is older than the installed version.

Inputs: claude-r1, codex-r1, claude-chal-r1, codex-chal-r1. Claude ran live probes: `claude -p ... --output-format stream-json`, reading the init `skills` and `plugins` arrays. Codex read the binary and the docs. Codex ran no skill-loading session.

## Answer

Claude Code loads skills from four kinds of source at the same time:
- the personal dir `~/.claude/skills/<name>/` (a symlink to a directory is accepted)
- the project dir `.claude/skills/`
- marketplace plugins
- session plugins (`--plugin-dir`, `CLAUDE_CODE_PLUGIN_DIRS`)

A plugin skill always has the name `plugin-name:skill`. So a plugin skill and a personal skill with the same base name both load.

For the same bare name in two non-plugin locations, enterprise wins over personal, and personal wins over project. This is from the doc only; no side probed it.

A bare `/name` runs the local skill. When no local skill has that name, it runs the plugin skill.

A session plugin can have the same manifest name as an installed plugin. Then it replaces the whole installed plugin for that session.

`CLAUDE_CODE_PLUGIN_DIRS` works like `--plugin-dir`. This is also true when the settings `env` block sets it.

A session can hide one entry of `~/.claude/skills`. Put `skillOverrides: {"<name>":"off"}` in a file and pass it with `claude --settings <file>`. `skillOverrides` has no effect on plugin skills.

## Claims

1. **CONFIRMED.** The discovery locations are: enterprise, personal `~/.claude/skills/<name>/SKILL.md`, project `.claude/skills/`, nested dirs, `--add-dir`, plugin `<plugin>/skills/<name>/SKILL.md`, and claude.ai synced. Sources: skills.md "Where skills live" (both sides). Codex also found binary gates `Vn("userSettings")` and `Vn("projectSettings")`.
2. **CONFIRMED (doc only).** When the same bare name is in two non-plugin locations, enterprise wins over personal, and personal wins over project. Source: skills.md "Resolve skills that share a name" (both sides). No side probed this.
3. **CONFIRMED.** A plugin skill and a non-plugin skill with the same base name both load. This is because plugin skills are namespaced. Sources:
   - skills.md (both sides)
   - Claude's probe: `probe-dup-r1` and `plug-a-r1:probe-dup-r1` were both in init `skills`.
4. **CONFIRMED.** A bare `/name` runs the local skill when a local skill exists. With no local match, it runs the plugin skill. Sources: skills.md "How a skill gets its command name" (both sides). Claude's probe outputs were `PROJECT` and `PLUGC`; this probe is Claude-only.
5. **CONFIRMED.** A personal entry can be a symlink to a directory. A target reached through two locations loads once. Sources:
   - skills.md (both sides)
   - binary (codex): `if(!V.isDirectory()&&!V.isSymbolicLink())return null;` and the log text `Skipping duplicate skill ... (same file already loaded ...)`
   - Claude's probe: the real symlinks `find-skills` and `orca-cli` appear in init `skills`.

   Deduplication itself was not probed.
6. **CONFIRMED.** A session plugin with the same manifest name loads instead of the installed plugin. Sources:
   - plugins/cli-reference.md (both sides)
   - binary log text `from --plugin-dir overrides installed version` (codex)
   - Claude's probe with plugD, manifest name `mattpocock-skills`: `/mattpocock-skills:tdd` printed `PLUGD`.
7. **CONFIRMED.** The replacement removes the whole installed plugin, not only the colliding skill. Sources:
   - Claude's probe: only `mattpocock-skills:tdd` remained. Without the flag, about 25 skills load.
   - codex binary S4: the whole marketplace plugin object is filtered out.
8. **CONFIRMED.** Precedence for one manifest name: managed policy, then the enabled session plugin, then the marketplace plugin, then the skills-directory plugin. Sources: plugins/loading.md "Name conflicts" (both sides). Codex also cites the binary.
9. **UNVERIFIED.** A fifth tier, synced plugins, comes last. Source: plugins/loading.md lines 358-370. Only Claude-chal states this.
10. **CONFIRMED.** The installed copy loads instead in two cases:
    - the session copy was disabled with `claude plugin disable <name>@inline`
    - managed settings lock the name

    A session plugin has the id `name@inline`. A marketplace plugin has the id `name@marketplace`. Sources: cli-reference.md (both sides); binary text `ignored: plugin is locked by managed settings` (codex). The disable case was not probed.
11. **CONFIRMED.** `CLAUDE_CODE_PLUGIN_DIRS` loads each path like `--plugin-dir`. The separator is `:` on Unix. Each path must be absolute or start with `~`; relative paths are skipped. The doc gate is v2.1.280. Sources: env-vars.md (both sides); binary `path.delimiter` split (both sides).
12. **CONFIRMED.** The settings `env` block can set `CLAUDE_CODE_PLUGIN_DIRS`. Sources:
    - binary text `Unset CLAUDE_CODE_PLUGIN_DIRS (in the environment, or in the settings \`env\` block that sets it)` (both sides)
    - Claude's probe: `--settings envset.json` gave `plug-c-r1:probe-only-r1`.
13. **CONFIRMED.** `--plugin-dir` is repeatable. Plugins with different names load side by side. Sources: `claude --help` (codex); Claude's probe with plugA and plugB.
14. **UNVERIFIED.** `--plugin-dir` also accepts a `.zip`. A folder of plugins loads each child. Source: `claude --help` (codex only).
15. **UNVERIFIED.** `--settings` accepts an inline JSON string. Source: `claude --help` (codex only). Claude tested only the file form.
16. **CONFIRMED.** `skillOverrides` maps a name to one of four values: `on`, `name-only`, `user-invocable-only` or `off`. With `off`, the skill is hidden from the model and from `/`. An explicit call to it returns an error. Sources: skills.md "Override skill visibility" (both sides); binary schema (both sides).
17. **UNVERIFIED.** `user-invocable-only` hides the skill from the model but keeps `/name`. Source: binary schema text (codex-chal only). The model effect was not tested.
18. **CONFIRMED.** A session settings file with `skillOverrides: {"<name>":"off"}` can hide an ordinary personal skill, a symlinked entry of `~/.claude/skills` included. Sources: codex binary `FK`/`NP`, schema and directory loader S1-S3 (codex-chal claim 14); Claude's probe (claim 30).
19. **CONFIRMED.** `skillOverrides` does not affect plugin skills. This applies to marketplace plugins and to `--plugin-dir` plugins. Sources:
    - skills.md "Plugin skills are not affected by skillOverrides" (both sides)
    - binary `if(e.type!=="prompt"||e.source==="plugin")return"on";` (both sides)
    - Claude's probe: `plug-a-r1:probe-dup-r1` and `mattpocock-skills:tdd` set to `off` stayed listed.
20. **CONFIRMED.** A bare-name key set to `off` hides only the local skill. The plugin skill with the same base name stays. Sources: the Claude probe; codex binary S1.
21. **CONFIRMED (doc only).** Settings precedence: managed, then CLI `--settings`, then local, then project, then user. Source: settings.md "Settings precedence" (both sides).
22. **UNVERIFIED.** The claim that the most restrictive `skillOverrides` value wins across all scopes is not established.
    - Claude marked it unverified.
    - Codex: the restrictive compare (`Lie`, `kMt=["policySettings","flagSettings"]`) covers alias handling only.
23. **CONFIRMED.** `--setting-sources` gates user and project skill discovery. The help text for `--disable-slash-commands` is "Disable all skills". Sources: binary gating (codex); `claude --help` (both sides); Claude's probe with `--setting-sources project`.
24. **UNVERIFIED.** `--setting-sources project` also removes marketplace plugins, and `--plugin-dir` still loads. Source: probe (Claude only).
25. **CONFIRMED-CORRECTED.** In a git worktree the walk stops at the worktree root. It falls back to the main checkout's `.claude/skills` only when the worktree root has no `.claude/skills` directory. This needs v2.1.277+. Correction: Claude wrote "if the worktree has none", from a WebFetch summary. Codex quoted skills.md lines 219-220. Claude did not rebut.
26. **CONFIRMED-CORRECTED.** A folder named `synced` (any case) is reserved. The reserved names are exactly `anthropic-skills` and names that begin `anthropic-skills:`. Correction: Claude wrote `anthropic-skills*`. Codex refuted this with skills.md lines 210-211. Claude did not rebut.
27. **UNVERIFIED.** Two session plugins with one manifest name: `--plugin-dir plugD --plugin-dir plugE`, both named `mattpocock-skills`. In either order, init shows the installed marketplace copy (cache path 1.2.3, 25 skills), and neither session copy loads. The debug log still prints `overrides installed version`. Source: Claude-chal probe only. Codex lists this case as unresolved.
28. **UNVERIFIED.** For one name given by both the flag and `CLAUDE_CODE_PLUGIN_DIRS`, the `--plugin-dir` flag copy wins. Source: Claude-chal probe only (`PLUGD`/`PLUGE` swap).
29. **UNVERIFIED.** A plugin-shaped dir under a skills dir follows plugin rules, so `skillOverrides` does not reach it. Source: loading.md lines 363-367 (Claude-chal only, not probed).
30. **UNVERIFIED.** The specific experiment: Claude ran `--settings` with a file holding `{"skillOverrides":{"find-skills":"off"}}`. This removed the symlinked `~/.claude/skills/find-skills` from the init skills and from the slash list. Source: Claude probe only. Codex-chal marks the run and the array as not reproduced. The retained `s.json` now holds another key.
31. **CONFIRMED.** Marketplace plugins are found through the installed-plugin records (`installed_plugins.json`) and the cached payloads under `~/.claude/plugins/cache/`. Settings `enabledPlugins` (`name@marketplace`) controls which load. Sources: plugins/loading.md (codex-r1 claim 3; claude-chal lines 30-33); Claude-chal probe: init `plugins` shows `mattpocock-skills` at `~/.claude/plugins/cache/claude-plugins-official/mattpocock-skills/1.2.3`.

## Corrections to earlier claims

- codex-r1 claim 8 has the tag `[probe]`, but codex ran no hiding test. Codex-chal narrows the tag. Claim 18 (mechanism, both sides) and claim 30 (Claude's single-side run) now cover it.
- codex-r1 claim 7 omits that the replacement covers the whole plugin. See claim 7.
- claude-r1 claim 21 (`anthropic-skills*`) is corrected by claim 26.
- claude-r1 claim 20 (worktree condition) is corrected by claim 25.
- claude-r1 claim 13 mentions a settings-reference summary with `hidden`/`collapsed` booleans. Both sides reject it.
- The doc line numbers differ between the sides: skills.md 154 against 202-209, and env-vars.md 344 against 371. The docs are rolling. Do not copy these line numbers into the map.
- Codex marks Claude's exact probe arrays as "not reproduced". It did not contradict any of them.

## Open points

- The personal-vs-project bare collision was not probed.
- Do the `skillOverrides` in a `--settings` file merge with the user's own `skillOverrides`, or replace them? Not tested.
- The mechanism behind claim 27 is not known.
- These were not probed: `plugin disable name@inline`, inline JSON for `--settings`, `.zip` for `--plugin-dir`, and the model effect of `user-invocable-only`.

## Consequences for the map

- The marketplace plugin and a Loop `--plugin-dir` copy with a different manifest name both load. The same skills then appear under two prefixes (claims 3, 6, 13).
- A Loop copy with the manifest name `mattpocock-skills` replaces the whole marketplace plugin for the session (claims 6, 7).
- Two session copies with one manifest name produced the marketplace copy. This is a single-side probe (claim 27).
- Known fact from the brief: `enabledPlugins:false` does not hide a `--plugin-dir` copy. Plugin skills ignore `skillOverrides` (claim 19).
- Personal skills in `~/.claude/skills` can be hidden per name and per session with a `--settings` file. This needs no write to `~/.claude` (claim 18).
- A personal skill and a plugin skill with the same base name do not collide. A bare `/name` runs the personal skill (claims 3, 4).
- A settings `env` block with `CLAUDE_CODE_PLUGIN_DIRS` gives the same session plugins as `--plugin-dir`. Relative paths are skipped (claims 11, 12).

