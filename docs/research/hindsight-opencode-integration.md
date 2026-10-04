# What does the Hindsight opencode integration deliver, how is it installed and configured, can it share a bank with Claude Code, and how is it pinned?

Ticket: myprysm/dotfiles#124

Versions and sources:
- Upstream source: vectorize-io/hindsight, commit `f7dd3f4fd7420f7beec60c32c965e5e5cf7be066`. Paths are relative to the clone. **O** = `hindsight-integrations/opencode`, **C** = `hindsight-integrations/coding-agents`, **D** = `hindsight-docs/docs-integrations`.
- Integration: `@vectorize-io/opencode-hindsight` 0.2.8.
- **I** = the installed Claude plugin `hindsight-memory` 0.7.2.
- opencode: 1.18.34 (local binary). Codex read the opencode source at tag `v1.18.34` (anomalyco/opencode). Claude read WebFetch summaries of the same files.
- Nobody installed anything, made a server request or read a credential file.

## Answer

The integration is a pure opencode plugin. It gives three native tools and three hooks. It has no MCP server and no skills.

To install it, put `"@vectorize-io/opencode-hindsight"` in the opencode `plugin` array. opencode then fetches the package.

Configuration has four layers. Later layers win: defaults, `~/.hindsight/opencode.json`, tuple options, environment. The token goes in `hindsightApiToken` or `HINDSIGHT_API_TOKEN`.

opencode can share a bank with Claude Code. Each side must resolve the same effective bank ID against the same API and tenant. The defaults differ (`opencode` and `claude_code`), so nothing is shared out of the box. Nobody tested sharing.

To pin the plugin, use the exact spec `@vectorize-io/opencode-hindsight@0.2.8`. A bare name resolves to `@latest`.

Upstream marks this package as superseded by `@vectorize-io/hindsight-coding-agents`. The package still works, but it is no longer developed.

## Claims

1. **CONFIRMED.** The plugin returns native tools and hooks. It does not deliver an MCP server or skills. The package is ESM and MIT licensed. It needs node >=22. Its published files are `dist` and `README.md`. Its dependencies are `@opencode-ai/plugin ^1.3.13` and `@vectorize-io/hindsight-client ^0.10.1`. Sources: `O/package.json:2-3,10-13,31-46`; `O/src/index.ts:37-82` (return at 78-81) (both sides).
2. **CONFIRMED.** The tools are `hindsight_retain`, `hindsight_recall` and `hindsight_reflect`. The plugin calls the Hindsight HTTP client directly. Sources: `O/src/tools.ts:16-19,32,59,86,111`; `O/src/index.ts:52-55` (both sides).
3. **CONFIRMED.** The plugin has three hooks:
   - `event`: on `session.idle`, it retains after enough new user turns. The default is every 3 user turns.
   - `experimental.chat.system.transform`: it recalls once per session and appends the result to `system[0]`.
   - `experimental.session.compacting`: it retains, and then it injects recalled memories into the compaction context.

   Auto recall and auto retain are on by default. Sources: `O/src/hooks.ts:195-347`; `O/src/config.ts:56-75` (both sides).
4. **CONFIRMED.** Upstream marks the package as superseded by `@vectorize-io/hindsight-coding-agents`. The docs say "This page and the published package still work; they are no longer developed." The successor source version is 0.8.0. Sources: `D/opencode.md:9-22` (I re-read it); `C/package.json:3` (both sides).
5. **UNVERIFIED.** On 2026-10-04 the npm registry showed `opencode-hindsight` latest 0.2.8, published 2026-07-21 and not deprecated. It showed `hindsight-coding-agents` latest 0.8.0. Source: Claude only, from a WebFetch summary. The codex registry access failed.
6. **CONFIRMED.** The old opencode doc page contradicts the code. The page lists `project` but not `gitProject`, and it calls `HINDSIGHT_API_URL` "required". The code has `gitProject`, and it defaults the URL to Hindsight Cloud. The README is more accurate. Sources: `D/opencode.md:142,178`; `O/src/bank.ts:23`; `O/src/config.ts:16,81` (both sides).
7. **CONFIRMED.** To install the plugin, add `"plugin": ["@vectorize-io/opencode-hindsight"]` to `opencode.json`. This can be the project file or `~/.config/opencode/opencode.json`. You do not run a separate `npm install`. Source: `O/README.md:16-27` (both sides).
8. **DISPUTED.** Which installer opencode uses, and which cache path:
   - Claude (opencode.ai/docs/plugins): Bun installs the package at startup into `~/.cache/opencode/node_modules/`.
   - Codex (versioned source `packages/core/src/npm.ts:79-100`): 1.18.34 uses npm Arborist and `<cache>/packages/<specifier>`.

   Claude found no `~/.cache/opencode/node_modules`. That absence does not prove that the newer cache layout is empty.
