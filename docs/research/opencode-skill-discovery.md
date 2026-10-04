# How does opencode 1.18.34 find skills? Re-check of Loop research §5 and `skills.paths`

Ticket: myprysm/dotfiles#107

Versions tested: opencode 1.18.34 (`opencode --version` -> `1.18.34`, binary `/home/linuxbrew/.linuxbrew/Cellar/opencode/1.18.34/bin/opencode`). The source is tag `v1.18.34`. The sst/opencode and anomalyco/opencode copies of `skill/index.ts` are identical (Claude-chal ran `diff`). The local copies are in `src-r3/`. Claude ran probes with `opencode debug skill` and a scratch `HOME`/`XDG_*`. Codex read the source, the binary and the saved probe outputs.

## Answer

opencode loads `~/.claude/skills` and `~/.agents/skills`. It also loads:
- project `.claude` and `.agents` dirs, walking up to the worktree
- config dirs: `~/.config/opencode`, `.opencode`, `~/.opencode`, `OPENCODE_CONFIG_DIR`
- `skills.paths`
- `skills.urls`

The order of these discovery categories is fixed. No side shows that the order of files inside one glob result is stable. The files load with unbounded concurrency, and each duplicate overwrites the earlier entry. So the collision winner changes between runs. The Loop's "scan order varies" gives the wrong cause: the varying load completion order is enough to change the winner.

`OPENCODE_DISABLE_EXTERNAL_SKILLS=1` removes `.claude` and `.agents`, both global and project. `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1` or `OPENCODE_DISABLE_CLAUDE_CODE=1` removes only `.claude`. These skill-disable flags do not touch the config dirs or `skills.paths`. Project `.opencode` may depend on `OPENCODE_DISABLE_PROJECT_CONFIG` (UNVERIFIED).

The skill tool looks up the exact frontmatter `name` string, with no prefix stripping. "Bare names only" is too strong.

`skills.paths` is a list of dirs:
- `~/` expands
- a relative path resolves against the project dir
- a missing dir gives a WARN and is skipped
- each dir is scanned for `**/SKILL.md`

## Claims

1. **CONFIRMED.** The external dirs are `.claude` and `.agents`. The global root is `join(global.home, dir)`. The pattern is `skills/**/SKILL.md` with `dot:true` and `symlink:true`. Source: `skill/index.ts` 21-25, 148-156, 185-194 (Claude lines; codex-chal agrees on the same file).
2. **CONFIRMED.** The project external dirs come from `fsys.up({targets:[".claude",".agents"], start: directory, stop: worktree})`. Source: `index.ts:196-202`; `core/src/fs-util.ts` (both sides).
3. **CONFIRMED.** These config dirs are scanned with `{skill,skills}/**/SKILL.md`: the global config dir (XDG), project `.opencode`, `~/.opencode` and `OPENCODE_CONFIG_DIR`. The skill-disable flags do not gate them. Sources: `index.ts:205-208`; `config/paths.ts` (both sides).
4. **UNVERIFIED.** Project `.opencode` discovery depends on `OPENCODE_DISABLE_PROJECT_CONFIG`. Source: codex-chal only.
5. **CONFIRMED.** The category order is fixed: global external, project external, config dirs, `skills.paths`, `skills.urls`. Source: `index.ts:185-227`. Claude stated it; codex-chal confirmed "fixed ordering of the discovery categories".
6. **CONFIRMED.** `skills.paths` works as follows:
   - `~/` is replaced by home.
   - A non-absolute path is joined to the instance (project) dir, not to the config file's dir.
   - When `isDir` is false, it logs WARN `skill path not found` and skips the path.
   - It scans with `**/SKILL.md` at any depth.
   - The scan is unscoped, so a scan failure becomes a defect, not a log line.

   Sources: `index.ts:159-164` and `210-220` (both sides). Probe: the relative `rel` resolved from cwd, and the nested `pc/sub/probe-nested-r3` was found (Claude; codex-chal read `o1_1.json:17,23`). Codex found no `skill path not found` line in the retained `.err` files. The WARN rests on source and on Claude's report.
