# How do you cut Hindsight noise in Claude Code sessions: the first-prompt recall, the per-prompt knowledge refresh, and knowledge pages from other repos?

Ticket: none yet.

Versions and sources: The pin is `@vectorize-io/hindsight-coding-agents` 0.8.0 (`home/.chezmoidata/hindsight.yaml:2-3`). I downloaded the registry tarball on 2026-10-31. Its sha256 is `afc489206154f2e7254057e52b455be8751e8b8bbf5e4a720a104c136fbeed7c`, the same as the pin. `P/` means the `package/` directory of that tarball. I did not read the staged copy under `~/.hindsight/coding-agents`, because the guard denies that path. The server source is `hindsight-api-slim/hindsight_api/api/http.py` at tag `v0.10.1` (commit `fac0975`), read through `gh api`. `S/` means that file. The version of the server that talos-home runs is not verified. The repo config is `home/private_dot_hindsight/modify_private_coding-agent.json`, called `T` below. One agent did this work. No second model checked it. No session, hook or API request was run. Every claim about behaviour comes from reading the README and the bundled `dist/*.js` code.

## Answer

The three symptoms have three separate causes.

1. **The ~13 KB `<hindsight_memory>` block on the first prompt** comes from `autoInject: "recall"`. The hook runs one recall per session and injects the result once, with a fixed ~1.7 KB preamble. The recall body defaults to `{"types": ["observation"], "budget": "low", "max_tokens": 2000}`. You can turn it off (`autoInject: "none"`) or make it smaller (`recallOptions.max_tokens`).
2. **The ~2.5 KB `<hindsight_knowledge_refresh>` block on every prompt** comes from `pageRefreshEveryTurns`. The README says the default is 10. The 0.8.0 code uses 1, so the block is added on every turn. A value of `0` does not turn it off, because the code reads `0` as 1. A large value (for example 50) makes it rare. A negative value turns it off in the code, but the README does not document this.
3. **Knowledge pages from other repos** appear because all repos share the static bank `damien-main-memory`. Page search and page list take only a query and a limit, on the client and on the server. No tag filter exists for pages. To scope pages to one repo, you must use one bank for each repo.

You can filter recall by tag, but only in a narrow way. `recallOptions` passes the `tags` and `tags_match` fields to the server. But the plugin does not expand `{gitProject}` in `recallOptions`, so each repo needs its own `paths.<dir>` entry with a literal tag. Also, with the default `observationScopes: "shared"`, observations have no tags. So a strict tag filter returns no observations, and a filter with `tags_match: "any"` does not filter anything.

## Claims

### Q1: values of `autoInject`, and how to turn injection off or make it smaller

1. **CONFIRMED.** `autoInject` takes four values: `"reflect"` (the default), `"pages"`, `"recall"` and `"none"`. `"none"` injects nothing, and the agent searches the pages itself. Sources: `P/README.md:606`. `P/dist/claude-hook.js:1540-1547` (`resolveAutoInject` accepts only `AUTO_INJECT_MODES` and falls back to `"reflect"`). The deprecated `autoReflect: false` also gives `"none"` (`P/README.md:607`).
2. **CONFIRMED.** `T` sets `autoInject` to `"recall"` (`T:43`). The comment above it cites #127: the `"reflect"` mode timed out at 20 s against this server (`T:40-42`).
3. **CONFIRMED.** The injection runs on the first prompt of a session only. In `buildHookOutput`, recall runs only when `reflectAnswer` is still undefined in the session cache. The block is added only when `reflectRanThisTurn` is true. A failed retrieval is tried again on the next prompt, up to two attempts (`HOOK_INJECT_ATTEMPTS = 2`). Source: `P/dist/claude-hook.js:2057-2061`, `:2091-2128`, `:2196`.
4. **CONFIRMED.** The recall result is wrapped in `<hindsight_memory>` with a fixed preamble of about 1.7 KB. The preamble covers relevance, crediting and corrections. Source: `P/dist/claude-hook.js:1853-1864`.
5. **CONFIRMED.** In this release, the first injection is skipped for one prompt when the bank is cold, or when the page list is known and empty. The SessionStart hook writes `deferInitialReflect` to the session cache. The prompt hook then rewrites the cache without that flag, so the injection runs on the second prompt. Sources: `P/dist/claude-sessionstart-hook.js:3069`, `:3129-3131`; `P/dist/claude-hook.js:2100-2102`, `:1936-1941`, `:2186-2191`.
6. **UNVERIFIED.** That the observed 13 KB is the 2000-token recall plus the 1.7 KB preamble. I did not read `last_recall`, the diag log or the server tokenizer.

