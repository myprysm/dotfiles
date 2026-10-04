# Handoff — skills delivery: build spec (2026-10-04)

This spec closes the map "Skills delivery to Claude Code, codex and opencode" (#104). A build
session works from it. It puts the decisions in order and gives the steps, the commits and the
checks. It does not copy the reasons. Each step cites the ticket that holds the decision.
**If this file and a ticket disagree, the ticket is correct.**

Words in this file have the meanings in `CONTEXT.md`: shared skill, agent-specific skill,
skill pin, skill bump, collision check. ADR 0002 records the path.

## Where things stand

- Today the Matt Pocock skills reach Claude Code only, through the marketplace plugin
  `mattpocock-skills@claude-plugins-official` (1.2.3, sha `c55ee46`). codex and opencode do
  not get them.
- After the build, a chezmoi external holds the skills at one skill pin. chezmoi symlinks
  each name into `~/.agents/skills` (codex, opencode) and `~/.claude/skills` (Claude Code).
  All three agents use bare names (#110, ADR 0002).
- The skills CLI entries (`find-skills`, `orca-cli`, `orchestration`, `computer-use` on WSL,
  `caveman` on the Mac) stay. No rule deletes an unknown entry in the two dirs (#115).
  Script 50 does not change (#116).
- The Loop is not changed by this build. Loop sessions see the bare names until the Loop
  proposals land. This is accepted (#110).

## Facts the build uses

- Initial pin: `c55ee46073ed923f86ce59a5eb3b6d895095d1b7` (#114, item 5). Archive URL:
  `https://github.com/mattpocock/skills/archive/c55ee46073ed923f86ce59a5eb3b6d895095d1b7.tar.gz`.
- The manifest is `.claude-plugin/plugin.json`. Its `skills` list at the pin has 25 paths.
  Each frontmatter `name` is equal to its directory name (#113):
  - `skills/engineering/`: `ask-matt`, `diagnosing-bugs`, `grill-with-docs`, `triage`,
    `improve-codebase-architecture`, `setup-matt-pocock-skills`, `tdd`, `to-spec`,
    `to-tickets`, `wayfinder`, `implement`, `prototype`, `research`, `domain-modeling`,
    `codebase-design`, `code-review`, `resolving-merge-conflicts`, `wizard`.
  - `skills/productivity/`: `grill-me`, `grilling`, `handoff`, `teach`, `to-questionnaire`,
    `wait-what`, `writing-for-agents`.
  - `skills/in-progress/` is not in the list. Do not deliver it (#110, item 4).
- Agent versions that #113 checked for collisions: Claude Code 2.1.289, codex 0.160,
  opencode 1.18.34. Two collisions are known and accepted: `code-review` (the bundled skill
  stays as `/review`) and `prototype` (the bundled skill is disabled) (#113).

## Build

One branch, one PR. Make the commits in this order. Commit format and `Refs #<n>` trailers
follow `AGENTS.md`.

### Commit 1 — `feat(skills): deliver the Matt Pocock skills from a pinned external`

Decisions: #110 items 1–4, #114 items 4, 6.

1. **Scope.** Add `skills` to the scope list in `AGENTS.md`: the skill pin, its external
   entry, the shared-skill symlinks in `~/.agents/skills` and `~/.claude/skills`, and the
   bump runbook (#114, item 6). The `AGENTS.md` rule puts a new scope in the commit that
   opens the area.
2. **External.** In `home/.chezmoiexternal.toml.tmpl`, add an entry
   `[".local/share/mattpocock-skills"]`: `type = "archive"`, the URL above, `exact = true`,
   `stripComponents = 1`, no `refreshPeriod`. Put the upstream commit subject in a comment.
   Add a one-line comment that points to `docs/runbooks/bump-skill-pin.md` (#114, items 4, 7).
3. **Symlinks.** For each of the 25 names, add two chezmoi symlink entries:
   - `home/dot_agents/skills/symlink_<name>.tmpl`
   - `home/dot_claude/skills/symlink_<name>.tmpl`

   Each file holds one line:
   `{{ .chezmoi.homeDir }}/.local/share/mattpocock-skills/skills/<category>/<name>`.
   Both links go to the payload. Do not chain one link to the other (ADR 0002). Do not make
   either directory `exact_`. The skills CLI entries must stay (#115).
4. **Before you commit,** run `chezmoi diff`. It must show the external and 50 new symlinks.
   It must not show a removal in `~/.agents/skills` or `~/.claude/skills`.

### Commit 2 — `refactor(skills): share playwright-cli through ~/.agents/skills`

Decision: #110 item 5.

1. Move `home/dot_claude/skills/playwright-cli/` to `home/dot_agents/skills/playwright-cli/`.
2. Add `home/dot_claude/skills/symlink_playwright-cli.tmpl` with the line
   `{{ .chezmoi.homeDir }}/.agents/skills/playwright-cli`.
3. `claude-permissions-review` stays in `home/dot_claude/skills/`. It is an agent-specific
   skill.
4. The `Skill(playwright-cli)` permissions in the settings template do not change.
5. Run `chezmoi diff`. The target `~/.claude/skills/playwright-cli` is a real directory
   today. Check that chezmoi replaces it with the symlink. This is not verified (see below).

### Commit 3 — `docs(skills): add the skill bump runbook`

Decision: #114, items 7, 8 and its "Bump procedure".

Write `docs/runbooks/bump-skill-pin.md`. Copy the six steps of the bump procedure from the
#114 resolution. Give the collision check its own section, because it also runs after each
`brew upgrade` of codex or opencode (#114, item 8). Put the check commands of this spec
("Checks") into step 5 of the runbook.

### Commit 4 — `docs(agents): list the bump runbook and update the deny-list reason`

Decisions: #114 item 7, #116 "Amendments".

1. Add `bump-skill-pin.md` to the Runbooks section of `AGENTS.md`.
2. In `.claude/skills/adopt/deny-list.md`, the row for `~/.agents/**`: change the reason to
   "skills-CLI and chezmoi symlinks; only the lockfile migrates".

### Commit 5 — `refactor(claude): remove the marketplace path for the Matt Pocock skills`

Decision: #116, items 1, 3.

1. In `home/.chezmoitemplates/claude-settings.json`, set
   `"mattpocock-skills@claude-plugins-official": false`. Do not delete the line.
2. In `home/.chezmoiscripts/run_once_after_51-purge-superseded-npx-skills.sh`:
   - remove `mattpocock/skills` from `SUPERSEDED`;
   - remove `mattpocock-skills@claude-plugins-official` from the install loop;
   - trim the header comment so that it names caveman only.
3. Run the script with `DRY=1` on WSL and read the plan. The edit changes the hash, so
   chezmoi runs the script one more time on each machine. That run is expected (#116, item 3).
4. Run `tests/test-claude-settings.sh`.

### After the commits — on WSL, then on the Mac

Do these steps one time on each machine, after both commits are on that machine (#116,
items 2, 5).

1. Run `chezmoi diff`, then `chezmoi apply`. Files apply before scripts (ADR 0001), so the
   symlinks and the `false` land in the same apply.
2. **WSL only, before the uninstall:** compare the payload with the plugin cache. Both are
   at `c55ee46`:
   `diff -r ~/.local/share/mattpocock-skills/skills ~/.claude/plugins/cache/claude-plugins-official/mattpocock-skills/1.2.3/skills`.
   Expect no difference.
3. Run `claude plugin uninstall mattpocock-skills@claude-plugins-official`. No script runs
   it.
4. Run `chezmoi diff` again. If the uninstall wrote `enabledPlugins`, run `chezmoi apply` to
   set `false` again.
5. Run the checks below.
6. Open sessions keep both names until they restart. This is accepted (#116, item 5).

### Issue comment

Post a comment on #14. It records that chezmoi now owns the Matt Pocock symlinks in
`~/.claude/skills` and `~/.agents/skills` (ADR 0002, #116). Write it in ASD-STE100. Then run
`git grep '#14'` and review each hit, as `AGENTS.md` requires. #116 did this review before
the build. Do it again on the build branch.

## Checks

Run these on each machine after the apply. The runbook reuses them.

1. **Names at the pin.**
   `jq -r '.skills[] | split("/")[-1]' ~/.local/share/mattpocock-skills/.claude-plugin/plugin.json`
   gives 25 names. Each name has a link in both dirs.
2. **No dangling link.** `find -L ~/.agents/skills ~/.claude/skills -maxdepth 1 -type l`
   prints nothing.
3. **No `in-progress` skill.** No link target contains `skills/in-progress/`:
   `for d in ~/.agents/skills ~/.claude/skills; do for l in "$d"/*; do [ -L "$l" ] && readlink "$l"; done; done | grep in-progress`
   prints nothing.
4. **Claude Code.** Read the `skills` array of the init event:
   `claude -p hi --model claude-haiku-4-5-20251001 --output-format stream-json --verbose --max-turns 1 | head -1 | jq -r '.skills[]'`.
   Expect the 25 bare names. Expect no `mattpocock-skills:` name after the uninstall. The
   init event shape comes from the research probes (#105, #112).
5. **opencode.** `opencode debug skill </dev/null` lists the 25 names (#107, claim 22).
6. **codex.** The research found no command that lists skills without a model turn. Ask in
   `codex exec` for the list of available skill names. The answer comes from the model, so
   it is weak evidence. Record it as such.
7. **Agent versions.** If Claude Code, codex or opencode is not at the version in "Facts the
   build uses", run the collision check of the runbook before you open the PR.

## Not in this build

- The Loop changes. The three proposals are on the Loop tracker (#110, item 6). The map
  keeps them under "Not yet specified".
- The first bump to `d81f3a1` (#114, item 5). It is the first use of the runbook. Do it in a
  separate PR.
- Renovate for the pin (#114, item 3).
- caveman, superpowers and hindsight. They stay plugins.

## Not verified — do not assume these

- chezmoi replaces the real directory `~/.claude/skills/playwright-cli` with a symlink on
  apply. Check it in `chezmoi diff` (commit 2).
- The effect of `claude plugin uninstall` on `enabledPlugins` in `settings.json` (#116,
  item 2).
- A codex skill list that does not come from the model (check 6).
- `review:off` in the user `settings.json` has no effect (#112, claim 13). The build does not
  depend on it.
- The bundled `prototype` stays disabled after a Claude Code self-update (#113, item 2).
- The effects of a scratch `HOME` outside skills, for the Loop proposals (#110, item 6).
