# What changes from hindsight-memory 0.7.2 to the latest version, does it add a `modules` key, which files and credentials does it touch, which server version does it need, how does it pick a bank, and how can chezmoi pin it?

Ticket: myprysm/dotfiles#122

Versions and sources: The installed plugin is `hindsight-memory` 0.7.2 (cache `~/.claude/plugins/cache/hindsight/hindsight-memory/0.7.2/`, installed sha `a0af096`). The upstream is vectorize-io/hindsight, commit `f7dd3f4fd7420f7beec60c32c965e5e5cf7be066`, in a shallow clone with no tags (both sides). `CC/` means `hindsight-integrations/claude-code/` in that clone. `I/` means the installed copy. The server source is tag `v0.10.1`, read through raw.githubusercontent (codex) and `gh api` (Claude). The Claude Code docs are from code.claude.com, read 2026-10-04. They are not versioned. Claude Code is 2.1.289. Neither side ran an install, an update, a session or an authenticated API request. Neither side read credential files.

## Answer

The latest manifest version is 0.7.5. But 0.7.5 does not identify one snapshot, because upstream changes code without a version bump. The update adds six recall and notice keys and four env overrides. It raises the UserPromptSubmit hook timeout from 12 s to 45 s. It changes full-session retention to chunked deltas. It also prints a deprecation notice at each SessionStart.

Upstream supersedes this plugin with `@vectorize-io/hindsight-coding-agents`.

The update adds no `modules` key, so it is not a mod. It writes state, a venv and `last_recall.json` under `$CLAUDE_PLUGIN_DATA`. The credential is `hindsightApiToken` in `~/.hindsight/claude-code.json` or the env var `HINDSIGHT_API_TOKEN`.

The plugin declares no minimum server version. The server 0.10.1 source has every endpoint that the plugin calls. Runtime compatibility is not tested.

The bank comes from `directoryBankMap`, then the static `bankId` (`claude_code`), then a dynamic ID. Tags filter memories inside a bank. They do not select the bank.

To pin, use a marketplace `ref` (a branch or tag), or an operator-owned catalog with a `git-subdir` source and a full `sha`.

## Claims

1. **CONFIRMED.** The latest manifest says 0.7.5 (`CC/.claude-plugin/plugin.json:4`, `.claude-plugin/marketplace.json:4`, and the current remote manifest). The installed manifest says 0.7.2 (`I/.claude-plugin/plugin.json:4`) (both sides).
2. **UNVERIFIED.** Release commits: `395823f` v0.7.5 (2026-07-14), `b2508bf` v0.7.4 (2026-07-09), `0eb5276` v0.7.3 (2026-07-07). The manifest is 0.7.5 at tags v0.10.1 and v0.10.2. The latest source commit is `8bc5ab1` (2026-09-18, Cursor LLM provider). Source: `gh api` (Claude only). The codex remote fetches failed.
3. **CONFIRMED.** The version 0.7.5 does not identify one source snapshot. Upstream changes integration code and keeps the version. Source: issue vectorize-io/hindsight#2900, "Claude Code plugin.json version not bumped for v0.8.5 - plugin update is a no-op" (codex; Claude-chal confirmed).
4. **CONFIRMED.** The update adds six keys. No existing default changes. The keys are `recallTags` `[]`, `recallTagsMatch` `"any"`, `recallTagGroups` `null`, `recallAdditionalBankFilters` `{}`, `recallMinScores` `{}` (a client-side score filter), and `upgradeNotice` `true`. Sources: diff of I/ and CC/ `settings.json` and `scripts/lib/config.py:20-24`, `:42` (both sides).
5. **CONFIRMED.** The update adds four env overrides: `HINDSIGHT_RECALL_TAGS`, `HINDSIGHT_RECALL_TAGS_MATCH`, `HINDSIGHT_RECALL_TAG_GROUPS` and `HINDSIGHT_RECALL_ADDITIONAL_BANK_FILTERS`. A list accepts JSON or comma-separated text. Compound filters need JSON. Source: `CC/scripts/lib/config.py:82-85`, `:99-120` (both sides).
6. **CONFIRMED.** `requestTimeoutSeconds`, the `{user_id}` tag template and the drop of empty namespace tags are already in 0.7.2. `CC/CHANGELOG.md:7` still lists them under "Unreleased", so the changelog is stale. Sources: `I/scripts/lib/config.py:43`, `:78`; `I/scripts/retain.py:177-183` (both sides).
7. **CONFIRMED.** The UserPromptSubmit hook timeout goes from 12 s to 45 s (`CC/hooks/hooks.json:20`). (both sides). **UNVERIFIED:** the HTTP recall timeout stays at 10 s (`CC/scripts/recall.py:196`), and `requestTimeoutSeconds` overrides it (`CC/scripts/lib/client.py:55-57`). Only codex and the merge read this.
8. **CONFIRMED.** Full-session retain sends only new messages. Chunk 0 uses the document ID `session_id`. A later chunk uses `session_id-cN`. Compaction starts a new chunk. The checkpoint fields stay `message_count` and `chunk`. Sources: `CC/scripts/retain.py:97-145`, `:239`; `CC/scripts/lib/state.py:164-200` (both sides).
9. **CONFIRMED.** The checkpoint commits after a successful retain (both sides). **UNVERIFIED:** it also commits, with no API request, when the filtered transcript is empty. Source: `CC/scripts/retain.py:154-158` (codex-chal and the merge only).
10. **CONFIRMED.** Other changes in the code:
    - `recallAdditionalBanks` skips the primary bank and duplicates.
    - `_resolve_project_name` handles bare-hub repos (`.bare` gives the parent name) (`CC/scripts/lib/bank.py:32-49`, `:78-85`).
    - `run_mcp.sh` runs `cd "${CLAUDE_PLUGIN_DATA}"` and exports `HINDSIGHT_MCP_PROJECT_CWD`. `mcp_server.py:57` derives the bank from that value, with an empty session ID.
    - `llm.py` adds the `cursor` and `github-copilot` providers.
    - `client.py` drops `health_check`.

    Sources: the cited files and the I/ to CC/ diffs (both sides).