7. **CONFIRMED.** `skills.urls` entries are pulled and then scanned. The schema has `paths` ("Additional paths to skill folders") and `urls`, both optional string arrays. Sources: `index.ts:222-227`; `packages/core/src/v1/config/skills.ts` (both sides).
8. **CONFIRMED.** On a collision, `add()` logs `duplicate skill name` and overwrites `state.skills[name]`. Files load through `Effect.forEach(..., {concurrency:"unbounded"})`. So the completion order, not the scan order, decides the winner. Sources: `index.ts` 125-139 and 240-243 (both sides); binary string `duplicate skill name` (both sides).
9. **CONFIRMED.** Observed winners for `probe-dup-r3`:
   - `~/.agents/skills` against `~/.claude/skills`, over 8 runs: agents, agents, claude, agents, agents, agents, claude, agents.
   - With `skills.paths` pa and pb added: agents, pb, pb.

   Sources: the Claude probe; codex-chal parsed `probe-r3/d1-d8.json` and `o1_1-3.json` and got the same lists. These runs show variation. They do not measure a distribution.
10. **CONFIRMED.** The built-in `customize-opencode` is registered first. A disk skill with the same name overrides it. Source: `index.ts:275-284` (both sides).
11. **CONFIRMED.** The flags work as follows:
    - `disableExternalSkills = OPENCODE_DISABLE_EXTERNAL_SKILLS`. It skips global and project `.claude` and `.agents`.
    - `disableClaudeCodeSkills = OPENCODE_DISABLE_CLAUDE_CODE || OPENCODE_DISABLE_CLAUDE_CODE_SKILLS`. It skips only `.claude`.
    - Neither flag gates the config dirs or `skills.paths`.
    - `"1"` parses as true.

    Sources: `effect/runtime-flags.ts` 21-30; `index.ts:185-208` (both sides); Effect `Config.ts:939,966` (codex-chal). Probe results are single-side: codex says the saved artifacts do not record the env of each run.
    - EXTERNAL=1 left 4 skills.
    - CLAUDE_CODE_SKILLS=1 gave `.agents` in 6 of 6 runs.
12. **CONFIRMED.** The docs page lists six locations and the walk-up. It does not mention `skills.paths`, `skills.urls` or `OPENCODE_DISABLE_EXTERNAL_SKILLS`. Source: https://opencode.ai/docs/skills/ (both sides). The page is not versioned.
13. **CONFIRMED.** The CLI env table lists `OPENCODE_DISABLE_CLAUDE_CODE` and `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS`. It does not list `OPENCODE_DISABLE_EXTERNAL_SKILLS`. Source: https://opencode.ai/docs/cli/ (both sides). Whether the EXTERNAL flag is public is UNVERIFIED.
14. **CONFIRMED.** The skill tool passes `params.name` to `skill.require` as an exact key. The failure text is `Skill "<name>" not found. Available skills: <sorted>`. There is no namespace stripping, so `mattpocock-skills:tdd` does not resolve `tdd`. Sources: `tool/skill.ts:8-25`; `index.ts` 73-80 and 294-299 (both sides).
15. **CONFIRMED.** Identity is the frontmatter `name`. The loader does not enforce a match with the directory name: `NameMismatchError` is declared at `index.ts:67-71` but not used. A file without a string `name` is skipped with no message. Sources: `index.ts` 53-59 and 123-139 (both sides). The docs section "Validate names" asks for a match, and 1.18.34 does not enforce it.
16. **CONFIRMED (source only).** A frontmatter `name` that contains a colon, such as `mattpocock-skills:tdd`, is stored and found by that exact string. Sources: `index.ts` 53-59, 134-139, 294-299 (codex-chal; claude-r3 claim 18 from the same source). No live tool call was made.
17. **CONFIRMED.** `permission.skill` patterns filter which skills each agent sees. The permission request uses the exact `params.name`. Sources: `index.ts:310-315`; `tool/skill.ts:23-32` (both sides).
18. **CONFIRMED.** `fmt()` lists only skills with a defined description. An empty string still passes. Source: `index.ts:321-323` (both sides).
19. **UNVERIFIED.** The docs require `description`, but the loader accepts a skill without one. Source: codex-chal only (docs "Write frontmatter"; `index.ts:53-59`).
20. **CONFIRMED.** The global external roots come from `global.home`, and `global.home` follows `$HOME`. Sources: `index.ts:190-194` (both sides); `core/src/global.ts` falls back to `os.homedir()` (codex-chal); probe: the scratch `~/.agents` was read and the real one was not (Claude). That no real-home file was read at all is not proven.
21. **CONFIRMED-CORRECTED.** The probe isolation was incomplete. Run d1 loaded `~/.orca-relay/opencode-overlays/<id>/opencode.json` and `.jsonc` while the scratch `XDG_*` was set. Correction: Claude-chal wrote that the runs "read no real config". Source: `probe-r3/d1.err:8-9` (codex-chal; I re-read lines 7-9). "Empty config" in claude-r3 claim 13 means the supplied config, not the whole effective config.
22. **CONFIRMED.** `opencode debug skill </dev/null` with a scratch `HOME` and `XDG_*` runs and lists the resolved skills. Source: Claude's probes; codex-chal parsed the saved outputs. This corrects codex-r3's open point that discovery could not be probed.
23. **UNVERIFIED.** `OPENCODE_TEST_HOME`, when set, overrides `os.homedir()` for `global.home`. Source: `core/src/global.ts` (codex-chal only).