9. **CONFIRMED.** Options go in a tuple `["@vectorize-io/opencode-hindsight", {...}]`. The plugin passes them to `loadConfig`. Sources: `O/README.md:50-87`; `O/src/index.ts:37-38` (both sides). **UNVERIFIED:** the 1.18.34 schema accepts tuples (opencode `packages/core/src/v1/config/plugin.ts:5-8` and the loader `plugin/index.ts:107-116`; codex only, Claude did not check them).
10. **CONFIRMED.** Configuration has four layers. Later layers win: defaults, then `~/.hindsight/opencode.json`, then tuple options, then environment. The Hindsight file goes through `JSON.parse`, so it must be JSON and not JSONC. Source: `O/src/config.ts:4-9,135-175` (both sides).
11. **CONFIRMED-CORRECTED.** A missing or invalid `~/.hindsight/opencode.json` adds no settings. Tuple options and environment still apply. So the result is not always the bare defaults with the Cloud URL. Source: `O/src/config.ts:135-175` (both sides).
12. **CONFIRMED.** The token field is `hindsightApiToken`. It can go in `~/.hindsight/opencode.json` or in tuple options. `HINDSIGHT_API_TOKEN` has the highest priority. The URL comes from `hindsightApiUrl` or `HINDSIGHT_API_URL`. `debug` has no environment variable. Sources: `O/src/config.ts:39-41,98-124,148-175`; `O/README.md:89-128` (both sides).
13. **CONFIRMED.** The plugin passes the token as the client `apiKey`. The client sends `Authorization: Bearer <apiKey>`. The plugin does not read `HINDSIGHT_API_TENANT_API_KEY`, so that server-side name does not apply to the client. Sources: `O/src/index.ts:52-55`; `O/src/config.ts:98-124`; `hindsight-clients/typescript/src/index.ts:345-357` (both sides).
14. **CONFIRMED.** A missing token does not stop the plugin from loading. Requests fail when a call is made. Nobody tested the server rejection. Source: `O/src/index.ts:47-55` (both sides).
15. **CONFIRMED.** A token that is written literally in the tracked `home/dot_config/opencode/opencode.json` goes into the public repo. The private places for it are the environment and `~/.hindsight/opencode.json`. Sources: `home/dot_config/opencode/opencode.json:1-9`; `O/src/config.ts:99-100,148-175` (both sides).
16. **CONFIRMED.** opencode config supports `{env:VAR}` and `{file:path}` substitution. The loader for `~/.hindsight/opencode.json` does no substitution. Sources: opencode.ai/docs/config#variables; `O/src/config.ts:135-142` (both sides).
17. **UNVERIFIED.** Substitution also works inside plugin tuple options, because opencode substitutes the full config text before it parses it. Source: codex only (`packages/opencode/src/config/variable.ts:30-35`; `packages/opencode/src/config/config.ts:216-224`). Claude saw no proof of this.
18. **CONFIRMED.** The static bank is `bankId` or `HINDSIGHT_BANK_ID`. The default is `opencode`. A non-empty `bankIdPrefix` gives `<prefix>-<bank>`. The tools always use the bank that the plugin resolved, and their arguments cannot change it. Sources: `O/src/bank.ts:22,94-100`; `O/src/config.ts:84-91,101,110-112`; `O/src/tools.ts:25-105` (both sides).
19. **CONFIRMED.** Dynamic mode (`dynamicBankId` or `HINDSIGHT_DYNAMIC_BANK_ID`) replaces the static bank. It joins fields with `::`. The fields are `agent`, `project`, `gitProject`, `channel` and `user`. The default is `["agent","project"]`, which gives `opencode::<cwd-basename>`. `gitProject` uses `git rev-parse --git-common-dir`, so worktrees share a bank. There is no `session` field. Sources: `O/src/bank.ts:22-23,36-86,102-132`; `O/README.md:161-171` (both sides).
20. **CONFIRMED-CORRECTED.** The plugin derives the bank once for each plugin instance, before it creates the tools and hooks. It uses `input.directory` and the environment. The code does not guarantee one bank for the whole process. Source: `O/src/index.ts:57-75` (both sides).
21. **CONFIRMED.** If `bankMission` is set, the plugin calls `createBank` with the mission on first use. Bank creation is lazy, and you do not need a setup step. Sources: `O/src/bank.ts:139-168`; `O/src/tools.ts:47-50` (both sides).
22. **CONFIRMED.** In I, `settings.json:3` ships `bankId` `claude_code` (underscore). The code fallback is `claude-code` (hyphen, `I/scripts/lib/bank.py:26`). `dynamicBankId` is false (`settings.json:29`). Nothing is shared by default (both sides).
23. **CONFIRMED.** Both clients use the same env names `HINDSIGHT_BANK_ID`, `HINDSIGHT_API_URL` and `HINDSIGHT_API_TOKEN`. Both join with `::` and support `bankIdPrefix`. `O/src/bank.ts:4` calls the file a port of Claude's `bank.py`. To share a bank, the two sides must match the API host, the authorized tenant and the effective bank ID. An equal `bankId` is not enough if dynamic mode, a prefix or a directory map is active. Claude's `directoryBankMap` has priority over its static bank. Sources: `I/scripts/lib/config.py:64-81,113-144`; `I/scripts/lib/bank.py:85-143` (both sides).
24. **CONFIRMED.** Sharing a dynamic bank is fragile:
   - Claude's fields are `agent|project|session|channel|user`. Claude has no `gitProject`, but its `project` follows the git common dir.
   - The two sides have different `agent` defaults.
   - opencode has no directory map.

   Sources: `I/scripts/lib/bank.py:29,48-90,109-123`; `O/src/bank.ts:23,94-132` (both sides).
