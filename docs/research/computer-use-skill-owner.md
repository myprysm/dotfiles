# What installs the untracked computer-use skill?

Ticket: myprysm/dotfiles#115

Versions: Orca 1.4.220 on WSL (Windows app `C:\Users\OPERATOR\AppData\Local\Programs\orca`, `app.asar` `/package.json` `"version": "1.4.220"`) and on the Mac (`/Applications/Orca.app`, CLI `/usr/local/bin/orca`). Skills CLI (`skills` npm package) 1.7.0 in three WSL npx caches. The cache does not prove the version that ran on 2026-09-27. Skills lock schema version 3. Research date 2026-10-04.

Inputs: question, claude-r1, codex-r1, claude-chal, codex-chal, and one operator statement. Side A is a Claude sonnet sub-agent. It read WSL directly and read the Mac (account `OPERATOR`) through an Orca terminal. Side B is `codex exec` (gpt-6.1-sol, low, read-only) on WSL. Side B had no Mac access. In the challenge round, each side checked the claims of the other side. Side B ran read-only commands only. Side A also opened Mac terminals and sent an `rm` command for `/tmp/r115-out.txt`. No side ran an installer, `chezmoi apply`, or a dry run. The operator supplied this statement in this session. It is a source of its own: "They [Orca] suggest installing skills for some features in the settings. The skills you see have been installed by me running the command they suggested in their integrated terminal." An opus agent merged the reports. A codex run (gpt-6.1-sol, medium) audited the merge. The merge applied the audit fixes.

Side effect on the Mac: side A opened an Orca terminal "r115-ro". Its startup wrote the temporary file `/tmp/r115-out.txt` on the Mac. Side A then removed the file. In the challenge round, side A ran `ls -la /tmp/r115-out.txt` on the Mac. The result was "No such file or directory". Side A closed both terminals.

## Answer

The premise of the ticket is partly false. The live skills CLI lock on WSL, `~/.agents/.skill-lock.json`, lists `computer-use`. The source is `stablyai/orca`. The `skillFolderHash` is `b59f27370a41225c22127e91da0c91cd2519f217`. The tracked repo lock, `home/dot_agents/dot_skill-lock.json`, does not list `computer-use`. The gap is between the live lock and the tracked lock.

The skills CLI wrote the payload `~/.agents/skills/computer-use` and the symlink `~/.claude/skills/computer-use`. The operator started it. Orca Settings suggests an install command for some features. The operator ran that command in the Orca integrated terminal, on WSL. The inspected Orca CLI install handler delegates to `npx skills add`. That handler does not copy or link the payload itself. The research found no path where Orca installs or rewrites a skill automatically. That search was not an exhaustive call graph.

`computer-use` is absent on the Mac (side A only).

Both sides identify the skills CLI as the installer of `find-skills`, `orca-cli` and `orchestration` on WSL. Side A reports the same installer for these skills and `caveman` on the Mac.

`/adopt` applies to any write under `home/` that comes from a live machine. The payload is `deny`. The symlink is `report`. Only the tracked lockfile row can be adopted. It must pass the normal adoption checks. A row would make script 50 restore `computer-use`.

## Claims

1. **CONFIRMED.** The live WSL lock lists `computer-use`. The tracked lock does not. Sources:
   - Both sides, `cat ~/.agents/.skill-lock.json`, lines 31-38: `"source": "stablyai/orca"`, `"sourceType": "github"`, `"skillPath": "skills/computer-use/SKILL.md"`, `"skillFolderHash": "b59f27370a41225c22127e91da0c91cd2519f217"`, `"installedAt"` = `"updatedAt"` = `"2026-09-27T22:15:30.961Z"`.
   - The live lock has four entries: `find-skills` (`vercel-labs/skills`), `orca-cli`, `orchestration`, `computer-use` (all three `stablyai/orca`). Lock mtime: `2026-09-29 20:11:18 +0200`.
   - The tracked lock `home/dot_agents/dot_skill-lock.json` lists `find-skills`, `orca-cli`, `orchestration` only. Commit `8b90039` "feat(claude): restore the Orca skills from the lockfile" added it. `git show 8b90039:home/dot_agents/dot_skill-lock.json | grep -c computer-use` gives `0`.
   - Side B: the active chezmoi source `/home/OPERATOR/.local/share/chezmoi/home/dot_agents/dot_skill-lock.json` has the same three entries.