### Q2: recall budget and size controls

7. **CONFIRMED.** `recallOptions` is merged one key at a time over the default recall body `{"types": ["observation"], "budget": "low", "max_tokens": 2000, "include": {"entities": null}}`. It cannot replace `query`. Sources: `P/README.md:609`; `P/dist/claude-hook.js:735-740` (defaults), `:786` (merge), `:1119-1132` (`{ ...this.recallOptions, query }`).
8. **CONFIRMED.** The server recall request accepts `types`, `prefer_observations`, `budget` (default `mid`), `max_tokens` (default 4096), `include`, `tags`, `tags_match`, `tag_groups`, `min_scores` and `temporal_window`. `min_scores.reranker` and `min_scores.final` are post-ranking floors. The server text warns that reranker scores are "not calibrated across queries". Source: `S/:415-490`.
9. **CONFIRMED.** The recall request has no field for a result count. The size controls are `max_tokens`, `budget` and the `min_scores` floors. Source: `S/:435-490`. The README table has no recall count key either (`P/README.md:581-628`).
10. **CONFIRMED.** `injectTimeoutMs` (default 7000) limits the time of the `"recall"` and `"pages"` injection. It does not limit size. Source: `P/README.md:604`.
11. **CONFIRMED.** `pageSearchLimit` sets how many pages one search returns. It applies to the injection, the reflect fallback and the `hindsight_search_knowledge_pages` tool. The README says the default is 3. The code default is 10 (`DEFAULT_PAGE_SEARCH_LIMIT = 10`). Sources: `P/README.md:608`; `P/dist/claude-hook.js:734`, `:1587`; `P/dist/mcp-server.js:31959`.

### Q3: filter recall by tag

12. **CONFIRMED.** The retain side already writes the tag. `T` sets `retainTags` to `["project:{gitProject}"]` (`T:34`). The plugin expands `{gitProject}` in `retainTags`, and the README says "Recalls can then filter by `project:<repo>`". Source: `P/README.md:952-970`.
13. **CONFIRMED.** The plugin has no dedicated recall-tag key. The legacy keys (`recallTags`, `recallTagsMatch`) are not in the 0.8.0 README or in `resolveConfig`. The only route is to put the server fields `tags` and `tags_match` in `recallOptions`. Sources: `P/dist/claude-hook.js:1548-1626` (`resolveConfig`); `P/README.md:609` ("anything recall accepts is settable").
14. **CONFIRMED.** The plugin does not expand `{gitProject}` in `recallOptions`. The object is copied as-is (`P/dist/claude-hook.js:1591`) and is spread into the request body (`:1126`). Template expansion exists only for bank IDs and retain stamps (`:308-321`). So `"tags": ["project:{gitProject}"]` in `recallOptions` sends the literal string.
15. **CONFIRMED.** You can set the filter for one repo with a `paths.<prefix>` section. A path section can override any field except the bank-resolution and approval fields. It replaces `recallOptions` as a whole, and the client then merges the defaults under it again. `~` in the key is expanded, and the longest prefix wins. Sources: `P/README.md:905-929`; `P/dist/claude-hook.js:1753-1764` (`BANK_OVERRIDE_EXCLUDED`), `:1765-1772` (`applyBankConfig`), `:260-277` (`configuredDir`, `mapLookup`), `:786`.
16. **CONFIRMED.** The server tag-match modes are `any` (OR, includes untagged), `all` (AND, includes untagged), `any_strict`, `all_strict` (both exclude untagged) and `exact`. The default is `any`. Source: `S/:464-475`.
17. **CONFIRMED.** With `observationScopes: "shared"`, observations are untagged. The plugin default is `"shared"` (`P/dist/claude-hook.js:683`), and `T` does not change it. The server text says `'shared'` "runs a single pass over one global, untagged scope ... while keeping those tags on the source facts" (`S/:1243-1253`). The recall `tags` text names "untagged/global observations ... (the scope written by observation_scopes='shared')" (`S/:464-468`). This has two results:
    - The default recall (`types: ["observation"]`) with `tags_match: "any"` still returns every untagged observation, so the filter has no effect.
    - With `any_strict`, the observations are excluded. Only raw facts (`world`, `experience`) that carry the tag can come back.
18. **UNVERIFIED.** Every raw fact in `damien-main-memory` carries a `project:` tag. Facts retained before `retainTags` was set, or written by Hermes or the legacy plugin, may have no tag. A strict filter would hide them.
19. **CONFIRMED.** `tags` and `tag_groups` together fail on the server. Do not set both in `recallOptions`. Source: `docs/research/hindsight-claude-code-plugin.md`, claim 28 (server v0.10.1 lines 470-474).

