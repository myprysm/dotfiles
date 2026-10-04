# Can the plugin `mattpocock-skills@claude-plugins-official` stay at one version or sha? Does it update itself, which setting stops the update, and can chezmoi own that setting?

Ticket: myprysm/dotfiles#109

Versions tested: Claude Code 2.1.289 (binary `~/.local/share/claude/versions/2.1.289`). Installed plugin: `mattpocock-skills` 1.2.3 (cache `~/.claude/plugins/cache/claude-plugins-official/mattpocock-skills/1.2.3`). The docs are from code.claude.com, read 2026-10-04, and are not versioned. Neither side ran an install, update or session probe. Codex could not reach api.github.com in the challenge.

## Answer

The official marketplace has auto-update on by default. An update pass runs in an interactive session after the first message, with a random delay of up to 10 minutes. It writes to disk. The running session keeps its loaded version until `/reload-plugins` or the next launch.

The official entry for mattpocock-skills pins the full sha `c55ee46073ed923f86ce59a5eb3b6d895095d1b7` with a `url` source. So the plugin lags upstream `main` by design.

The manifest `version` (1.2.3) is a second gate. The cache changes only when this string changes. Upstream `main` still says 1.2.3. So a new copy needs two events: Anthropic bumps the entry sha, and the manifest version at the new sha differs.

There are two ways to stop updates:
- `autoUpdate:false` on a `claude-plugins-official` entry in `extraKnownMarketplaces`. This applies to the whole marketplace.
- `DISABLE_AUTOUPDATER=1`, `DISABLE_UPDATES=1` or `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`. These also stop Claude Code's own updates, unless `FORCE_AUTOUPDATE_PLUGINS=1` is set.

Chezmoi already owns `env` and `extraKnownMarketplaces`.