2. **CONFIRMED.** The live lock is the only skills lock in the inspected locations. Sources:
   - Both sides: the skills CLI 1.7.0 `dist/cli.mjs` lines 3740-3752 (`getSkillLockPath()`) use `$XDG_STATE_HOME/skills/.skill-lock.json` when the variable is set, else `~/.agents/.skill-lock.json`. `XDG_STATE_HOME` is not set. `~/.local/state/skills` does not exist.
   - Side B: line 1093 names the project lock `skills-lock.json`. No `~/.agents/skills-lock*` exists.
   - Limit: the search covered `~/.agents`, `~/.agents/skills`, `~/.claude/skills` and `home/`. It was not a search of the whole machine.
3. **CONFIRMED.** Inventory of `~/.agents/skills` on WSL. All entries are real directories. No `SKILL.md` has a version field. Sources: both sides (`ls -la`, `lstat`, frontmatter read). Times are `+0200`, mtime = ctime.
   - `computer-use`: 2026-09-28 00:15:30, `name: computer-use`. It holds only `SKILL.md` (2211 bytes, mtime and ctime 2026-09-28 00:15:30.736265150).
   - `find-skills`: 2026-04-06 14:33:41, `name: find-skills`.
   - `orca-cli`: 2026-09-29 20:11:17, `name: orca-cli`.
   - `orchestration`: 2026-09-28 00:14:55, `name: orchestration`.
4. **CONFIRMED.** Inventory of `~/.claude/skills` on WSL. Sources: both sides.
   - `computer-use`, `find-skills`, `orca-cli`, `orchestration` are symlinks to `../../.agents/skills/<name>`.
   - The `computer-use` symlink has mtime 2026-09-28 00:15:30.736265. That is the same time as its target.
   - `orca-cli` link: 2026-09-28 00:13:26. `orchestration` link: 2026-09-28 00:14:55. `find-skills` link: 2026-04-06 14:33:41.
   - `claude-permissions-review`: real directory, 2026-10-03 12:04:17.
   - `playwright-cli`: real directory, mtime 2026-03-29 21:31:37, ctime 2026-08-03 01:12:53.
   - `synced`: real directory, 2026-09-28 00:27:25, no top-level `SKILL.md`.
   - The frontmatter names of the two real skill directories are `claude-permissions-review` and `playwright-cli`. Neither file has a version field. The symlink frontmatter matches the target.
   - The `description` of each entry is in its `SKILL.md`. This document does not repeat it.
5. **CONFIRMED.** The installed `computer-use` payload is identical to the record in the Orca 1.4.220 bundle. Sources:
   - Both sides: `sha256sum ~/.agents/skills/computer-use/SKILL.md` gives `2839933fd35216845461466403e6061488005f6df57126d0cd0f769ea45753f3`.
   - Both sides: `resources/skills/current-manifest.json` (Windows Orca install), `computer-use` record: `"releaseRevision": 9`, `"gitTreeSha": "b59f27370a41225c22127e91da0c91cd2519f217"`. This equals the lock `skillFolderHash`.
   - Side B: the same record has `"exactSha256": "2839933f...53f3"`. Side A did not read this field.
   - Side B: the bundle also holds `release-mapping.json`, `snapshot-registry.json` and `app.asar.unpacked/out/cli/bundled-skill-guides.js`.