### Q4: the per-prompt knowledge refresh

20. **CONFIRMED.** The refresh block is `<hindsight_knowledge_refresh>`. It holds the page-count line (when the bank has pages) and the whole `TOOL_GUIDE`, plus the "pages first" line when `autoInject` is not `"reflect"`, plus `toolGuideExtra`. Source: `P/dist/claude-hook.js:1884-1906`.
21. **CONFIRMED.** The trigger is the turn count, not a change. The hook adds the block when `cadence > 0 && turns % cadence === 0`, where `turns` starts at 1 (`P/dist/claude-hook.js:2093`, `:2197-2203`). The page list is fetched again on the same cadence (`:2170-2185`).
22. **CONFIRMED.** The code default for `pageRefreshEveryTurns` is 1. The README says 10. The code comment explains why: "moving this from 10 to 1 took searches from 15% of turns to 32.5% ... The cost is the guide's ~2KB re-sent per turn, which caches." Sources: `P/dist/claude-hook.js:1593-1597`; `P/README.md:611`. The observed refresh on every prompt matches the code, not the README.
23. **CONFIRMED.** `pageRefreshEveryTurns: 0` does not turn the refresh off. `raw.pageRefreshEveryTurns || 1` turns `0` into 1 (`P/dist/claude-hook.js:1597`). A value of N gives the block on turns N, 2N, and so on. With N > 1 there is no refresh on turn 1.
24. **CONFIRMED in code, not documented.** A negative value (for example `-1`) passes the `|| 1` check. `cadence > 0` is then false, so no refresh block is ever added, and the page list is fetched only once (`P/dist/claude-hook.js:2171`, `:2197`). The README does not document this, so a later release can change it.
25. **CONFIRMED.** The SessionStart hook always adds a `<hindsight_knowledge>` block with the same tool guide, when the session is not inert. It says "This tool guide and the page list are re-injected for you periodically". With the default cadence of 1, turn 1 gets the guide twice: once from SessionStart and once from the refresh. Sources: `P/dist/claude-sessionstart-hook.js:1879-1888`, `:3065-3068`. No key removes the SessionStart block except `disabled`, which removes all memory.
26. **CONFIRMED.** The setting has an env fallback, `HINDSIGHT_PAGE_REFRESH_EVERY_TURNS`. The file wins where it sets a value (`P/dist/claude-hook.js:1679`; `P/README.md:506-508`). Hook harnesses read the file at each hook call, so a change applies on the next prompt (`P/README.md:519-529`).

### Q5: scope knowledge pages per repo