25. **CONFIRMED.** Neither side adds an agent tag by default. The opencode retain context is `"opencode"`. The recall defaults differ: opencode uses `["world","experience"]` and I uses `["observation"]`. So a shared bank does not give the same recall results. Sources: `O/src/config.ts:61,76-77`; `I/settings.json:11,20,22`; `I/scripts/lib/client.py:61-67,120,147` (both sides).
26. **UNVERIFIED.** Sharing works against the deployed server. Nobody tested it (both sides).
27. **CONFIRMED.** opencode uses its session ID as the retain document ID. Source: `O/src/hooks.ts:168-177` (both sides). **UNVERIFIED:** that it never collides with Claude IDs. Claude also uses its session ID with no namespace (`I/scripts/retain.py:165-175`, codex).
28. **CONFIRMED (as documented).** The successor command `npx @vectorize-io/hindsight-coding-agents install opencode` (or `opencode2`) does these things:
   - it writes a plugin entry into `~/.config/opencode/opencode.json`, with native tools and no MCP.
   - it copies the runtime to `~/.hindsight/coding-agents`.
   - it backs up each file that it changes as `<file>.hindsight-backup`.
   - it asks questions interactively, or it takes `--server cloud|self-hosted|daemon`.

   The manual form is `{"plugin":["/path/to/hindsight-coding-agents"]}`. Source: `D/coding-agents.md:50-52,95-120,344-369` (both sides). Nobody ran the install.
29. **CONFIRMED.** The successor reads one file, `~/.hindsight/coding-agent.json`. Later layers win for each field. Layers 4 and 5 and the `HINDSIGHT_CONFIG` override are **UNVERIFIED** (codex and the merge only):
   1. defaults
   2. env (`HINDSIGHT_API_URL`, `HINDSIGHT_API_TOKEN`, `HINDSIGHT_<FIELD>`)
   3. the file's top level
   4. `harnesses.<name>`
   5. `paths.<prefix>`
   6. `banks.<id>`

   Env is a fallback, and the file wins where it sets a value. The keys include `apiUrl`, `apiToken`, `bankId` and `mapPathToBank`. Logs go to `~/.hindsight/coding-agents-logs/`. Source: `C/README.md:494-515,586-591,1084` (both sides, except as marked).
