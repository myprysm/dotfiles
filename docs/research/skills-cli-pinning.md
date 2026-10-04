# Can the skills CLI 1.7.0 give one pinned version of a skill repo to Claude Code, codex and opencode?

Ticket: myprysm/dotfiles#108

Versions tested: skills CLI 1.7.0. Claude used the npm tarball `skills@1.7.0` in `probe-r4/pkg/package`. Codex used the npx cache `~/.npm/_npx/ac0ed6aa23b37c1e/node_modules/skills`, where `--version` gives `1.7.0`. `diff -rq` between the two is empty (codex-chal). The code is `dist/cli.mjs`. Claude ran live installs with a scratch `HOME` (`probe-r4/home`). Codex checked the retained files.

## Answer

Yes for the payload. `skills add 'mattpocock/skills#<full 40-hex sha>' -g -y -a claude-code codex opencode -s <skill>` installs that exact tree. The probe installed a tag and a full sha; the payload was byte-identical to upstream at those refs.

codex and opencode are "universal" agents. Their global install goes to `~/.agents/skills/<name>`, not to `~/.codex/skills` or `~/.config/opencode/skills`. Claude Code gets `~/.claude/skills/<name>`, which is a relative symlink to `../../.agents/skills/<name>`.

The CLI uses symlink mode when two or more distinct skill dirs are targeted together with `-y`. With one distinct dir it copies. `--copy` forces a copy.

The ref can be a branch, a tag or a full 40-hex sha. An abbreviated sha cannot select a commit. It works only when a branch or tag has that literal name. `owner/repo@x` is a skill filter, not a ref.

The global lock records the `ref` exactly as typed, but no resolved commit. No command restores from the global lock. `experimental_install` restores only the project `skills-lock.json`, and only to universal agents.

The dotfiles script `50-claude-skills` installs upstream HEAD with no ref. It skips skills that already have a symlink.

## Claims

1. **CONFIRMED.** The agent definitions in `cli.mjs` are:
   - claude-code: `.claude/skills`, global `join(claudeHome,"skills")`, at 1507-1511
   - codex: `.agents/skills`, global `join(codexHome,"skills")`, at 1571-1575
   - opencode: `.agents/skills`, global `join(configHome,"opencode/skills")`, at 1891-1895
   - universal, at 2146-2150

   Source: both sides.
2. **CONFIRMED.** `isUniversalAgent` is `skillsDir === ".agents/skills"` (`cli.mjs:2180`). For a universal agent, `getAgentBaseDir` returns `~/.agents/skills` (global) or `<cwd>/.agents/skills`, and it ignores `globalSkillsDir` (2208-2216). Sources: both sides.
   - Claude's probe: `universal: Codex, OpenCode / symlinked: Claude Code`.
   - Codex checked that `.codex` and `.config/opencode` stayed empty.
3. **CONFIRMED.** Claude Code's global dir is `~/.claude/skills/<name>` and honors `CLAUDE_CONFIG_DIR` (`cli.mjs:1396-1398`, 1511). Codex verified the symlink in the retained files: `probe-r4/home/.claude/skills/setup-pre-commit -> ../../.agents/skills/setup-pre-commit`. Sources: both sides.
4. **CONFIRMED.** The bundled README table lists Codex at `~/.codex/skills` and OpenCode at `~/.config/opencode/skills`. The runtime does not use those paths. Sources: README.md 298 and 330 against `cli.mjs:2215` (both sides).
5. **CONFIRMED.** Mode choice (`cli.mjs:5462-5483`):
   - `--copy` gives copy.
   - Two or more distinct dirs with `-y` give symlink.
   - Two or more distinct dirs without `-y` give an interactive choice.
   - One distinct dir forces copy.

   Sources: both sides. Claude's probe: `-a claude-code` alone made a real dir `tdd` and no `.agents/skills/tdd`. Codex checked the retained files.
6. **CONFIRMED.** Symlink mode copies the payload into `.agents/skills/<name>` and links Claude's path to that copy, not to the git checkout. When symlink creation fails, the CLI copies instead. The symlink is relative. Sources: `cli.mjs` 2264-2268, 2342-2350 (both sides).
7. **CONFIRMED-CORRECTED.** The canonical dir is not "written once". The installer runs for each selected target (`cli.mjs:5558-5577`), and each symlink install cleans and copies the canonical dir again (2326-2327). Overlap checks can return early. Correction: claude-r4's Answer said "written once", and claude-r4 claim 4 cited 2342 for the cleanup. Codex-chal refuted both with source. Claude did not rebut.
8. **CONFIRMED.** The copy step excludes `.git`, `__pycache__` and `metadata.json`. Source: `cli.mjs:2368-2380` (claude-r4 claim 4; codex-chal claim 4).
9. **CONFIRMED.** These ref forms work: `owner/repo#ref`, `owner/repo#ref@skill`, `https://github.com/o/r/tree/<ref>` and the GitLab tree form. `owner/repo@x` is a skill filter. Sources: `cli.mjs` 163-180, 235-251, 263-279, 295-302 (both sides).
   - Probes (Claude): the tree URL gave lock `ref: "v1.2.0"`; `@v1.2.0` gave `No matching skills found`.
   - Codex: the decisive `@` parser is at 295-302. Claude's line 161 is only a recognition regex.