27. **CONFIRMED.** Page search and page list work on the whole bank. The client sends only `q` and `limit` to `/knowledge-base/search`, and it lists the whole tree for `listPages` (`P/dist/claude-hook.js:1172-1190`, `:1209-1229`). The MCP tool takes only `query` (`P/dist/mcp-server.js:33301-33323`). The server endpoint takes only `q` and `limit` (`S/:7075-7097`). No route filters pages by tag.
28. **CONFIRMED.** `customPages.<name>.tags` selects which facts feed a page. It does not filter search (`P/README.md:615`). `hindsight_reflect` also takes only `query` (`P/dist/mcp-server.js:33339-33349`).
29. **CONFIRMED.** `T` turns off all five seeded pages (`T:33`). A skipped page "is **not deleted**" (`P/README.md:614`). So the pages from other repos that the search returns already exist in the shared bank.
30. **UNVERIFIED.** Which writer created those pages (an earlier config, another machine, Hermes, or the legacy plugin).
31. **CONFIRMED.** One bank for each repo is the upstream default. Without `bankId`, the bank is `coding-agent::{gitProject}`, and linked worktrees share the bank of the main checkout. Sources: `P/README.md:587-589`, `:931-950`; `P/dist/claude-hook.js:308-321`. `T` sets the static `bankId` (`T:31`). The handoff records the decision: one static bank for all agents and machines, shared with Hermes (#127; `docs/handoff/2026-10-04-hindsight.md`, "Where things stand").
32. **CONFIRMED.** Several repos can still share a bank by choice, through `banks.<id>.bank` or `mapPathToBank` (`P/README.md:856-903`).
33. **CONFIRMED.** 0.8.0 has no "recall additional banks" key. `rg -i additionalBank` finds nothing in `P/README.md` or `P/dist/claude-hook.js`. With one bank for each repo, recall can no longer reach memory from another repo.
34. **CONFIRMED, with a gap.** What one bank for each repo costs:
    - Old memories stay in `damien-main-memory`. Nothing moves them.
    - With `manageBankConfig: false` (`T:32`), the plugin writes no missions or strategies to the new banks (`P/README.md:597`).
    - With all pages off, a new bank has no pages. The page tools then return nothing.
    - Each page costs one LLM synthesis per refresh (`P/README.md:707`).
    - **UNVERIFIED:** the server-side cost of consolidation for each bank.

## Proposals (not applied)

Each diff is against `T`. Every proposal changes a value that `tests/test-hindsight-config.sh` may assert (`:40`, `:50`, `:77-78`, `:85` assert `bankId` and `autoInject`). Update that test in the same commit. A proposal that amends #127 (B, E) needs `git grep '#127'` and a review of every hit, per `AGENTS.md`.

### A. Make the refresh rare

```diff
 {{- $_ := set $live "autoInject" "recall" -}}
+{{- $_ := set $live "pageRefreshEveryTurns" 50 -}}
```

- Removes the ~2.5 KB block from almost every prompt (claims 21-23). The SessionStart guide stays, once (claim 25).
- Trade-off: upstream measured half as many memory searches with a cadence of 10 than with 1 (claim 22). Expect the agent to call the Hindsight tools less often.
- Variant `-1`: never refreshes. It depends on undocumented code behaviour (claim 24).

### B. Turn off the first-prompt injection

```diff
-{{- $_ := set $live "autoInject" "recall" -}}
+{{- $_ := set $live "autoInject" "none" -}}
```

- Removes the ~13 KB block (claims 1, 3). The recall request also goes away, so the prompt hook is faster.
- Trade-off: the session gets no memory unless the agent calls a tool. The page tools then return pages from all repos (claim 27). Amends #127.

### C. Make the recall smaller

```diff
 {{- $_ := set $live "autoInject" "recall" -}}
+{{- $_ := set $live "recallOptions" (dict "max_tokens" 500) -}}
```

- Keeps the injection and cuts its body to about a quarter (claim 7). The 1.7 KB preamble stays (claim 4).
- Trade-off: fewer memories, and the memories still come from all repos. The value 500 is a guess to tune. It was not measured. Optional: add `min_scores.final` to drop weak hits. The server warns that the scores are not calibrated (claim 8).

### D. Filter recall by tag, one entry per repo

```diff
 {{- $_ := set $live "autoInject" "recall" -}}
+{{- $_ := set $live "paths" (dict
+      "~/projects/myprysm/website" (dict "recallOptions" (dict
+        "types" (list "world" "experience")
+        "tags" (list "project:website")
+        "tags_match" "any_strict"
+        "max_tokens" 1000))) -}}
```

- Recall in that repo returns only facts tagged with its project (claims 15-17).
- Trade-offs:
  - Each repo needs a hand-written entry, because `{gitProject}` is not expanded (claim 14).
  - Observations are excluded, because they are untagged under `"shared"` (claim 17). So the injection holds raw facts, not the consolidated layer.
  - Facts with no tag are hidden (claim 18).
  - The tag value must be the main worktree basename. That `website` is the basename is not verified.
  - `set` replaces any `paths` key the live file has.
- This proposal does not fix the knowledge pages (claim 27).

### E. One bank for each repo

```diff
-{{- $_ := set $live "bankId" "damien-main-memory" -}}
+{{- $_ := unset $live "bankId" -}}
```

- Each repo gets `coding-agent::<repo>` (claim 31). This scopes recall, observations and pages in one change. It is the only route that scopes the knowledge pages (claims 27-28).
- Trade-offs:
  - It reverses #127, which Hermes shares.
  - It cuts every repo off from existing memory and from memory of other repos (claims 33-34).
  - New banks start empty, and they have no pages while `T:33` turns pages off. So the page tools give nothing until pages are turned back on, and each page then costs LLM synthesis.
  - The server cost of each bank is not verified (claim 34).
- `banks.<id>.bank` can merge chosen repos back together (claim 32).

### Effect of each proposal on each symptom

| Symptom | A | B | C | D | E |
|---|---|---|---|---|---|
| 13 KB first-prompt block | no | removed | smaller | smaller, repo only | repo only |
| Refresh on each prompt | rare or off | no | no | no | no |
| Pages from other repos | no | no | no | no | yes |

A with B, or A with C, is the smallest change that removes most of the noise without a bank decision.

## Open points

- Which server version talos-home runs. The server claims are from tag v0.10.1.
- Which writer created the pages from other repos in `damien-main-memory`.
- What share of facts in the bank carry a `project:` tag.
- The real token size of the observed recall. No diag log was read.
- The behaviour of `pageRefreshEveryTurns: -1` is in the code only and may change in a later release.