30. **CONFIRMED (as documented).** The successor install takes the endpoint from the old `~/.hindsight/claude-code.json` or `codex.json`. It maps `hindsightApiUrl` to `apiUrl` and `hindsightApiToken` to `apiToken`. Source: `D/coding-agents.md:380-392` (both sides).
31. **CONFIRMED (as documented).** The successor's default bank is `coding-agent::{gitProject}`. That is one bank for each repo, and every harness shares it. Claude Code also shares it when the successor wires Claude. `bankId` overrides the default, and `mapPathToBank` overrides `bankId`. Migration does not move memory, and opencode history cannot be imported. Sources: `C/README.md:316,587-590,933-944`; `D/opencode.md:21`; `D/coding-agents.md:394-409` (both sides).
32. **CONFIRMED (as documented).** The successor's Claude wiring puts 3 hooks into `~/.claude/settings.json` and adds MCP with `claude mcp add`. Source: `D/coding-agents.md:58-64` (both sides). **UNVERIFIED:** double capture when the `hindsight-memory` plugin also runs. This is an inference, and nobody tested it.
33. **CONFIRMED.** By default the successor updates itself (`autoUpdate: true`). Once a day at session start, it checks npm and re-stages `~/.hindsight/coding-agents`. `false` pins the version. Source: `C/README.md:37,625` (both sides). **UNVERIFIED** (codex correction, not confirmed by Claude): this applies only to an `npx` install; it does not touch a global install, a vendored copy or a checkout; it does not rewire host config, so a new hook entry point still needs a manual `install`.
34. **CONFIRMED.** The repo tracks only `home/dot_config/opencode/opencode.json`. That file holds the instructions path and a disabled provider, with no Hindsight entry. The per-machine `opencode.jsonc` is not tracked (#78). Sources: `home/dot_config/opencode/opencode.json:1-9`; `home/.chezmoiignore:83-88` (both sides).
35. **CONFIRMED.** The opencode 1.18.34 global loader deep-merges `config.json`, then `opencode.json`, then `opencode.jsonc`. Only `instructions` is concatenated. Sources: opencode `config/config.ts:41-45,245-255` (both sides).
36. **CONFIRMED-CORRECTED.** Plugin arrays in the global JSON and JSONC files are not concatenated (correction to Claude claim 29). **UNVERIFIED:** tuple option objects are not merged (codex only). **UNVERIFIED:** the result when both files carry `plugin`. Codex says plugin-origin dedupe keeps the later whole registration by package name (`config/config.ts:318-340`; `config/plugin.ts:58-69`). Claude says the JSONC array may replace the JSON array, and that this needs a test.
37. **CONFIRMED.** The bare name resolves to `@latest`. opencode keeps an exact version spec such as `@vectorize-io/opencode-hindsight@0.2.8`. It also accepts a local path. The installer reuses an existing cache entry, so a bare name is not a reproducible pin, and it does not refresh on every start. Source: opencode `plugin/shared.ts:20-31,158-195`; `core/src/npm.ts:79,114-135` (both sides, Claude from summaries). **UNVERIFIED:** that the cache directory is keyed by the full spec, so that a pin bump reinstalls (codex only).
38. **CONFIRMED.** The package uses `^` ranges for dependencies and does not ship its `package-lock.json`. Source: `O/package.json:31-34,44-46`; `O/package-lock.json:1-14` (both sides).
39. **CONFIRMED.** The release tag is `integrations/opencode/v<semver>`. The changelog `## [0.2.8]` maps to tag `integrations/opencode/v0.2.8`. CI publishes to npm with `--provenance`. opencode is in the integration lists. This version is separate from Claude 0.7.2 and from the server/chart version. Sources: `scripts/release-integration.sh:16,98,161-172`; `scripts/check-integration-releases.sh:13`; `.github/workflows/release-integration.yml:184-205`; `hindsight-docs/src/pages/changelog/integrations/opencode.md:13` (both sides).
40. **CONFIRMED.** The clone is shallow and shows one commit for the opencode dir. Release cadence cannot be found from it (both sides).
41. **CONFIRMED.** The local opencode is 1.18.34 from Homebrew. **UNVERIFIED:** that `^1.3.13` runs on 1.18.x, that the experimental hook names stay stable, and that the server accepts client `^0.10.1` (both sides).
42. **CONFIRMED.** The integration is not a "mod" in this repo's sense. It is an opencode plugin, not a Claude Code plugin with `hooks/hooks.json` modules. Sources: `CONTEXT.md:61-66`; `O/src/index.ts:78-81`; `I/hooks/hooks.json:1-49` (both sides).

## Corrections to earlier claims

- Claude's citations for `index.ts` were off by 168 lines. The real lines are 37-82 for the plugin function, 52-55 for the client and 57 for the bank (both challenges).
- Claude claim 29 (plugin arrays are concatenated and deduped across JSON and JSONC) is withdrawn for files in the same directory (claim 36).
- Claude claims 30 and 35 ("npm semver only, no user lock", "pinning undocumented") are corrected. An exact version spec and a local path work (claim 37).
- Claude claim 12 is corrected. Tuple options and env still apply when the Hindsight file is missing (claim 11).
- Claude claim 14 is refined. Codex lists six layers; layers 4 and 5 stay UNVERIFIED (claim 29).
- Codex says Claude claim 36 needs a limit: auto-update applies only to an `npx` install. This stays UNVERIFIED (claim 33).
- The Codex report left out the supersession. Codex accepted this gap (claim 4).

## Open points

- Does `plugin` in `opencode.jsonc` replace the entry in `opencode.json`, or does dedupe keep the later entry? Test this on 1.18.34.
- Is the opencode package cache keyed by the full spec? Which installer and cache path does 1.18.34 use?
- Does `{env:VAR}` work inside tuple options? Test it.
- Do the experimental hooks run on 1.18.34? Does the deployed server accept client 0.10.x?
- Is the npm artifact for 0.2.8 published, and what does it contain?
- Does the successor `install` change the chezmoi-managed `opencode.json`? If it does, it conflicts with chezmoi. This is likely, but nobody verified it.
- Which `recallTypes` should a shared bank use? This is a design decision.

## Consequences for the map

- Map #121: upstream supersedes `opencode-hindsight` with `@vectorize-io/hindsight-coding-agents`, which covers Claude Code, codex, opencode and others. The successor has one config file and one bank for each repo. It updates itself and edits the agent configs. Each map ticket must choose between the frozen per-agent plugins and the successor (claims 4, 28-33).
- Enrollment #126: the old plugin needs one `plugin` entry in the tracked `opencode.json`. Put it in one file only (claims 7, 36). The successor `install` writes to `~/.config/opencode/opencode.json` and `~/.claude/settings.json` itself, and both files are managed by chezmoi (claims 28, 32).
- Shared memory #127: opencode and Claude can share a bank only with the same effective bank ID, API host and tenant. Check dynamic mode, the prefix and `directoryBankMap` on both sides. The recall types differ (claims 22-25). The successor shares `coding-agent::{gitProject}` by design, but it does not move existing memory (claim 31).
- Credentials and guard #128: never put a literal token in a tuple in tracked config. Use `HINDSIGHT_API_TOKEN`, an untracked `~/.hindsight/opencode.json`, or possibly `{env:VAR}` (claims 12, 15-17). The successor reads `~/.hindsight/coding-agent.json`, and it takes credentials from the old Claude and codex files (claims 29-30).
- Upgrade policy #129: pin `@vectorize-io/opencode-hindsight@0.2.8` exactly. A bare name is `@latest` from the cache (claim 37). Dependencies float on `^` (claim 38). The successor auto-updates unless `autoUpdate: false` is set. Codex says this applies only to an `npx` install (UNVERIFIED, claim 33).
- Migration #130: you cannot import opencode history. The successor adopts only the endpoint from the old files (claims 30, 31).