## Loop research §5 verdict

The file is `~/projects/myprysm/ultimate-agentic-loop/docs/research/2026/10/opencode-headless-mechanics.md` §5, lines 72-80.

| Loop statement | Result |
|---|---|
| Loads `~/.agents/skills` and `~/.claude/skills` (l.77) | CONFIRMED (claims 1, 9) |
| Winner changes between runs (l.76-77) | CONFIRMED (claims 8, 9) |
| "the last one scanned wins and the scan order varies between runs" (l.76) | CONFIRMED-CORRECTED: the discovery category order is fixed. Concurrent loads finish in a varying order, and the last overwrite wins (claims 5, 8). No side shows that the file order inside one glob result is stable. Codex-r3 first endorsed the Loop wording; codex-chal withdrew that. |
| EXTERNAL=1 leaves only config paths and built-in (l.77) | CONFIRMED (claim 11). "Config paths" includes the config dirs, `OPENCODE_CONFIG_DIR` and `skills.urls`, not only `skills.paths` (claims 3, 7). |
| CLAUDE_CODE_SKILLS=1 drops `.claude`, keeps `.agents` (l.78) | CONFIRMED (claim 11) |
| "The skill tool takes the bare name" (l.80) | CONFIRMED-CORRECTED: the tool takes the exact frontmatter name. `mattpocock-skills:tdd` fails because no skill has that name, not because colons are refused (claims 14, 16). |

## Corrections to earlier claims

- Loop §5 l.76 (cause of the random winner) and l.80 ("bare name") are corrected in the table above.
- codex-r3 line numbers do not match the tag file, and they are off by about 15-50 lines. Examples:
  - discovery: codex 131-188, real 148-202
  - config dirs: codex 191-194, real 205-208
  - `skills.paths`: codex 195-205, real 210-220
  - flags: codex 18-27, real 21-30

  Use the `src-r3/skill-index.ts` lines given here.
- codex-r3 claim 4 "independently supports the Loop's explanation" was withdrawn in codex-chal.
- codex-r3 open point: "discovery cannot be probed". This is corrected by claim 22.
- claude-chal-r3: "read no real config". This is corrected by claim 21.

## Open points

- The skill tool was not called in a live `opencode run`. Claims 14 and 16 are from source.
- The env of each flag probe run is not recorded in the artifacts (claim 11).
- The source of the Orca overlay config is not found (claim 21). One likely route is an `OPENCODE_CONFIG_DIR`-style overlay that Orca sets, but this is not checked.
- Is `OPENCODE_DISABLE_EXTERNAL_SKILLS` a public interface? Not known.

## Consequences for the map

- opencode reads `~/.agents/skills` and `~/.claude/skills`. With the skills-CLI layout (payload plus Claude symlink), each skill is found twice under one name. One of the two copies wins at random (claims 1, 8, 9).
- A duplicate name between `skills.paths` (a Loop pin) and `~/.agents`/`~/.claude` gives a random winner. `OPENCODE_DISABLE_EXTERNAL_SKILLS=1` removes both external families, global and project (claims 9, 11).
- The skill-disable flags do not remove the config dirs (`~/.config/opencode/skills`, `.opencode`, `~/.opencode`, `OPENCODE_CONFIG_DIR`). Project `.opencode` discovery may depend on `OPENCODE_DISABLE_PROJECT_CONFIG` (claim 4, UNVERIFIED). An Orca overlay config loaded in a scratch run (claims 3, 4, 21).
- `skills.paths` takes any dir and scans `**/SKILL.md`. One checkout root can serve opencode (claim 6).
- The name is the exact frontmatter `name`. opencode does not add or strip a plugin prefix. A name such as `mattpocock-skills:tdd` exists in opencode only when a `SKILL.md` has that exact frontmatter `name` (claims 14, 15, 16).
- The built-in `customize-opencode` can be overridden by a disk skill with the same name (claim 10).

