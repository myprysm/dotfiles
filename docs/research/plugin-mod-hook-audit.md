# Enabled plugins: mod hooks before the secret guard

Research for #95. Part of #85. It builds on the research for #87
(branch `research/mod-hooks-vs-command-hooks`, file
`docs/research/mod-hooks-vs-command-hooks.md`).

Claude Code version: 2.1.288. Machine: the WSL machine. Date: 2026-10-03. Method: read only.
No file under `~/.claude` was changed. No plugin was validated, installed or disabled.

## Question

Do the enabled plugins register mod function hooks on `tool.call`, `classic.PreToolUse` or
`tool.check`? If yes, what does each hook do?

## Sources and labels

Each claim has one label.

- VERIFIED: a file and line, or a command output, shows it.
- UNVERIFIED: no source shows it. The note says what test would answer it.

Source keys:

- `[S]` — `home/.chezmoitemplates/claude-settings.json` in this repo.
- `[IP]` — `~/.claude/plugins/installed_plugins.json`.
- `[KM]` — `~/.claude/plugins/known_marketplaces.json`.
- `[MP-x]` — `~/.claude/plugins/marketplaces/<x>/.claude-plugin/marketplace.json`.
- `[C]` — `~/.claude/plugins/cache/`. Paths below are relative to it.
- `[R]` — `reference.md` of the `plugin-authoring` skill for 2.1.288:
  `/tmp/claude-1000/bundled-skills/2.1.288/91b17b2120cac2f738ba3bb47a070f87/plugin-authoring/reference.md`.
  The engine writes this file again at each load.
- `[PL]` — output of `claude plugin list` and `claude plugin list --json`.

## How a mod is declared

- A mod is a hooks module. `hooks/hooks.json` names it under the key `modules`. The module
  exports `register(on, options)`. VERIFIED `[R]` lines 11-14.
- The module and its imports must have one of these suffixes: `.ts`, `.tsx`, `.jsx`, `.js`,
  `.mjs`, `.cjs`, `.mts`, `.cts`. VERIFIED `[R]` line 14.
- Thus a `.js` or `.ts` file that no `hooks/hooks.json` names under `modules` is not a mod.
  VERIFIED by `[R]` lines 11-14.