10. **CONFIRMED.** A ref install runs `git clone --depth 1 --branch <ref>`. Only when the ref matches `/^[0-9a-f]{40}$/i` and the branch is missing does it fall back to `init`, then `fetch --depth 1 <sha>`, then checkout `FETCH_HEAD`. Source: `cli.mjs` 747-764, 921-937 (both sides).
11. **CONFIRMED.** A full sha and a tag install exact content. Sources:
    - Claude's probe: `#8b36d4fb2635b3c21998dcd8144439c9e5ba7302` and `#v1.2.0` installed.
    - Codex-chal byte comparison of the retained payloads: `v1.2.0 setup-pre-commit files 2 mismatches []` and `8b36d4f... tdd files 4 mismatches []`.
12. **CONFIRMED (scoped).** An abbreviated sha cannot select a commit. It is passed to `--branch`, and the sha fallback needs 40 hex. A branch or tag literally named like the short sha would still work. Sources: `cli.mjs` 747-748, 921-927 (both sides). The probe output `Failed to clone` came from Claude only.
13. **CONFIRMED-CORRECTED.** The retained data does not show the install of tag v1.2.0 differing from HEAD. Correction: claude-r4 claim 7 said it "differs (one char in SKILL.md)". Evidence:
    - Codex-chal: `git diff v1.2.0 HEAD` on those skill files in `probe-r4/src` gave no output.
    - I re-ran it: the retained clone HEAD is `8b36d4f` (2026-08-05). There is no diff for `setup-pre-commit`, `tdd` or `grilling`.

    The pin effect rests on claim 11, not on this diff.
14. **CONFIRMED.** With a ref, the blob/API fast path is skipped: `tryBlobInstall` returns null when `ref !== undefined` (`cli.mjs:4102`), so the install clones. Sources: both sides.
15. **CONFIRMED.** The global lock is `$XDG_STATE_HOME/skills/.skill-lock.json`, else `~/.agents/.skill-lock.json`. Its version is 3, and a reader drops older versions. Each entry holds `source`, `sourceType`, `sourceUrl`, `ref` (as typed), `skillPath`, `skillFolderHash`, `installedAt` and `updatedAt`. No resolved commit is stored. Sources: `cli.mjs` 3743-3760, 5644-5651; retained `probe-r4/home/.agents/.skill-lock.json` (both sides).
16. **CONFIRMED-CORRECTED.** In the probe, `skillFolderHash` equals the git tree sha: `git rev-parse v1.2.0^{commit}:skills/misc/setup-pre-commit` = `dcc584ff84c4f040ea12742fcb46b7c3ad7070bd` (both sides). Correction: this is not always a git tree sha. `cli.mjs:5640-5642` can fall back to the local SHA-256 at 1138-1147 (codex-chal; not rebutted).
17. **CONFIRMED.** For a GitHub clone install, the global hash comes from `fetchRepoTree(source, parsed.ref, getGitHubToken)`, which calls the GitHub API, anonymously first. It falls back to a local hash. Source: `cli.mjs` 3832, 3918-3928, 5628-5645 (both sides). Whether the probe called the API is UNVERIFIED.
18. **CONFIRMED.** No command restores from the global lock. `experimental_install` (`cli.mjs:8357`) runs `runInstallFromLock` (6538). It reads `skills-lock.json` in cwd, rebuilds `source#ref` (6531-6536), and calls `runAdd` with `getUniversalAgents()` and `yes:true` (6568-6573). It does not compare `computedHash`. Sources: both sides.
19. **CONFIRMED.** The project lock `skills-lock.json` is version 1. It holds `source`, `ref`, `sourceType`, `skillPath` and `computedHash` (SHA-256). It has no `sourceUrl` for shorthand. A restore into an empty dir made only `.agents/skills/grilling` and no `.claude/`. Sources:
    - Claude's probe in proj2
    - retained `probe-r4/proj2`, with byte equality to v1.2.0 (codex-chal)
    - `cli.mjs:1093`, 1138-1147
