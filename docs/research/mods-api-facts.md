# Mods API facts for the statusline and UI surfaces

Research for #86. Claude Code version checked: 2.1.288.

## Sources

- TYPES: the type declarations that the `plugin-authoring` skill wrote for this build. Path: `/tmp/claude-1000/bundled-skills/2.1.288/91b17b2120cac2f738ba3bb47a070f87/plugin-authoring/types/claude-code.d.ts`. The path is session-specific. Cite by line number.
- SKILL-REF: `reference.md` in the same folder as TYPES' parent (`.../plugin-authoring/reference.md`).
- DOCS: official pages under `https://code.claude.com/docs/en/plugins/mods/` (`overview`, `reference`, `interface`, `api`). The reference page says "as of v2.1.287".
- STATUSLINE-DOC: `https://code.claude.com/docs/en/statusline`.
- BLOG: `https://claude.dev/blog/getting-started-with-claude-code-mods/`. Secondary source. Used only to confirm.
- No live mod was run. No mods folder was enabled. `~/.claude` was not touched.

## Q1. What data does a mod status line get?

A mod has no "status line payload". It calls functions. A mod pushes text with `$.ui.status(text)`. It reads the data with other calls.

- VERIFIED: `$.ui.status(text)` takes a string or `undefined`. It sets one line per plugin. `undefined` clears it. Source: TYPES lines 2262-2273.
- VERIFIED: The line shows "under the prompt, beside the engine's own pinned notices". Source: TYPES line 2263.
- VERIFIED: The docs say the line starts with a warning sign and the mod name, as in `⚠ my-mod: checks: 3 passing`. Source: DOCS `api.md`, section "Show something without starting a turn".
- VERIFIED: `$.session.usage()` returns `{ startedAt, context, rateLimits, cost }`. The types call these "the status line's figures". Source: TYPES lines 2621-2642 and 11007-11042.
- VERIFIED: Context window. `context.tokens` (optional) equals the status line `total_input_tokens`. `context.window` equals `context_window_size`. `context.percent` (optional, 0 to 100) equals `used_percentage`. `tokens` and `percent` are absent until the first API response of the live window. Source: TYPES lines 10257-10280.
- VERIFIED: Rate limits. `rateLimits` is an array of `{ kind, percentUsed, resetsAt? }`. `kind` is `five_hour`, `seven_day` or `spend_limit`. The array is empty when no window has a reading, and off a subscription. Source: TYPES lines 10597-10612 and 11010-11013, 11032-11036.
- VERIFIED: `resetsAt` is an ISO 8601 string. The `statusLine` payload `resets_at` is Unix epoch seconds. A port must convert. Source: TYPES lines 10608-10611; STATUSLINE-DOC field table.
- VERIFIED: Cost is `cost.usd`. It is absent where the host keeps no ledger. The CLI always has one. Source: TYPES lines 10295-10300 and 11037-11041.
- VERIFIED: The model is `$.session.model()`. It resolves a string, "the main loop's model, as `/model` shows it". Source: TYPES lines 2580-2583.
- UNVERIFIED: Whether that string equals the `statusLine` `model.display_name` (for example "Opus"). The types say only "as /model shows it". A live call is needed.
- UNVERIFIED: Whether `$.ui.status` text can carry ANSI colour, or whether the engine strips it. The types and docs do not say. The only text rule found is that an unpaired surrogate becomes U+FFFD (TYPES lines 2268-2269).
- UNVERIFIED: Whether a mod can read every other `statusLine` field. `session.usage()` has no `cwd`, `workspace` or cache fields. Other calls may cover some (`$.session.cwd()`, `repo()`). Not checked one by one.
- NOT FOUND: any event that fires on a status line refresh. A mod must pull usage itself, for example from a timer. TYPES line 3254 shows `$.clock.every` driving `$.ui.status`. Which event to hook was not studied.

## Q2. Can a mod status line and the `statusLine` setting coexist? Which wins?

- UNVERIFIED: No source states the relation. The mods docs and the statusline docs do not mention each other. The BLOG does not discuss it.
- INFERENCE, not a fact: The two look like two different slots. The `statusLine` setting renders "in its own row above the built-in footer badges" (STATUSLINE-DOC, intro). `$.ui.status` is a pinned notice "under the prompt, beside the engine's own pinned notices" (TYPES line 2263). The wording differs. That is not proof.
- VERIFIED: The docs treat them as separate things. `"disableAllHooks": true` stops every installed mod, and also "your settings hooks and custom status line". Source: DOCS `overview.md` (line 103 of a saved copy).
- VERIFIED: The docs list "status lines" with settings hooks, skills and MCP servers as things that run outside Claude Code. A mod runs inside. Source: DOCS `overview.md` (line 17 of a saved copy).
- To settle it: load a throwaway mod that calls `$.ui.status("x")` while the `statusLine` setting is active, and look. This needs a live session. Not done.