6. **CONFIRMED.** On WSL, `orca` is a shim to the Windows app. Sources:
   - Both sides: `~/.local/bin/orca` runs `exec /mnt/c/Users/OPERATOR/AppData/Roaming/orca/wsl-managed-cli/32035c1f029c2d819963/orca-ide "$@"`.
   - Side B: `~/.local/bin/orca-ide` sets `ORCA_WIN_LAUNCHER='C:\\Users\\OPERATOR\\AppData\\Local\\Programs\\orca\\resources\\bin\\orca.exe'`.
   - Side A: `orca --version` prints `1.4.220`. Side B: the `app.asar` `/package.json` says `"version": "1.4.220"`.
7. **CONFIRMED after resolution.** The `orca` commands work from the Claude sessions. They fail in the side B sandbox. Sources:
   - Side B: every `orca` and `orca-ide` call failed with `ERROR: UtilBindVsockAnyPort:309: socket failed 1`. This also happened in a plain `/bin/bash` retry. The error comes from WSL interop. It occurs before Orca starts.
   - Side A: `orca-ide agent-context`, `--version`, `environment list`, `skills install --help`, `skills update --help` and `skills list` worked from the Claude sessions.
   - Resolution: both observations hold. The vsock failure is specific to the side B sandbox. It does not refute the side A output.
   - Side B confirmed the side A help text in the static files (claim 8).
8. **CONFIRMED.** The Orca CLI installs its bundled skills through the community skills CLI. The inspected handler does not copy or link the payload itself. Sources:
   - Side A: `orca skills install --help` says "Install bundled Orca skills via the community skills CLI... Resolves to the same `npx skills add <repo> --skill <name> ...` command used by Orca Settings, plus ... `npx --yes` and `-y`". It is global by default. It "Targets the coding agents Orca detects on this host, plus the shared .agents/skills directory". `orca skills update --help` resolves to `npx skills update <names...>`.
   - Side B: the same text is in `resources/app.asar.unpacked/out/cli/specs/skills.js:75-81`. Lines 107-112 describe `npx skills update`.
   - Both sides: `out/shared/agent-feature-install-commands.js:9` sets `ORCA_SKILLS_REPOSITORY_URL = 'https://github.com/stablyai/orca'`. Lines 35-48 build `skills add <repository> --skill <name> --global --agent <target> -y`.
   - Both sides: `out/cli/handlers/skills.js:135-145` prepends `--yes`. Line 196 calls `runNpxSkills(npxArgs)`. Lines 212-213 register `skills install` and `skills update`. Lines 170-173 throw when `ORCA_CLI_CWD` is set.
   - Side B: `~/.npm/_npx/43103b98cff1ffa9/node_modules/skills/dist/cli.mjs:2326-2342` copies the payload into the canonical directory (lines 2326-2327) and calls `createSymlink(canonicalDir, agentDir)` (line 2342).
   - Limit (side B): the current handler does not prove how an older Orca version behaved.
9. **CONFIRMED after correction.** The operator statement identifies who started the install. Both sides infer that the skills CLI wrote the WSL payload and symlink. The operator started the install from the command that Orca Settings suggests, in the Orca terminal, on WSL. Sources:
   - Operator statement: Orca suggests installing skills for some features in Settings. The operator ran the suggested command in the Orca integrated terminal.
   - Side A (challenge): the Settings pane "Computer Use skill" (`Mm()`, near byte 31034918 of `app.asar`) shows an install command. It opens a "Computer Use setup" terminal, where the user runs the command. Side A did not confirm whether that terminal runs the command on its own. Side B did not check this pane.
   - Both sides: the lock records `2026-09-27T22:15:30.961Z`. The payload and the symlink have the filesystem time `2026-09-27T22:15:30.736265Z`. The times differ by about 225 ms (claims 1, 3, 4). The payload hash matches the bundle (claim 5). The install path is the skills CLI (claim 8).
   - Both sides: the lock install times are sequential: `orca-cli` 2026-09-27T22:13:26.854Z, `orchestration` 22:14:56.650Z, `computer-use` 22:15:30.961Z.
   - The WSL files contain `computer-use`. Side A reports that the Mac does not (claim 12).
   - Correction: side B claim 9 and side B challenge claim 6 left the initiator open. The files alone cannot tell a direct `npx skills add` from an Orca-generated command. The operator statement closes this point.