20. **CONFIRMED (source only).** Global `skills update` keeps the stored ref. It rebuilds `source/<folder>#<ref>` and checks the tree at that ref. An entry with no ref follows HEAD/main/master. A tag keeps its name; if the tag moves upstream, the content moves too. Source: `cli.mjs` 3918-3922, 6516-6536, 7362-7379, 7448-7469 (both sides). Not probed.
21. **CONFIRMED-CORRECTED.** Update skips git entries that lack `skillFolderHash` or `skillPath` (`cli.mjs:7327-7335`). Correction: before that check, `well-known` entries take their own update path, using `sourceBaseUrl` and `wellKnownDigest` (7318-7325). Source: codex-chal; not rebutted.
22. **CONFIRMED-CORRECTED.** The README has no `#ref` syntax. Correction: Azure is not the only ref-like form. README line 44 shows `npx skills add https://github.com/vercel-labs/agent-skills/tree/main/skills/web-design-guidelines` (codex-chal; I re-read lines 40-46 of the tarball README).
23. **CONFIRMED.** The dotfiles script `home/.chezmoiscripts/run_onchange_after_50-claude-skills.sh.tmpl`:
    - groups lock entries by `.source` only (63-69)
    - skips any skill whose Claude symlink exists, with `[ -L ... ] && continue` (49)
    - runs an unversioned `npx --yes skills add "$repo" -g -y -a universal claude-code -s ...` with no ref (55)

    The tracked lock `home/dot_agents/dot_skill-lock.json` has 3 entries with hashes and no `ref`. Sources: codex-r4 claim 7; claude-chal re-read; codex-chal lines.
24. **CONFIRMED.** Because of the symlink guard, a changed pin is not re-applied to a skill that is already linked. Sources: script line 49 (both challenges).
25. **UNVERIFIED.** A no-ref add for owners in the CLI's blob allow-list (vercel, vercel-labs, heygen-com, remotion-dev, `BLOB_ALLOWED_REPOS`) goes through the blob path, not a clone. mattpocock is not in the list. Source: `cli.mjs:5195-5203` (claude-chal only).
26. **UNVERIFIED.** On Windows the link is an absolute junction, not a relative symlink. Source: `cli.mjs:2264-2268` (codex-chal only).
27. **UNVERIFIED.** The copy step also excludes `__pypackages__`. Source: `cli.mjs:2368-2377` (codex-chal only).

## Corrections to earlier claims

- claude-r4 Answer, "canonical copy ... written once": corrected by claim 7.
- claude-r4 claim 7, "vs HEAD: differs (one char)": no retained evidence (claim 13).
- claude-r4 claim 11 and the Answer, "`skillFolderHash` = git tree sha": not general (claim 16).
- claude-r4 claim 16, update skip rule: `well-known` entries are an exception (claim 21).
- claude-r4 claim 17, "Azure is the only documented ref-like syntax": README:44 has a GitHub `tree/main` URL (claim 22).
- Wrong line numbers in claude-r4: the canonical cleanup is at 2326-2327, not 2342; the `@` parsing is at 295-302, not 161.
- codex-r4 marked SHA support as "not executed". Claude's probes and the retained payloads now cover it (claim 11).

## Open points

- No side tested end to end that Claude Code 2.1.289, codex 0.160.0 and opencode 1.18.34 load the installed skills.
- Two skills with one name in one repo were not tested.
- Whether the probe called the GitHub API (claim 17) is not known.
- `skills update` with a pinned ref was not probed (claim 20).
- `createSymlink` replaces a real `~/.claude/skills/<name>` dir with `rm -rf` (`cli.mjs:2255-2259`, claude-r4 only). Not probed.

## Consequences for the map

- One `skills add 'owner/repo#<40-hex sha>' -g -y -a claude-code codex opencode` writes one payload to `~/.agents/skills/<name>` and one Claude symlink. Without `-y` the CLI asks for the mode, and without `--copy` it does not force copies (claim 5). Codex and opencode read `~/.agents/skills` directly (claims 2, 3, 5, 11; see r2 and r3).
- opencode reads both `~/.agents/skills/<name>` and the Claude symlink `~/.claude/skills/<name>` → same payload. Both have the same frontmatter name, so they take the opencode collision path (findings-r3 claim 8). Both point to the same payload. No side tested whether opencode warns for two paths to one payload.
- The pin is the ref string given to `add`. A tag can move upstream; a full sha cannot (claims 10, 12, 15, 20).
- The global lock is a record only. It cannot restore. The project lock restore covers only universal agents, not the Claude symlink (claims 15, 18, 19).
- Today's script installs upstream HEAD and does not refresh skills that are already linked (claims 23, 24).
- The skills CLI places skills into the dirs that all three agents scan globally. So these skills are visible in every session, Loop sessions included, unless a session hides them: Claude `skillOverrides`, codex `-c skills.config` or `HOME`, opencode `OPENCODE_DISABLE_EXTERNAL_SKILLS` (see r1-r3).