## Q3. Which surfaces render in the Mac Desktop Code tab?

Desktop means the Code tab of the Claude Desktop app. The WSL exception in the docs does not apply on a Mac.

- VERIFIED: Hooks run in the Desktop Code tab. What the mod draws appears there, "except elements the elements table marks terminal-only". Source: DOCS `overview.md`, "Where mods run" table.
- VERIFIED: Band (`AbovePrompt`). Raised on terminal and desktop only. Source: TYPES lines 9568-9577; DOCS `reference.md` render sites table.
- VERIFIED: Pane (`Pane`). Raised on every surface in the types, and listed for Desktop in the docs. Source: TYPES lines 9622-9630; DOCS `reference.md` render sites table.
- VERIFIED: `Spinner`, transcript sites, `CommandOutput`, `AskUserQuestion`, `SessionMode`, `PromptHint` are raised in terminal and desktop. Source: DOCS `reference.md` render sites table. Some other status lines are terminal-only. Source: DOCS `interface.md` line 294 of a saved copy.
- VERIFIED: The Desktop element table has `Box, Text, Button, Input, Select, Svg, Link, Code, Markdown, Client`. It has no `Raster` and no `Image`. Source: TYPES lines 3616-3627 and 3590-3592.
- VERIFIED: Desktop is a remote surface. It "asks over the wire (ui_render)" and "draws the tree where it has a slot for it". A mod can read `e.surface` or `$.session.surfaces()`. Source: TYPES lines 9683-9694 and 2612.
- UNVERIFIED: Status line (`$.ui.status`) on desktop. The types and docs name no surface for it. It is not a render site (not in `RenderComponent`, TYPES line 8712).
- UNVERIFIED: Toast (`$.ui.toast`) on desktop. The types describe a box "over the transcript's top right corner" and a notification bar line "where the transcript is printed into scrollback" (TYPES lines 2247-2254). Both read as terminal wording. No desktop statement found.
- UNVERIFIED: Slash command (`$.command.register`) in the Desktop Code tab. The docs say hooks run there (DOCS `overview.md`, "Where mods run"). A command is a `command.run` hook. No page says the Desktop typeahead lists it. The documented fallback where nothing draws is a command's text reply.
- NOT STATED for desktop: pane placement. The terminal rule is that an unasked pane seats from 144 columns and an asked pane at any width (TYPES lines 2278-2283).

## Q4. What does `$.state` keep across a hot reload?

- VERIFIED: `$.state` "survives a hot reload of the plugin's code". Source: TYPES lines 3168-3170. DOCS `interface.md` ("Keep state") says the same. BLOG says the same.
- VERIFIED: It lasts for the session. It ends with the session, and on `/clear`, `/resume` and `/branch`. Source: DOCS `interface.md`, table in "Keep state".
- VERIFIED: It does not persist across sessions. The types say "Persist through `$.store`". Source: TYPES line 3174.
- VERIFIED: A reload does NOT keep module-level variables or timers. `register` runs again and `session.start` fires again. Pending waits and timers are cancelled. Source: TYPES lines 3214-3216; SKILL-REF line 69; DOCS `reference.md` (`session.start` row: "again after a reload", not after `/clear`, `/resume`, `/branch`); DOCS `interface.md` table.
- VERIFIED: `$.store` keeps values across sessions and hot reloads. JSON only. 4 MiB limit in all. Source: TYPES lines 3136-3167.
- VERIFIED: Rules for `$.state`. Only the owner plugin writes. A `ui.render` hook may not write. `plugin` and `key` must be literals. Values are JSON, never `undefined`. A contract file `types/index.d.ts`, named in `plugin.json` as `"types"`, declares each value. Source: TYPES lines 3172-3209; `plugin-authoring` skill text.
- UNVERIFIED: Whether `$.ui.status` text stays on screen across a reload. The types say the engine's pane record outlives the module (`$.ui.panes()`, TYPES lines 2311-2316). They say nothing about the status line.

## Summary

- Data for a mod status line: VERIFIED for context window, rate limits and cost via `$.session.usage()`, and for the model name via `$.session.model()`.
- Format gaps: the rate-limit reset is ISO, not epoch (VERIFIED). Model string versus `display_name`: UNVERIFIED.
- Coexistence and precedence with the `statusLine` setting: UNVERIFIED. Needs a live test.
- Desktop: band and pane VERIFIED. Status line, toast and slash command UNVERIFIED for the Desktop Code tab.
- `$.state`: VERIFIED to survive a hot reload and last for the session. VERIFIED not to survive `/clear`, `/resume`, `/branch` or session end.