10. **UNVERIFIED.** The research found no Orca path that installs or rewrites a skill automatically (app start, update, onboarding, session). Source: side A only (challenge), `app.asar` read at byte offsets:
    - The main-process updater method `start(e)` at byte 12469550 (audit re-read; side A cited 12470909) spawns `npx --yes skills update <names> --global -y`. Side A found the IPC `skills:startUpdateRun` (near byte 12519517) that exposes it. Preload `window.api.skills.startUpdateRun` is near byte 23683996. Renderer wrappers are near bytes 53650767 and 105066448.
    - `skills:freshnessInventory` is read-only. The renderer uses a 15 s freshness interval (`i=15e3`, at byte 58746777, audit re-read). It refreshes the inventory on focus and on a skills event. A focus handler can schedule a delayed refresh. It does not install or update. The Settings UI holds "SkillFreshnessRow".
    - `skills:installShare` and `skills:installBundleShare` (near byte 12515736) handle shared skills, not bundled `computer-use`.
    - Limit: side A did not find which renderer code calls the update wrapper. The search is not an exhaustive call graph. Side B inspected only the explicit command handler and left this point open.
    - One data point: the Mac runs the same Orca 1.4.220 and has no `computer-use` (claim 12).
11. **CONFIRMED.** The same owner (the skills CLI) installed these entries on WSL: `computer-use`, `orca-cli`, `orchestration` (source `stablyai/orca`) and `find-skills` (source `vercel-labs/skills`). Sources: both sides, the live lock (claim 1).
12. **UNVERIFIED.** `computer-use` is absent on the Mac. It is not in `~/.agents/skills`, not in `~/.claude/skills`, and not in the Mac lock `~/.agents/.skill-lock.json` (mtime Oct 2 14:30). Source: side A only. Side B had no Mac access.
13. **UNVERIFIED.** The Mac lock lists four entries. Source: side A only.
    - `find-skills` (`vercel-labs/skills`, 2026-04-07).
    - `caveman` (`JuliusBrussee/caveman`, 2026-09-09).
    - `orchestration` (`stablyai/orca`, 2026-09-29T14:54Z).
    - `orca-cli` (`stablyai/orca`, 2026-10-02T12:30Z).
    - The hashes of `find-skills`, `orca-cli` and `orchestration` match WSL.
14. **UNVERIFIED.** Mac topology. Source: side A only.
    - `~/.agents/skills`: `caveman`, `find-skills`, `orca-cli`, `orchestration`, all real directories.
    - `~/.claude/skills`: symlinks `find-skills`, `orca-cli`, `orchestration`. Real directories `claude-permissions-review`, `playwright-cli`, `synced`.
    - `~/.claude/skills` has no `caveman` symlink. The `caveman` payload in `~/.agents/skills` has no link from `~/.claude/skills`.
    - `chezmoi managed` on the Mac gives the same skill entries as on WSL.
15. **CONFIRMED.** Other entries in `~/.claude/skills`, listed only. Owners were not traced further.
    - `claude-permissions-review` and `playwright-cli` are chezmoi-managed (claim 16). Their original authors were not investigated.
    - `synced`: owner not investigated. Side B saw `docx`, `pdf`, `pptx`, `xlsx`, `google-workspace` and other payloads in it, and reported a `manifest.json` time of Oct 4 13:25 in a bucket below `synced`. Side A said that it holds anthropic-skills payloads and that something rewrites it live. The upstream owner, a repeated rewrite, and the rewrite mechanism stay unverified.
