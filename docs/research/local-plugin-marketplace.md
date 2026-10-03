# How a local plugin marketplace loads

Research for #88. Part of #85. Claude Code 2.1.288.

Each fact is marked VERIFIED or UNVERIFIED.
VERIFIED means a URL, a command output or a file path is cited.
Doc URLs were fetched on 2026-10-03.

Sources:

- LOAD = https://code.claude.com/docs/en/plugins/loading
- MREF = https://code.claude.com/docs/en/plugins/marketplace-reference
- CMKT = https://code.claude.com/docs/en/plugins/create-marketplace
- SKILL = the `plugin-authoring` skill, `reference.md` (bundled with 2.1.288)

## 1. Copied or read in place?

Read in place. VERIFIED (LOAD, section "In-place and copied plugins").

- A relative-path plugin in a marketplace added from a local directory "loads in place from its path inside the marketplace folder".
- Its hook processes and MCP and LSP servers get a `CLAUDE_PLUGIN_ROOT` that points at the source directory.
- Every other marketplace plugin (github, git-subdir, url, npm, archive, `command` copy mode) is copied to `cache/<marketplace>/<plugin>/<version>/`.

The marketplace itself is not copied either. VERIFIED (LOAD, "Find plugins on disk").

- A marketplace from a local `file` or `directory` source "has no copy" under `marketplaces/`.
- Its `installLocation` in `known_marketplaces.json` is the path you gave.

Local contrast. VERIFIED (`~/.claude/plugins/known_marketplaces.json`, read-only).

- The three marketplaces there are all `github` sources.
- Each has an `installLocation` under `~/.claude/plugins/marketplaces/`.
- No local `directory` marketplace exists on this machine, so there is no on-disk sample of one.

The entry must use a relative `source`. VERIFIED (MREF, "Plugin sources").

- Start it with `./`. `"."` alone means the marketplace root.
- A `..` fails `claude plugin validate`.
- The root is the directory that holds `.claude-plugin/`.
- A `directory` marketplace source takes `path` = the marketplace root (MREF, "Fields by type").
- A non-relative entry source (for example `github`) would still copy to the cache. VERIFIED (LOAD).

The `source` object shape for settings. VERIFIED (MREF, "Marketplace sources" table).

```json
{ "extraKnownMarketplaces": { "<name>": { "source": { "source": "directory", "path": "<abs path>" } } } }
```

- The table says `directory` with `path` "Loads" under `extraKnownMarketplaces`.
- The fetched settings-reference page did not show a `directory` example.
  The block above is built from MREF's table, not copied from a doc example.
- Marketplace name rules: MREF "Reserved names" and "Top-level fields". The names `inline`, `skills-dir`, `synced` and `builtin` are reserved.
- Whether `~` or `$HOME` expands in `path`: UNVERIFIED. Use an absolute path that chezmoi templates in. Experiment: section 6, test D.

## 2. Does hot reload see a file that `chezmoi apply` changes?

Not a file watch. Only `/reload-plugins` or a restart. VERIFIED (CMKT "Test an edit to a plugin"; LOAD "In-place and copied plugins").

- CMKT: edits "take effect at the next session start or when you run `/reload-plugins` in a session, with no change to the plugin's `version`".
- LOAD: the running session keeps its loaded set until `/reload-plugins` or a new session.
- LOAD: a local-directory plugin "loads its current source files at every session start, whatever its version string says". No version bump is needed.

The mod hot-reload watch does not cover this path. VERIFIED by omission (SKILL).

- SKILL lists what the engine watches: the mods folder (once enabled), `--plugin-dir` and `CLAUDE_CODE_PLUGIN_DIRS` folders, and skills-dir plugins.
- A local-marketplace plugin is not on that list.
- UNVERIFIED: whether a plugin loaded from a local marketplace gets a file watch anyway. The docs do not say it does.
- Experiment: section 6, test B.

Version string with no git. VERIFIED (LOAD, "How Claude Code computes the version").

- Local directory, neither plugin nor marketplace a git repository: version is `unknown`, unless `plugin.json` or the entry sets `version`.
- LOAD: "Claude Code doesn't take the version from a repository that encloses the install path".
- Whether the version matters for an in-place plugin: LOAD says it does not affect loading.