- An entry with `"type": "command"` is a classic command hook. It is not a mod. It runs with the
  settings hooks, not before them. VERIFIED (#87 research, "Where settings hooks run in the
  order").
- Method limit: a hook blocks recursive content search through Bash, and this session had no
  Grep tool. Thus the files were not searched for `register(` or `tool.call`. The audit reads
  every `hooks/hooks.json` and every `.claude-plugin/plugin.json`, which are the files that
  declare hooks. VERIFIED (the hook refusal: "Recursive content search through Bash is blocked
  by policy").

## Enabled plugins and installed copies

- `[S]` lines 74-98 set eight plugins to `true`: `superpowers`, `ralph-loop`,
  `typescript-lsp`, `security-guidance`, `gopls-lsp`, `mattpocock-skills` (all
  `@claude-plugins-official`), `hindsight-memory@hindsight`, `caveman@caveman`. VERIFIED.
- The live `~/.claude/settings.json` has the same `enabledPlugins` values. VERIFIED (`jq
  '.enabledPlugins'`).
- `claude plugin list` shows the same eight as enabled, at the versions below. It lists no
  built-in plugin. VERIFIED `[PL]`.
- Every enabled plugin is installed. No enabled plugin is missing. VERIFIED `[IP]`, `[PL]`.
- `[IP]` lists one entry for each plugin. VERIFIED.

| Plugin | Active version `[IP]` | Other copies in `[C]` |
|---|---|---|
| superpowers | 6.4.1 | 6.3.0 |
| ralph-loop | 1.0.0 | none |
| typescript-lsp | 1.0.0 | none |
| security-guidance | 2.0.9 | 2.0.7, 2.0.8 |
| gopls-lsp | 1.0.0 | none |
| mattpocock-skills | 1.2.3 | none |
| hindsight-memory | 0.7.2 | none |
| caveman | 0d95a81d35a9 | none |

- The old copies (`superpowers/6.3.0`, `security-guidance/2.0.7`, `security-guidance/2.0.8`)
  have an empty `.in_use` folder. No session uses them now. VERIFIED (`ls -A .in_use`).
- Each old copy has only `"type": "command"` hooks and no `modules` key. VERIFIED (`jq` on each
  `hooks/hooks.json`).
- `mattpocock-skills`: the marketplace pins sha `c55ee46…` `[MP-claude-plugins-official]`. The
  installed copy has `gitCommitSha` `2ab9580…` `[IP]`. The installed copy is not the current
  pin. VERIFIED. The audit covers the installed copy only.

## Results per plugin

### superpowers 6.4.1

- `hooks/hooks.json` lines 3-15: one `SessionStart` hook, `"type": "command"`, runs
  `hooks/run-hook.cmd session-start`. No `modules` key. VERIFIED.
- `.claude-plugin/plugin.json` lines 1-20: no `hooks` key. VERIFIED.
- `index.js` at the root re-exports `./.opencode/plugins/superpowers.js`. Line 1 says it is the
  entry point for OpenCode. No `hooks/hooks.json` names it. VERIFIED (`index.js` lines 1-9).
- `hooks/hooks-cursor.json` exists. Its name is not `hooks/hooks.json`. It is for Cursor.
  VERIFIED (file name; `[R]` line 13 names only `hooks/hooks.json`).
- Verdict: NO MOD. One classic command hook on `SessionStart`.

### ralph-loop 1.0.0

- `hooks/hooks.json` lines 4-12: one `Stop` hook, `"type": "command"`, runs
  `hooks/stop-hook.sh`. No `modules` key. VERIFIED.
- `.claude-plugin/plugin.json` lines 1-9: no `hooks` key. VERIFIED.
- Verdict: NO MOD. One classic command hook on `Stop`.

### typescript-lsp 1.0.0

- The installed folder holds only `LICENSE`, `README.md` and `.in_use`. It has no
  `.claude-plugin/plugin.json` and no `hooks/` folder. VERIFIED (`ls -laR`).
- The marketplace entry has `"strict": false` and an `lspServers` block that runs
  `typescript-language-server --stdio`. It has no `hooks` key. VERIFIED
  `[MP-claude-plugins-official]`.
- Verdict: NO MOD. No hooks. It starts an LSP server process.

### gopls-lsp 1.0.0

- The installed folder holds only `LICENSE`, `README.md` and `.in_use`. VERIFIED (`ls -laR`).
- The marketplace entry has `"strict": false` and an `lspServers` block that runs `gopls`. It
  has no `hooks` key. VERIFIED `[MP-claude-plugins-official]`.
- Verdict: NO MOD. No hooks. It starts an LSP server process.

### security-guidance 2.0.9

- `hooks/hooks.json` lines 3-122: every hook is `"type": "command"`. Each runs
  `hooks/sg-python.sh` with a Python script. No `modules` key. VERIFIED.
- Events: `SessionStart` (line 4, `ensure_agent_sdk.py`), `UserPromptSubmit` (line 15),
  `PostToolUse` with matcher `Edit|Write|MultiEdit|NotebookEdit` (lines 25-34),
  `PostToolUse` with matcher `Bash` and `if` filters on `git commit`, `git push`, `gt create`,
  `gt modify`, `gt submit` (lines 35-95, `asyncRewake`), `Stop` (line 97), `SubagentStop`
  (line 110). VERIFIED.
- It has no `PreToolUse` hook. VERIFIED (same file).
- `.claude-plugin/plugin.json` lines 1-10: no `hooks` key. VERIFIED.
- Verdict: NO MOD. Classic command hooks only. None is on `PreToolUse`.

### mattpocock-skills 1.2.3

- The folder has no `hooks/` folder. VERIFIED (`ls -la`).
- `.claude-plugin/plugin.json` lines 1-48: a `skills` list, no `hooks` key. VERIFIED.
- `skills/misc/git-guardrails-claude-code/scripts/block-dangerous-git.sh` is a file inside a
  skill. The manifest does not register it as a hook. That skill is also not in the `skills`
  list (lines 21-47). VERIFIED.
- Verdict: NO MOD. No hooks.

### hindsight-memory 0.7.2

- `hooks/hooks.json` lines 3-47: every hook is `"type": "command"`. No `modules` key.
  VERIFIED.
- Events: `SessionStart` (`session_start.py`), `UserPromptSubmit` (`recall.py`), `Stop`
  (`retain.py`, `async`), `SessionEnd` (`session_end.py`). VERIFIED (lines 3, 14, 25, 37).
- `.claude-plugin/plugin.json` lines 1-8: no `hooks` key. VERIFIED.
- `.mcp.json` starts an MCP server: `bash scripts/run_mcp.sh`. VERIFIED (`.mcp.json` lines
  2-6; `[PL]` `mcpServers`).
- `settings.json` at the plugin root holds the plugin's own options (`autoRetain`,
  `retainToolCalls: false`, and others). It has no `hooks` key. VERIFIED (lines 1-38).
- Verdict: NO MOD. Classic command hooks only. None is on `PreToolUse`.

### caveman 0d95a81d35a9

- The folder has no `hooks/` folder, so it has no `hooks/hooks.json`. VERIFIED (`ls`: "No
  such file or directory").
- `.claude-plugin/plugin.json` lines 8-33 declare hooks inline. Both are `"type":
  "command"`: `SessionStart` runs `node src/hooks/caveman-activate.js`, `UserPromptSubmit`
  runs `node src/hooks/caveman-mode-tracker.js`. No `modules` key. VERIFIED.
- These `.js` files run under `node` as commands. They are not mod modules. VERIFIED (same
  lines).
- `.codex/hooks.json` and `plugins/caveman/.codex-plugin/` are for Codex. Claude Code reads
  `hooks/hooks.json` only. VERIFIED (paths; `[R]` line 13).
- Verdict: NO MOD. Two classic command hooks.

## Verdict table

| Plugin | Version | Mod | Classic command hooks | PreToolUse command hook | Verdict |
|---|---|---|---|---|---|
| superpowers | 6.4.1 | no | SessionStart | no | NO MOD |
| ralph-loop | 1.0.0 | no | Stop | no | NO MOD |
| typescript-lsp | 1.0.0 | no | none (LSP server) | no | NO MOD |
| security-guidance | 2.0.9 | no | SessionStart, UserPromptSubmit, PostToolUse, Stop, SubagentStop | no | NO MOD |
| gopls-lsp | 1.0.0 | no | none (LSP server) | no | NO MOD |
| mattpocock-skills | 1.2.3 | no | none | no | NO MOD |
| hindsight-memory | 0.7.2 | no | SessionStart, UserPromptSubmit, Stop, SessionEnd | no | NO MOD |
| caveman | 0d95a81d35a9 | no | SessionStart, UserPromptSubmit | no | NO MOD |

All rows are VERIFIED by the sections above.

## What this means for the guard

- No enabled plugin ships a mod. Thus no enabled plugin registers `tool.call`,
  `classic.PreToolUse` or `tool.check`. No enabled plugin uses `$.fs.read` or
  `$.process.run`, because those exist only in a mod. VERIFIED by the table.
- No enabled plugin has a classic `PreToolUse` command hook. Thus no plugin hook runs beside
  `block-secret-reads` on the same event. VERIFIED by the table.
- The classic command hooks run as normal processes with the user's rights. They can read any
  file the user can read. The guard does not cover them, because the guard checks tool calls
  only. VERIFIED (#87 research: the guard is a `PreToolUse` hook with matcher
  `Read|Grep|Bash`).
- The LSP plugins and the hindsight MCP server also start processes with the user's rights.
  VERIFIED `[MP-claude-plugins-official]`, `.mcp.json`.
- The finding holds for the copies installed today. A plugin update can add a `modules` key.
  VERIFIED (`mattpocock-skills` already has a different pin in the marketplace).

## Built-in plugins such as `sec-default@builtin`

- `/etc/claude-code` does not exist on this machine. Thus there is no managed settings file.
  VERIFIED (`ls`: "No such file or directory").
- The signed-in account is not a Team or Enterprise plan. VERIFIED (`jq` on
  `~/.claude.json` `oauthAccount`).
- The #87 research cites the docs: the built-in guard loads only with managed settings or for
  a Team or Enterprise sign-in. VERIFIED (#87 research, `[D-admin]`).
- `claude plugin list` does not list built-in plugins. VERIFIED `[PL]`.
- Thus `sec-default@builtin` probably does not load here. UNVERIFIED: this is an inference from
  the docs rule and the account fields. No log shows it. `~/.claude/debug` does not exist.
  Test: run `claude --debug`, then search the log for `cc-plugin-sec-default`.

## Open items

- Confirm that `sec-default@builtin` does not load, with the `--debug` test above.
- Check again after each plugin update. Check `hooks/hooks.json` for a `modules` key, and
  `plugin.json` for a `hooks` key.
- Other machines may have other plugin versions. This audit covers the WSL machine only.