A user cannot set the per-plugin sha inside the official catalog entry. The documented routes to hold a version are:
- add a marketplace as `owner/repo#<ref>`, which selects one catalog commit (not tested for `claude-plugins-official`)
- a marketplace of the operator's own, with `sha` on the plugin entry
- a `--plugin-dir` checkout (the Loop's route, from ADR 0003)

Codex does not rule out other indirect pins.

## Claims

1. **CONFIRMED.** Auto-update default:
   - On for `claude-plugins-official` and the other official names, except `knowledge-work-plugins` and `first-party-plugins`.
   - On for `claudeai` and `pluginDirectory` sources.
   - Off for every other marketplace (hindsight and caveman here).

   Sources: plugins/install.md "Keep plugins updated" (both sides); binary `function Gve(e,n,s){if(s!==void 0)return s;if(n.autoUpdate!==void 0)return n.autoUpdate;if(n.source?.source==="claudeai")return!0;if(n.source?.source==="pluginDirectory")return!0;let r=e.toLowerCase();return jMe.has(r)&&!Cp.has(r)}` (codex; Claude-chal re-extracted it).
2. **CONFIRMED.** The pass runs in an interactive session after the first message. It waits a random delay of up to 10 minutes. It then refreshes the auto-update marketplaces and updates their plugins on disk. The running session keeps its old versions. The notice is `Plugin updated: <name> · Run /reload-plugins to apply`. Sources:
   - plugins/loading.md "When auto-update runs" (claude-r5, codex-r5 claim 3)
   - binary `var I=600000`, `Math.floor(Math.random()*I)`, and `Plugin autoupdate: updated ${o} from ${e.oldVersion} to ${e.newVersion}` (codex-chal)

   Codex-chal could not re-fetch the loading page.
3. **CONFIRMED.** Precedence for a marketplace's auto-update: first `autoUpdate` from settings `extraKnownMarketplaces`, then `autoUpdate` in `known_marketplaces.json`, then the default. Sources: loading.md (both sides); binary `Gve` above.
4. **UNVERIFIED.** The `/plugin` toggle writes `known_marketplaces.json`, and also the settings entry when one exists. Source: loading.md (Claude only).
5. **CONFIRMED.** `DISABLE_UPDATES`, `DISABLE_AUTOUPDATER` and `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` each turn off the pass, unless `FORCE_AUTOUPDATE_PLUGINS=1` is set. Sources:
   - loading.md and plugins/org.md (both sides)
   - binary `function cve(){if(a.DISABLE_UPDATES)...;if(Le(process.env.DISABLE_AUTOUPDATER))...;let e=lnt();...}`, `function lnt(){if(process.env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC)...}` and `function qZ(){return Lse()&&!a.FORCE_AUTOUPDATE_PLUGINS}` (codex; Claude-chal re-extracted `cve`)
6. **UNVERIFIED.** With these env vars, the "Enable auto-update" toggle is hidden. Source: loading.md (Claude only).
7. **UNVERIFIED.** The current env-vars page lists `DISABLE_AUTOUPDATER`, `DISABLE_UPDATES` and `FORCE_AUTOUPDATE_PLUGINS`. Source: codex-chal only. Claude's WebFetch did not return these rows.
8. **CONFIRMED.** `DISABLE_AUTOUPDATER` also stops Claude Code's own updates. A plugin with a `command` source is not covered. mattpocock-skills has a `url` source, so it is covered. Sources: org.md "Turn updates off for the whole fleet" (both sides); local `marketplace.json` entry (both sides; I re-read it).
9. **CONFIRMED.** `claude plugin install name@marketplace` refreshes the marketplace first, whatever the `autoUpdate` setting or `DISABLE_AUTOUPDATER` is. `/plugin` "Update now" and `claude plugin update` also work with auto-update off. Sources: loading.md "When Claude Code refreshes a marketplace before an install"; install.md "Update plugins now" (claude-r5; codex-r5 claim 7).
10. **CONFIRMED.** `claude plugin install` has no version or sha option. Its usage is `claude plugin install|i [options] <plugin>`. Sources: `claude plugin install --help` (codex); the docs list no such flag (Claude-chal).
11. **CONFIRMED.** The local official catalog entry is `"source":{"source":"url","url":"https://github.com/mattpocock/skills.git","sha":"c55ee46073ed923f86ce59a5eb3b6d895095d1b7"}`, with no `ref` and no entry `version`. The remote `anthropics/claude-plugins-official` `main` has the same sha. Sources: `~/.claude/plugins/marketplaces/claude-plugins-official/.claude-plugin/marketplace.json` (both sides; I re-read it); raw GitHub (both sides).
12. **CONFIRMED.** The manifest `version` at three commits: `c55ee46` = 1.2.3, `2ab9580` = 1.2.0, `d81f3a1` = 1.2.3. Sources: `gh api` (Claude); raw.githubusercontent at each sha (codex-chal).
13. **UNVERIFIED.** Upstream `main` HEAD is `d81f3a183412e71a5b1e84ca21bc1a35eea03a60`, with date 2026-09-29T12:37:40Z. Source: `gh api repos/mattpocock/skills/commits/main` (Claude only). Codex-chal's re-run failed with a network error.
14. **UNVERIFIED.** The title of commit `d81f3a1` names `release/v1.3`. Source: github.com commit page (codex-chal only).
15. **CONFIRMED.** Upstream `main` has `skills/engineering/{implement-spec,pr,retro}`. The cached plugin copy has none of the three. Sources: both sides.
16. **CONFIRMED-CORRECTED.** At the pinned commit `c55ee46`, the tree has `skills/in-progress/implement-spec/SKILL.md` and `skills/in-progress/retro/SKILL.md`; `pr` is absent (Claude-chal, `gh api` tree).
    - The plugin manifest lists its skills explicitly. The cached `plugin.json` `skills` array has no `in-progress` path (I re-read it: 0 hits for `in-progress`).
    - Correction: codex-r5 said "the catalog-pinned commit omits them". The commit has two of them, but the manifest does not load them.
    - Codex-chal says "pinned manifest omits them", which agrees with this.
17. **CONFIRMED.** The installed record holds `version 1.2.3`, `installedAt 2026-08-05T16:25:31Z`, `lastUpdated 2026-08-09T20:21:57Z` and `gitCommitSha 2ab958093e83e0ec752e6c1c5932da465bf23e0c`. The manifest at `2ab9580` says 1.2.0. The cache dir and the cached manifest say 1.2.3. The cause of this mismatch is not known. Sources: `~/.claude/plugins/installed_plugins.json` and the cached `plugin.json` (both sides; I re-read them).
18. **CONFIRMED.** The manifest `version` takes priority. A manifest that pins `version` keeps users on the cached copy until the string changes. Sources: loading.md "How Claude Code computes the version" (Claude); host-marketplace.md "Release a new version" (codex-chal).
19. **UNVERIFIED.** The full fallback order is: manifest `version`, then entry `version`, then the 12-character commit sha. Source: loading.md (Claude only). Supporting data: seven official plugins have `version` = `d182ca456ca0` (claim 22).
20. **CONFIRMED.** For this plugin, a new cached copy needs two things: Anthropic changes the entry sha, and the manifest version at that sha differs from `1.2.3`. Upstream `main`'s manifest is still `1.2.3`. Sources: claims 11, 12, 18 (both sides).
21. **CONFIRMED.** `known_marketplaces.json` has no `autoUpdate` key for any of the three marketplaces. So no stored preference applies. The effective policy still depends on settings `extraKnownMarketplaces` (claim 3) and on the env vars (claim 5). Neither side checked the inherited environment or all settings scopes. Each entry holds `source`, `installLocation` and `lastUpdated`. Sources: both sides. The timestamp for `claude-plugins-official` moved from 09:10:48Z (Claude) to 09:28:03Z (codex-chal) on 2026-10-04. The cause is not recorded.
22. **CONFIRMED-CORRECTED.** On 2026-10-02 at 21:52:32.94xZ, **eight** official plugins changed, not ten:
    - seven of them have version `d182ca456ca0`
    - `security-guidance` has version 2.0.9
    - all eight have `gitCommitSha d182ca456ca0...`

    The `marketplaces/` dir mtime is `2026-10-02 23:52:32 +0200`, the same second. Correction: claude-r5 said "ten plugins". Sources: codex-chal probe; I re-ran it and got 8 rows.
23. **UNVERIFIED.** Who triggered the 2026-10-02 change, auto-update or a manual action? Not known. Both sides agree the files record no trigger. claude-r5 claim 14 calls it inference. Correction: the claude-r5 Answer line "confirmed by timestamps" claims too much.
24. **CONFIRMED-CORRECTED.** superpowers and figma are `url` sources with a pinned `sha`, last updated 2026-09-23. Correction: `stripe` is a `git-subdir` source with `ref: main` and `sha: 97b2164...`. Its `lastUpdated` is `2026-09-23T18:52:06.168Z`, not 18:52:04Z. Sources: codex-chal; I re-read both files.
25. **CONFIRMED.** Plugin sources of type `github`, `url` and `git-subdir` take `ref` (branch or tag) and `sha` (full 40-char, lowercase). With both set, `sha` wins. `npm` takes `version`. `archive` takes `sha256`. Source: marketplace-reference.md "Plugin sources" (both sides).
26. **CONFIRMED.** Holding users on one version is the marketplace owner's job, through `ref`/`sha` on the plugin entry. A user can add a marketplace as `owner/repo#<ref>`. One marketplace serves one version of each plugin at a time. Source: host-marketplace.md "Hold users on one version" (both sides).
27. **CONFIRMED.** `extraKnownMarketplaces` is an object keyed by marketplace name. `ref` goes on the marketplace `source`, and `autoUpdate` is a field of the entry. Source: marketplace-reference.md "Source objects in settings" (both sides). Both sides reject a WebFetch summary that showed an array.
28. **CONFIRMED.** `enabledPlugins` takes `true`/`false` per `name@marketplace`. No version or sha in the value is documented. Sources: loading.md and org.md; template line 74 (both sides).
29. **CONFIRMED (doc).** The name `claude-plugins-official` is accepted only from `github.com/anthropics/`. A managed `autoUpdate` locks the user toggle. Sources: marketplace-reference.md "Reserved names"; org.md (both sides).
30. **UNVERIFIED.** For the official marketplace, the binary function `q_e` accepts user (operator) settings and ignores project and local entries. Source: codex-chal only. Whether a user-scope `autoUpdate:false` for the official marketplace works on 2.1.289 was not probed by either side.
31. **CONFIRMED.** In `home/dot_claude/modify_private_settings.json`, `$owned` includes `env`, `enabledPlugins`, `extraKnownMarketplaces` and `skillOverrides`. An owned key is replaced whole from the rendered template, after `settings.local.json` overrides are merged into the base. Sources: modifier lines 34-48 (both sides; codex added the local merge, and Claude-chal confirmed it).
32. **CONFIRMED.** The template `home/.chezmoitemplates/claude-settings.json` has, today:
    - `env` with `CLAUDE_CODE_ENABLE_TELEMETRY` and `CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY`
    - `extraKnownMarketplaces` with `hindsight` and `caveman` only
    - `enabledPlugins` with `"mattpocock-skills@claude-plugins-official": true` (line 95)

    No updater key and no `claude-plugins-official` entry exist. Sources: template lines 3-6, 95, 99-112 (both sides).
33. **UNVERIFIED.** A user-scope `env` value (`DISABLE_AUTOUPDATER`) is read before the updater pass on 2.1.289. The docs show settings `env` entering the process env, and the binary reads `process.env.DISABLE_AUTOUPDATER`. Neither side tested the start-up order.
34. **UNVERIFIED.** The local marketplace clone dir is not a git repo, so `git log` fails there. Source: Claude only.

## Corrections to earlier claims

- **ADR 0003 l.3, "v1.3 with pr, implement-spec and retro was merged on 2026-09-29 while the marketplace still pins v1.2.3".**
  - "v1.3" is not a manifest version. Upstream `main`'s `plugin.json` says 1.2.3, the same as the pinned commit (claim 12).
  - Codex-chal reports that "release/v1.3" appears in the title of commit `d81f3a1` (claim 14, UNVERIFIED).
  - The 2026-09-29 date matches the HEAD commit date (claim 13, UNVERIFIED).
  - The marketplace pins a sha, `c55ee46`, not a version (claim 11).
  - Two of the three skills already exist at the pin, under `in-progress/`, but the manifest does not load them (claim 16).
- **ADR 0003 l.3 and l.7, "it updates itself behind a run's back" and "auto-updates".**
  - Auto-update is on by default for the official marketplace (claim 1).
  - The pass writes to disk. A running session keeps its loaded version until `/reload-plugins` or the next launch (claim 2).
  - For this plugin, a new copy also needs a sha bump by Anthropic and a manifest version change (claim 20). Upstream `main` is still 1.2.3.
  - The installed copy last changed on 2026-08-09 (claim 17).
  - A change can reach the *next* session.
- **#98 ("nobody saw an auto-update in a log").** The 2026-10-02 cluster (8 plugins, one second) fits a marketplace refresh, but no log names the trigger (claims 22, 23). mattpocock-skills was not part of it.
- claude-r5 "ten plugins" is corrected to eight (claim 22). The stripe source type and timestamp are corrected (claim 24).
- claude-r5 Answer, "auto-update path is confirmed by timestamps": inference only (claim 23).
- codex-r5 claim 9, "catalog-pinned commit omits them": corrected (claim 16).
- codex-r5 omitted `DISABLE_UPDATES` and `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` (claim 5).
- claude-r5 relied on docs for the precedence. Codex added the binary evidence (`Gve`, `cve`, `qZ`, `lnt`).

## Open points

- Does a user-scope `extraKnownMarketplaces["claude-plugins-official"].autoUpdate:false` stop the pass on 2.1.289? No probe (claims 30, 33).
- Why is the record `gitCommitSha 2ab9580` (1.2.0) but the cache is 1.2.3? (claim 17)
- What triggered the 2026-10-02 refresh and the 2026-10-04 refreshes? A `claude --debug` log would show it; none was read.
- The #98 body could not be fetched by codex (network). Claude read its item 11.
- The Claude Code changelog was not read.

## Consequences for the map

- The marketplace plugin's content is set by Anthropic's sha `c55ee46` and the manifest version 1.2.3, not by this repo (claims 11, 20).
- This plugin loads the manifest's `skills` list. Skills under `in-progress/` at the pin are not loaded (claim 16). A checkout of the same sha that is loaded another way (for example opencode `skills.paths` scanning `**/SKILL.md`) can expose a different skill set.
- `claude plugin install` takes no sha. The official entry's sha is set by Anthropic. Documented routes to hold a version: a marketplace added as `owner/repo#<ref>` (one catalog commit; not tested for the official marketplace), an own marketplace entry with `sha`, or a `--plugin-dir` checkout. Other indirect pins are not ruled out (claims 10, 25, 26).
- Chezmoi already owns the two off switches: `env` (`DISABLE_AUTOUPDATER`, which also stops Claude Code self-update) and `extraKnownMarketplaces` (per-marketplace `autoUpdate:false`, for all official plugins). Both keys exist in the template today. Neither holds an updater setting: `env` has no `DISABLE_AUTOUPDATER`, and `extraKnownMarketplaces` has no `claude-plugins-official` entry (claims 5, 8, 31, 32).
- Update-off does not pin a fresh install: `claude plugin install` refreshes the catalog anyway (claim 9).
- Auto-update writes to disk only. A running Loop session keeps its version, and a new session picks up the new copy (claim 2).
- Name collisions: a `--plugin-dir` copy named `mattpocock-skills` replaces this plugin for the session (see findings-r1 claims 6, 7).

