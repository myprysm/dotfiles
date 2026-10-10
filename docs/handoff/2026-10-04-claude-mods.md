# Handoff — Claude Code mods: build spec (2026-10-04)

This spec closes the map "Claude Code mods — statusline and setup revision" (#85). A build
session works from it. It restates each step that a build session must do. It does not copy
the reasons. Each step cites the ticket that holds the decision. **If this file and a ticket
disagree, the ticket is correct.**

Words in this file have the meanings in `CONTEXT.md`: secret guard, mod, mod admission, mod
check.

## Where things stand

- The repo ships zero mods (#90, #93). No surface becomes a mod now.
- The statusline stays the bash `statusLine` command. Its segments do not change (#90).
- No enabled plugin ships a mod, on WSL (#95) or on the Mac (#89).
- The secret guard stops the model. It does not stop a mod. Every mod runs before it (#87, #91).

## Build now

These items do not need a mod. Build them in this order. Commit scope: `claude`.

1. **Comment in the secret guard** (#91, item 8). In
   `home/dot_claude/hooks/executable_block-secret-reads.sh.tmpl`, add a comment. It says that
   the hook does not stop mods, and it cites #91.
2. **Test for the mod check first** (#98, item 9). Write `tests/test-mod-check.sh` with
   fixture plugin trees:
   - a plugin with no mod;
   - a plugin with a `modules` key in `hooks/hooks.json`;
   - an `installed_plugins.json` that the script cannot read.

   Do not write a fixture for the `claude plugin validate` path. No real mod exists to
   verify it against.
3. **Mod check script** (#98, items 5–8). Add `home/dot_claude/hooks/mod-check.sh`
   (chezmoi name: `executable_mod-check.sh`, or `.tmpl` if it needs `.chezmoi.homeDir`).
   - Scan every installed plugin, enabled or disabled, from
     `~/.claude/plugins/installed_plugins.json`. Also scan `~/.claude/mods/plugins/*` when
     that tree exists.
   - Use jq only. Do not start node.
   - A finding is an installed plugin that has a `modules` key in `hooks/hooks.json`. Run
     `claude plugin validate` only on such a plugin. A classic command hook is not a finding.
   - Baseline: every mod is a finding until a mod is admitted (#98, item 4).
   - Clean result: no output.
   - Each finding: one line in the hook `systemMessage`:
     `<id> <version>: ships a mod — run mod admission (#91)`. If admission fails, add the
     refused items to the line.
   - If the check cannot run (jq missing, file missing, unknown format), show
     `mod check could not run: <reason>`. Never pass silently.
   - Exit code is not 0 when the script finds something. The hook does not block.
4. **SessionStart hook in the settings template** (#94 as amended by #98, item 5). In
   `home/.chezmoitemplates/claude-settings.json`, add a `SessionStart` command hook next to
   the `PreToolUse` entry. It runs `bash {{ .chezmoi.homeDir }}/.claude/hooks/mod-check.sh`.
   - `hooks` is already an owned key. The `$owned` list does not change.
   - The hook ownership rule of #73 removes and re-adds repo commands under
     `~/.claude/hooks/`. The new entry is under that path, so the rule covers it. Do not
     change the rule.
   - Extend `tests/test-claude-settings.sh` for the new entry.

## When the first mod is built

Nothing below happens now. A future decision that needs a mod starts here.

1. **Admission first** (#91). Run `claude plugin validate` on the applied mod. Refuse the
   mod if the `hooks:` line shows `tool.call`, `classic.PreToolUse` or `tool.check`, or the
   `calls:` line shows `fs.read` or `process.run`. A repo mod gets no exception. A mod that
   needs a refused item reopens #91.
2. **Source** (#92, items 4–5, 9). Repo path `home/dot_claude/exact_mods/`. It holds
   `dot_claude-plugin/marketplace.json` and one directory for each mod. It applies to
   `~/.claude/mods/`. Marketplace name: `dotfiles`. Plugin ids: `<mod>@dotfiles`.
3. **Trap** (#92, item 6). The source tree does not have the plugin layout. `claude
   --plugin-dir`, `claude plugin validate` and `claude plugin test` cannot run on it. Run
   them on `~/.claude/mods/` or on `chezmoi apply --destination <tmp>`.
4. **Settings template change** (#94, item 4). One change, in the same commit as the mod:
   - `extraKnownMarketplaces.dotfiles.source = {"source": "directory", "path": "{{ .chezmoi.homeDir }}/.claude/mods"}`.
     Use the absolute path. Expansion of `~` is not verified (#92, item 8).
   - `enabledPlugins["<mod>@dotfiles"] = true` for each mod.
   - All keys are already owned. The `$owned` list does not change.
   - Effect: apply reverts a `/plugin` toggle made at runtime. Apply is the gate (#92, item 3).
5. **Experiment A** (#88, #92 item 7). Verify that the mod loads from settings only, with no
   `/plugin` step and no trust prompt. If it fails, use `env.CLAUDE_CODE_PLUGIN_DIRS` in the
   settings template instead. Then the plugin id is `<mod>@inline`. Run the other #88
   experiments too: `.claude-plugin/types/` in a `directory` marketplace, and `~` in `path`.
   The findings are in `docs/research/local-plugin-marketplace.md`.
6. **Admitted-mods list** (#98, item 4). The first admission adds a repo list of admitted
   mods (`id` and version) in the same commit. The mod check stops reporting a listed mod.
7. **Tests for the mod** (out of scope on #85). The build session decides them.
   `claude plugin test` runs on the applied tree (item 3).
8. **Development loop** (#92, item 10). Edit the source. Run `chezmoi apply ~/.claude/mods`.
   Use a session that runs `claude --plugin-dir ~/.claude/mods/plugins/<mod>`. Claude Code
   watches that directory and reloads the mod on each apply.
9. **Mac desktop** (#89). The desktop Code tab is most likely 2.1.286, below the 2.1.287
   minimum. Check the version again before you expect a mod to load there.

## Known limit

`settings.local.json` can enable a mod on one machine. The template does not filter it.
Mod admission covers repo mods only (#94, item 5).

## Deferred

**Auto-update gate** (#98, item 1). The upgrade path if a mod ever fails admission: turn off
plugin auto-update, and update only through one script that runs the mod check first. It
needs research first: which setting turns off auto-update, and can chezmoi own it. Not part
of #85.

**Managed settings** (#91, item 5). Move `block-secret-reads` into managed settings if a mod
that fails admission is ever necessary. It needs root on each machine.

## Not verified — do not assume these

- The Mac desktop Code tab version. It is inferred from files, not seen (#89).
- The `hooks:` and `calls:` lines of `claude plugin validate`. Nobody saw them on a real mod
  (#98, item 11).
- Plugin auto-update for the installed marketplaces. Ten official plugins changed version at
  the same time on 2026-10-02. No log shows auto-update (#98, item 11).
- Experiment A and the other #88 experiments. Nobody ran them.
- Expansion of `~` in a marketplace `path` (#92, item 8).
- Coexistence of a mod surface with the `statusLine` row, and mod status in the desktop app
  (#86).