11. **CONFIRMED.** The plugin is deprecated. The doc `hindsight-docs/docs-integrations/claude-code.md:9-37` says "Superseded by the Coding Agents plugin ... still work; they are no longer developed". The replacement is `npx @vectorize-io/hindsight-coding-agents install claude-code`. It uses one bank for each repo, and all agents share that bank. The `coding-agents/README.md` has a migration section (about line 382). An update of this plugin does not do the migration (both sides).
12. **CONFIRMED.** `CC/scripts/session_start.py:25-31` and `CC/scripts/lib/upgrade_notice.py:1-43` print a deprecation `systemMessage` at each SessionStart, before the early returns. `"upgradeNotice": false` in `~/.hindsight/claude-code.json` stops it (both sides).
13. **UNVERIFIED.** Claude Code 2.1.289 shows a SessionStart `systemMessage` to the user (neither side tested it).
14. **CONFIRMED.** The update adds no `modules` key. `CC/hooks/hooks.json` has only top-level command hooks for SessionStart, UserPromptSubmit, Stop and SessionEnd. The installed hooks differ only in the timeout. `CC/.mcp.json` starts a stdio MCP server, `hindsight`, through `bash ${CLAUDE_PLUGIN_ROOT}/scripts/run_mcp.sh`. The plugin is not a mod by `CONTEXT.md:61` (both sides). **UNVERIFIED:** the hooks and MCP server run Python with full user access (one side only), and the v0.10.1 tag `hooks.json` has no `modules` (Claude only).
15. **CONFIRMED.** Normal hooks write under `${CLAUDE_PLUGIN_DATA}/state/`. The fallback is `~/.claude/plugins/data/hindsight-memory/state/` (`CC/scripts/lib/state.py:29-37`). The files are `turns.json` and `turns.lock` (`state.py:102`), `retention_tracking.json` and `retention_tracking.lock` (`state.py:210`), `bank_missions.json` (`bank.py:181-194`), `last_recall.json` (`recall.py:260-265`), and `daemon.json` (`daemon.py:240`, cleared at `:344`). JSON writes go through `.tmp` files (both sides).
16. **CONFIRMED.** `last_recall.json` holds the recalled memory text, the bank ID, the result count and a timestamp. Source: `CC/scripts/recall.py:261` (codex; Claude-chal confirmed).
17. **CONFIRMED.** MCP startup writes `${CLAUDE_PLUGIN_DATA}/venv/` and `${CLAUDE_PLUGIN_DATA}/requirements.txt` (`mcp>=1.0.0`). The launcher installs the dependencies when the cache differs or `mcp` does not import. Source: `CC/scripts/run_mcp.sh:6-47` (both sides).
18. **CONFIRMED.** The manual script `setup_hooks.py` rewrites `~/.claude/settings.json`. It replaces matching hook entries and sets `env.CLAUDE_PLUGIN_ROOT` (`CC/scripts/setup_hooks.py:16`, `:57-68`, `:133-146`). It reads `~/.hindsight/claude-code.json` only for `requestTimeoutSeconds`, and it never writes that file. No plugin code writes `~/.hindsight/claude-code.json`. `CC/README.md:25` says to make it by hand (both sides).
19. **UNVERIFIED.** Claude Code 2.1.289 needs `setup_hooks.py`. If it runs, it duplicates the hooks and conflicts with the chezmoi-owned `env` (neither side tested it).
20. **CONFIRMED.** The config load order is: defaults, `${CLAUDE_PLUGIN_ROOT}/settings.json`, `~/.hindsight/claude-code.json`, then env. A later entry wins. A null file value does not replace an earlier value. The user file survives updates. Source: `CC/scripts/lib/config.py:123-168` (both sides).
21. **CONFIRMED.** The credential is the key `hindsightApiToken` (`config.py:44`) or the env var `HINDSIGHT_API_TOKEN` (`config.py:72`). The client sends it as a Bearer header (`client.py:59-65`). The shipped `hindsightApiToken` is `null` and `hindsightApiUrl` is empty (`CC/settings.json`). The server-side `HINDSIGHT_API_TENANT_API_KEY` (`hindsight-api-slim/hindsight_api/extensions/builtin/tenant.py:45-52`) is not a plugin setting (both sides).
22. **CONFIRMED-CORRECTED.** Only local daemon mode writes files that hold credentials. The plugin skips the daemon when an external API configuration is present (`CC/scripts/lib/daemon.py:108`). In daemon mode it makes the `claude-code` embed profile. The embed code writes `~/.hindsight/profiles/claude-code.env` with `HINDSIGHT_API_LLM_API_KEY`, plus metadata, temp, log and lock files. `embedVersion` `"latest"` selects the embed package. Sources: `daemon.py:28-262`; `llm.py:51-133`; `hindsight-embed/hindsight_embed/profile_manager.py:187-238`, `:402-710` (codex; Claude-chal confirmed). **UNVERIFIED:** the profile directory is under `~/.hindsight`. Claude-chal left this open. The merge read `profile_manager.py:188`, which sets `CONFIG_DIR = Path.home() / ".hindsight"`, but the merge is not a second side.
23. **UNVERIFIED.** The local credential locations and values are not known. No one read them (both sides, by scope).
24. **CONFIRMED.** The plugin declares no minimum server version and does no version check. Sources: `plugin.json`, `requirements.txt`, `daemon.py:95`, `client.py:42`, README (both sides).
25. **CONFIRMED.** The server v0.10.1 source has the endpoints that the plugin calls (`hindsight_api/api/http.py` at v0.10.1):
    - recall, `POST /v1/default/banks/{bank}/memories/recall`, at line 5416, which takes `tag_groups`
    - retain, `POST .../memories`
    - `PATCH .../config` for `reflect_mission` and `retain_mission`
    - mental-models at lines 6207, 6370 and 6412

    The client calls are `client.py:101`, `:134` and `:155-162`, and `mcp_server.py:103-162` (both sides). The payload fields were not each checked. **UNVERIFIED:** the mental-model detail modes at lines 6094, 6152 and 8535 (codex only).