16. **CONFIRMED.** chezmoi manages no entry under `~/.agents/skills` and none of the four skills-CLI symlinks. Sources: both sides, `chezmoi managed | grep -i -E 'skill|\.agents'`:
    - `.agents` (directory only), `.chezmoiscripts/50-claude-skills.sh`, `.chezmoiscripts/51-purge-superseded-npx-skills.sh`, `.claude/skills`, `.claude/skills/claude-permissions-review/**`, `.claude/skills/playwright-cli/**`.
    - `home/.chezmoiignore:40` holds `.agents/.skill-lock.json`. chezmoi does not write the live lock.
17. **CONFIRMED.** Script 50 (`home/.chezmoiscripts/run_onchange_after_50-claude-skills.sh.tmpl`) restores the skills that the tracked lock lists. It skips names that already have a symlink in `~/.claude/skills`. Sources: both sides, full read.
    - Lines 63-67: at template time it reads `dot_agents/dot_skill-lock.json` (the tracked lock) and groups names by source.
    - Line 49: `[ -L "$HOME/.claude/skills/$skill" ] && continue`.
    - Line 55: `npx --yes skills add "$repo" -g -y -a universal claude-code -s $wanted`.
    - Lines 58-59: it records names that still have no symlink.
    - The tracked lock has no `computer-use` row. So script 50 does not install `computer-use` on a fresh machine.
18. **CONFIRMED after correction.** Script 51 (`home/.chezmoiscripts/run_once_after_51-purge-superseded-npx-skills.sh`) reads the live lock. For the sources `mattpocock/skills` and `JuliusBrussee/caveman`, it deletes the payload and unlinks matching symlinks. Sources: both sides, full read in the challenge round.
    - Lines 18-30: it reads the live lock. Line 19: `SUPERSEDED='mattpocock/skills JuliusBrussee/caveman'`. It selects lock names with these sources.
    - Lines 38-46: it removes symlinks in `~/.[!.]*/skills` and `~/.config/*/skills` whose target matches `*agents/skills/<name>`.
    - Lines 54-57: `payload="$HOME/.agents/skills/$skill"`, then `rm -rf "$payload"` when `[ -d "$payload" ]`.
    - Lines 63-74: it removes the selected rows from the live lock.
    - Lines 80-86: it removes the standalone caveman hook files in `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks` (line 83).
    - Lines 92-96: when `claude` exists, it runs two commands: `claude plugin install mattpocock-skills@claude-plugins-official` and `claude plugin install caveman@caveman`.
    - On WSL, the live lock selects no name today. `computer-use` (`stablyai/orca`) is not selected.
    - On the Mac, the live lock holds `caveman` (`JuliusBrussee/caveman`). Script 51 selects it there (side A only).
    - Correction: claude-r1 read only the head of script 51 and said that it removes symlinks. It also deletes payload directories and prunes lock rows.
19. **CONFIRMED.** No chezmoi rule deletes an unknown entry in `~/.agents/skills` or `~/.claude/skills`. Sources: both sides.
    - The source directories are `home/dot_agents` and `home/dot_claude/skills`. Neither is `exact_`.
    - `home/.chezmoiignore` and `home/.chezmoiexternal.toml.tmpl` hold no rule for the skill trees.
    - Script 51 selects skill names by source in the live lock. Its separate hook cleanup selects files by name.
    - Both sides infer that the current rules leave `computer-use` in place. No side ran an apply to test this.