## 3. What Claude Code writes into the plugin directory

Documented writes. VERIFIED (SKILL `reference.md`, the paragraph that starts "A mod the engine loads from a folder the person owns").

- For a plugin loaded "from a folder the person owns (the mods folder after `Enable for this session`, a `--plugin-dir` or `CLAUDE_CODE_PLUGIN_DIRS` folder)", the engine lays types into `<plugin>/.claude-plugin/types/` "at every load and reload".
- Contents: `claude-code/index.d.ts`, `claude-code-tools/index.d.ts`, `claude-code-mcp/index.d.ts`, one folder per `dependencies` plugin, and `tsconfig.json`.
- `claude-code-mcp/index.d.ts` is refreshed when the mod is saved.

Not documented. UNVERIFIED.

- Whether a plugin loaded through a local `directory` marketplace gets `.claude-plugin/types/` written. SKILL does not list marketplace loads among the folders. If the plugin is a mod and loads in place, the same write is plausible. No source says so.
- Whether Claude Code writes anything else into an in-place plugin directory. LOAD names `.orphaned_at` markers only for old cache version directories, so not for an in-place source.
- LOAD: for an in-place plugin, Claude Code does not install Node dependencies into the source directory ("Install them there yourself, or from a hook into `${CLAUDE_PLUGIN_DATA}`"). VERIFIED. No `node_modules` write is expected from Claude Code.
- Persistent plugin data goes to `~/.claude/plugins/data/<plugin-id>/`, outside the plugin directory. VERIFIED (LOAD, "Find plugins on disk"; the directory exists locally, `ls ~/.claude/plugins/data`).
- Where `$.store` (across sessions) lives on disk: UNVERIFIED.

Consequence for the repo. This is a proposal, not a decision.

- `.claude-plugin/types/` is generated at load and reload. Do not commit it.
- A `types/index.d.ts` at the plugin root is different. It is the plugin's own state contract, named in `plugin.json` as `"types"` (SKILL.md). It is authored, so it belongs in the repo.
- If chezmoi writes the plugin tree and Claude Code adds files into it, chezmoi will not remove them on `apply` unless the source directory is marked exact. Not tested. UNVERIFIED.
- `claude plugin validate <path>` and `claude plugin test [dir]` exist in 2.1.288 (output of `claude plugin --help`).

## 4. Can `enabledPlugins` enable it with no `/plugin install`?

The docs say yes for relative-path plugins. One gap remains.

VERIFIED (LOAD, "Check which stage a plugin reached" and "Plugins and marketplaces that aren't on disk at session start"):

- Settings declare the marketplace in `extraKnownMarketplaces` and the plugin in `enabledPlugins`.
- After the session starts, a marketplace "that settings declare but `known_marketplaces.json` lacks" is cloned. Then plugins reload and enabled plugins that are not cached yet are downloaded.
- So a settings-only declaration starts the fetch step. No interactive command is named as required.

VERIFIED (LOAD, "Enabled in project settings but not installed"):

- A relative-path plugin "needs no install record because it loads from the marketplace itself".
- That sentence sits under the project-settings case. It states the general rule for relative-path plugins.
- A `true` in user settings fetches any source type (same section). `~/.claude/settings.json` is the user scope, which the chezmoi merge owns.

VERIFIED (MREF, `defaultEnabled`): the entry's `defaultEnabled` defaults to `true` "when the user hasn't set it in `enabledPlugins`". Write the key explicitly anyway.

The key format. VERIFIED (LOAD, "Find where a plugin came from"): `"<entry-name>@<marketplace>": true`. The entry name is the key, not the manifest name. Keep the two the same (CMKT "Keep the entry name and the manifest name the same").

Existing repo shape. VERIFIED (`home/.chezmoitemplates/claude-settings.json`, lines 97-107): `enabledPlugins` has `"caveman@caveman": true`. `extraKnownMarketplaces` holds `github` sources.

UNVERIFIED gaps:

- Whether the "clone" path works for a `directory` source with no `/plugin` step. Also whether the first run needs a restart or `/reload-plugins`. LOAD shows `Plugins changed. Run /reload-plugins to activate.` only for a changed source.
- Whether a trust prompt appears for a `directory` source in user settings. LOAD names the workspace trust dialog only for project-scope `extraKnownMarketplaces` and project plugins.
- Whether `claude plugin list` shows the plugin before its first load.

## 5. Other facts that bear on #92

- Plugins load at session start from `installed_plugins.json` and the cache "without using the network" (LOAD). VERIFIED. An in-place plugin has no cache entry.
- Auto-update is off by default for a non-official marketplace (LOAD, "Which marketplaces and plugins auto-update"). VERIFIED. Claude Code skips the pre-install refresh for a local `file` or `directory` marketplace (LOAD, "When Claude Code refreshes a marketplace before an install"). VERIFIED.
- `claude plugin marketplace add <path>` writes `extraKnownMarketplaces` in user settings (CMKT step 4; LOAD "Declared, in settings"). VERIFIED. The chezmoi merge owns that key, so a manual add can drift. Not tested.
- `marketplace add --scope` takes `user` (default), `project` or `local`. VERIFIED (`claude plugin marketplace add --help`).
- `--plugin-dir` and `CLAUDE_CODE_PLUGIN_DIRS` are a different route. The id is `<name>@inline`. It is session-only, in place and watched. It overrides a same-named marketplace plugin (LOAD "Name conflicts"). VERIFIED. `CLAUDE_CODE_PLUGIN_DIRS` may be set in the `env` block of `~/.claude/settings.json`, never a project's (SKILL `reference.md`). VERIFIED. This route needs no marketplace and no `enabledPlugins` key. It is the only route that SKILL documents as watched and as getting the types write.
- A mod is a plugin with `.claude-plugin/plugin.json` and `hooks/hooks.json` (SKILL.md). VERIFIED. Whether a marketplace-loaded plugin runs its hooks module as a mod, with hot reload: UNVERIFIED.
- Cloud sessions skip `extraKnownMarketplaces` from a repository (LOAD, "Plugins shared through a repository"). VERIFIED for project scope only.

## 6. Experiments to settle the UNVERIFIED items

Run them on a scratch config, never on the real `~/.claude`. Whether 2.1.288 honors a `CLAUDE_CONFIG_DIR` override: UNVERIFIED. Otherwise use a disposable VM, container or user.

Setup:

1. Create `/tmp/mkt/.claude-plugin/marketplace.json` with `name: "local-test"`, `owner.name`, and one entry `{ "name": "probe", "source": "./plugins/probe" }`.
2. Create `/tmp/mkt/plugins/probe/` with `.claude-plugin/plugin.json` (`name: "probe"`, `version: "0.1.0"`) and a skill or a hooks module, so the load is visible.
3. `claude plugin validate /tmp/mkt` must pass.
4. In the scratch user settings, with no `marketplace add` and no `install`, set `extraKnownMarketplaces.local-test.source = { "source": "directory", "path": "/tmp/mkt" }` and `enabledPlugins["probe@local-test"] = true`.

Test A, enable with no install (section 4).
- Start `claude`. Wait. Run `claude plugin list` and `/plugin`.
- Record: does the plugin appear, is `known_marketplaces.json` written, is a restart or `/reload-plugins` needed, is there a trust prompt.
- Record whether `installed_plugins.json` changes and whether `cache/local-test` exists. Expect no cache entry.

Test B, file change visibility (section 2).
- With the session open, edit the probe plugin (change the skill text or hook output). Do not run `/reload-plugins`. Check the behavior.
- Run `/reload-plugins`. Check again.
- Replace the file by write-temp-then-rename, as chezmoi does. Check again.
- Restart. Check again.

Test C, generated files (section 3).
- `git init` in `/tmp/mkt` and commit before test A.
- After tests A and B, run `git -C /tmp/mkt status --ignored`.
- Record every path Claude Code created: `.claude-plugin/types/`, `node_modules`, others.
- Repeat with `CLAUDE_CODE_PLUGIN_DIRS=/tmp/mkt/plugins/probe` for contrast.

Test D, `~` in `path`.
- Set `"path": "~/mkt"` and check whether the marketplace loads.