26. **UNVERIFIED.** The upgrade notice says Knowledge Pages need v0.9.x or later (`upgrade_notice.py:21-28`). That applies to the replacement integration. It is not a minimum for this plugin (both sides read it as an inference).
27. **CONFIRMED.** At v0.10.1, `helm/hindsight/Chart.yaml` has `version: 0.10.1` and `appVersion: "0.10.1"`. Clone HEAD has 0.10.2 (`Chart.yaml:5-6`). The release dates are 2026-09-21 (v0.10.1) and 2026-09-29 (v0.10.2) (both sides). **UNVERIFIED:** the tagged v0.10.2 chart, and a 404 from `repos/vectorize-io/charts` (Claude only). The chart version does not prove the image that runs.
28. **CONFIRMED-CORRECTED.** The server rejects `tags` and `tag_groups` together ("'tags' and 'tag_groups' are mutually exclusive"). The plugin sends both when both are set, with no guard (`CC/scripts/recall.py:180-195`; `client.py:110`). Correction: Claude cited line 547-548, which is clone HEAD. At v0.10.1 the check is at lines 470-474 (codex-chal) (both sides on substance).
29. **CONFIRMED.** Bank selection (`CC/scripts/lib/bank.py:94-165`):
    - `directoryBankMap` (realpath match) wins.
    - When `dynamicBankId` is false (the default), the plugin uses `bankId`. The code fallback is `"claude-code"` (`bank.py:26`). The shipped value is `claude_code`.
    - When dynamic, `dynamicBankGranularity` defaults to `["agent","project"]`, joined with `::`. The fields are `agent`, `project`, `session`, `channel` and `user` (`bank.py:29`).
    - `agent` is `agentName` (default `claude-code`). `project` is the repo basename. Worktrees resolve to the main repo (`resolveWorktrees` default true). `channel` and `user` come from `HINDSIGHT_CHANNEL_ID` and `HINDSIGHT_USER_ID`. `user` falls back to `anonymous`.
    - `bankIdPrefix` gives `<prefix>-<id>`.
    - The env overrides are `HINDSIGHT_BANK_ID`, `HINDSIGHT_DYNAMIC_BANK_ID` and `HINDSIGHT_AGENT_NAME` (`config.py:73-74`, `:91`).

    Sources: both sides.