20. **CONFIRMED after resolution.** `/adopt` applies to the computer-use case. It denies the payload, gives `report` for the symlink, and allows only the lockfile row. Sources:
    - Both sides: `.claude/skills/adopt/SKILL.md:3`: "Also use before any `chezmoi add` or any write under home/ sourced from a live machine."
    - Both sides: `SKILL.md:28`: "**Deny-list check** — if the source path matches [deny-list.md](deny-list.md), hard-refuse to stage it."
    - Both sides: `deny-list.md:29`: "`~/.agents/**` except `~/.agents/.skill-lock.json` | skills-CLI-managed tree; only the lockfile migrates". So the payload `~/.agents/skills/computer-use` is `deny`.
    - Both sides: `deny-list.md:28` covers per-machine agent state under `~/.claude`: "only `CLAUDE.md`, `settings.json`, `statusline.sh`, hand-written skills migrate". The symlink `~/.claude/skills/computer-use` matches no deny row. It is not a hand-written skill.
    - Both sides: `mapping.md:4`: "a finding with no row here is `report`, not improvisation." `mapping.md` has no row for skills. So the symlink is `report`.
    - Side A (challenge): a `computer-use` row in `home/dot_agents/dot_skill-lock.json` is a lockfile change. It goes through the normal gauntlet: plan, approval per group, strip and review, gitleaks. With that row, script 50 restores `computer-use` (claim 17).
    - Resolution: claude-r1 claim 8 said that `/adopt` does not apply to a tool-installed entry. Side B said that `/adopt` applies and denies the payload. `/adopt` applies to any proposed write under `home/` that comes from a live machine. Tool ownership gives no exemption. The rules then classify each part: the payload is `deny`, the symlink is `report`, the lockfile row is adoptable.
21. **UNVERIFIED.** On WSL, `orca skills list` gives: `computer-use`, `linear-tickets`, `orca-cli`, `orca-emulator`, `orca-emulator-android`, `orca-linear`, `orca-per-workspace-env`, `orchestration`. `orca skills installed` fails on WSL with "must run on the machine whose installed skills you want to use...". Source: side A only (live output). Side B could not run the commands (claim 7). Side B found the eight names in `current-manifest.json` and the error text in `out/cli/handlers/skill-sharing.js:18`.

## Facts that bear on the delivery

The planned delivery uses chezmoi `symlink_` entries with bare names for the Matt Pocock skills, in `~/.agents/skills/<name>` and `~/.claude/skills/<name>`. These facts apply. They are facts only. This document makes no recommendation.

- Script 50 skips a name that already has a symlink in `~/.claude/skills` (claim 17).
- Script 51 reads the live lock. For names with the source `mattpocock/skills` or `JuliusBrussee/caveman`, it runs `rm -rf ~/.agents/skills/<name>` and unlinks symlinks whose target matches `*agents/skills/<name>` (claim 18). Script 51 is `run_once`.
- No `exact_` directory and no ignore or script rule deletes an unknown entry in either directory (claim 19). The reviewed rules leave `computer-use`, `find-skills`, `orca-cli` and `orchestration` in place. Script 51 selects the Mac `caveman` for deletion if it runs there. The Mac selection rests on side A only.
- The tracked lock decides what script 50 restores. The live lock decides what script 51 purges.

## Corrections to earlier claims

- The ticket premise said that the skills CLI lock does not list `computer-use`. The live WSL lock lists it. Only the tracked lock omits it (claim 1).
- codex-r1 claim 6 said that all Orca read commands fail. They fail only in the side B sandbox, at WSL interop (claim 7).
- codex-r1 claim 9 left the initiator unknown. The operator statement identifies it (claim 9).
- claude-r1 claim 4 described script 51 from its head only. Script 51 also deletes payload directories and prunes lock rows (claim 18).
- claude-r1 claim 8 said that `/adopt` does not apply. It applies and classifies each part (claim 20).
- claude-r1 claim 3 said that `synced` holds anthropic-skills payloads that something rewrites live. Side B confirmed only a recent `manifest.json` time (claim 15).

## Open questions

- Is there an automatic Orca install or rewrite path? Side A found none. The search was not an exhaustive call graph. Side A did not find which renderer code calls the `skills update` wrapper (claim 10).
- Does the "Computer Use setup" terminal run the install command on its own, or does the user run it? The operator statement says that the operator ran it.
- Which skills CLI version ran on 2026-09-27? The caches hold 1.7.0 (claim 2).
- Locks outside the inspected locations were not searched.
- Who owns `synced`? Does a process rewrite it? If so, which process (claim 15)?
- Who originally wrote `claude-permissions-review` and `playwright-cli` (claim 15)?
- The Mac claims rest on side A only (claims 12-14).