30. **CONFIRMED.** The bare-repo name change (claim 10) can change dynamic bank IDs for bare-hub layouts (codex; Claude-chal confirmed `bank.py:78-85`).
31. **CONFIRMED.** The plugin sets the mission for each bank from `bankMission` and `retainMission`, while the bank is in its local tracking (`bank.py:168-200`) (both sides). **UNVERIFIED:** a failure can retry, and pruning lets a later repeat happen (codex-chal only).
32. **CONFIRMED.** Tags filter memories inside a bank. They do not select the bank. `retainTags` defaults to `["{session_id}"]`. Retain tags and metadata expand `{session_id}`, `{bank_id}`, `{timestamp}` and `{user_id}`. No env var sets `retainTags`. **UNVERIFIED:** recall tags pass through with no expansion (Claude did not check it; codex and the merge only). Additional banks inherit the recall filters unless `recallAdditionalBankFilters` overrides them. Sources: `CC/settings.json:33`; `CC/scripts/retain.py:185-214`; `CC/scripts/recall.py:180-219`; `config.py:70` (both sides, except the expansion point).
33. **UNVERIFIED.** Recall tags first came in 0.7.3 (Claude only).
34. **UNVERIFIED.** The behaviour of a session that is active during the upgrade is not known. The document ID shape changed. The checkpoint shape is compatible (both sides left this open).
35. **CONFIRMED.** The template enables `hindsight-memory@hindsight` with `extraKnownMarketplaces.hindsight` `{"source":"github","repo":"vectorize-io/hindsight"}`. It has no `ref`, no `sha` and no `autoUpdate`. Chezmoi owns and replaces `extraKnownMarketplaces` and `env`. Sources: `home/.chezmoitemplates/claude-settings.json:106-110`; `home/dot_claude/modify_private_settings.json:45`; `~/.claude/plugins/known_marketplaces.json` (lastUpdated 2026-06-28T15:01:13Z); `installed_plugins.json` (0.7.2, `a0af096`) (both sides).
36. **CONFIRMED.** Auto-update is off by default for this marketplace (#109 claim 1). `claude plugin install name@marketplace` and `claude plugin update` refresh the catalog anyway (#109 claim 9). `enabledPlugins` takes only true or false (#109 claim 28). Sources: `docs/research/marketplace-plugin-pinning.md`; plugins/loading.md "Versions and updates" (both sides).
37. **UNVERIFIED.** A bare-name `claude plugin install` (no `@marketplace`) does not refresh the catalog. Source: plugins/loading.md "When Claude Code refreshes a marketplace before an install" (codex-chal only).
38. **CONFIRMED.** The marketplace entry has a relative-path source, `"./hindsight-integrations/claude-code"` (`.claude-plugin/marketplace.json:13-17`). The manifest version gates the cache, so a commit with no version bump does not replace the cache. Sources: plugins/loading.md:270-300; host-marketplace "Release a new version" (both sides). The content of any one cached 0.7.5 copy is not checked.
39. **CONFIRMED.** The documented pin routes:
    - A marketplace `ref`: `extraKnownMarketplaces.<name>.source.ref`, or `marketplace add owner/repo#<ref>`. It selects a catalog branch or tag (marketplace-reference.md:348, :395-410; discover-plugins.md:208).
    - In an operator-owned catalog, a plugin source with `sha`. For this monorepo plugin, use `git-subdir` with path `hindsight-integrations/claude-code` and a full commit SHA (marketplace-reference.md:139-153; host-marketplace "Hold users on one version").
    - A `--plugin-dir` checkout.

    `claude plugin install` has no version or sha option (`--help`; #109 claim 10). The release tags v0.10.1 and v0.10.2 are candidate refs. Sources: both sides. **UNVERIFIED:** no `integrations/claude-code/*` tags exist (Claude only).
40. **UNVERIFIED.** A full SHA works as a marketplace-level `ref`. Release tags are immutable. A change of `ref` on a marketplace that was already added makes 2.1.289 fetch it again (neither side tested these).

## Corrections to earlier claims

- Claude claim 3, "checkpoint committed only after success": an empty filtered transcript also commits, with no request (claim 9).
- Claude claim 6 left out `last_recall.json` (claims 15, 16).
- Claude claim 12 cited `http.py:547-548`, which is clone HEAD. The v0.10.1 line is 470-474 (claim 28).
- Claude claim 19, "commit pin only via own marketplace with sha or --plugin-dir": this goes beyond the evidence. #109 leaves other indirect routes open (`marketplace-plugin-pinning.md:122`).
- Claude-chal claim 12 left the daemon profile path open. `CONFIG_DIR` is `~/.hindsight` (claim 22).
- Codex claim 21 says the checkpoint commits after a successful retain. Codex-chal added the empty-transcript case itself.

## Open points

- Which image version runs on the server, and do chart values override it?
- Does the plugin work at runtime with the API host? No authenticated request was made.
- Does Claude Code 2.1.289 show the SessionStart deprecation notice?
- Does 2.1.289 need `setup_hooks.py`?
- Does a full SHA work as a marketplace `ref`? Are the release tags immutable?
- What happens to a session that is active during the upgrade?
- The plugin declares no minimum server version.

## Consequences for the map

- Upstream supersedes this plugin with `@vectorize-io/hindsight-coding-agents`. That integration uses one bank for each repo, and all agents share it. Upstream no longer develops `hindsight-memory`. The choice between a bump to 0.7.5 and a move to coding-agents belongs to the operator. It bears on every ticket below (claims 11, 12).
- Enrollment #126: The bank comes from `directoryBankMap`, then the static `bankId` `claude_code`, then a dynamic `agent::project` ID. Worktrees resolve to the main repo. A bare-hub layout can change its dynamic ID after the update (claims 29, 30).
- Shared memory #127: With the shipped static bank, all projects share `claude_code`. Tags filter inside a bank. They do not separate banks. If `recallTags` and `recallTagGroups` are both set, every recall fails on the server (claims 28, 32).
- Credentials and guard #128: The token is `hindsightApiToken` in `~/.hindsight/claude-code.json` or `HINDSIGHT_API_TOKEN`. In daemon mode, `~/.hindsight/profiles/claude-code.env` holds an LLM API key. `last_recall.json` under `$CLAUDE_PLUGIN_DATA/state/` holds recalled memory text. Do not run `setup_hooks.py`: it rewrites the chezmoi-owned `settings.json` (claims 16, 18, 21, 22).
- Upgrade policy #129: "0.7.5" does not name one snapshot, and a commit with no version bump does not reach the cache. Auto-update is already off. An install with `@marketplace` refreshes the catalog anyway. One documented exact-pin route is an operator-owned catalog with `git-subdir` and a full `sha`. A `ref` to a release tag holds only the catalog. Chezmoi already owns `extraKnownMarketplaces`, the place for a pin (claims 3, 35, 36, 38, 39).
- Migration #130: The server 0.10.1 source has every endpoint that the plugin calls. The plugin declares no minimum version, so 0.10.1 is not ruled out. The update itself makes the UserPromptSubmit hook wait up to 45 s and adds a notice at each session. Set `upgradeNotice: false` to stop the notice (claims 7, 12, 24, 25, 27).
