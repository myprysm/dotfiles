# Which `code-review` does Claude Code 2.1.289 run when a personal skill and the bundled skill share the name?

Ticket: myprysm/dotfiles#112

Versions tested: Claude Code 2.1.289 on the Mac and on WSL (binary `~/.local/share/claude/versions/2.1.289`, embedded `VERSION:"2.1.289"`). Plugin `mattpocock-skills` 1.2.3 on both machines. codex-cli 0.160.0. The docs are from code.claude.com, read 2026-10-04. The docs are not versioned.

Inputs: claude-r1, codex-r1, claude-chal, codex-chal. Side A is a Claude sonnet sub-agent. It ran live `claude -p ... --output-format stream-json --verbose` probes on the Mac (macOS) through an Orca terminal, with the model `claude-haiku-4-5-20251001`. The marker skill is the personal skill `~/.claude/skills/code-review`, a symlink to `~/.cache/probe-112/code-review`. It replies `PERSONAL-CODE-REVIEW-MARKER-112`. Side B is `codex exec` (gpt-6.1-sol, low, read-only) on WSL. It read the binary and the code.claude.com docs. Side B ran no Claude session. Side A did not check the binary byte offsets of side B. An opus agent merged the four reports. A codex run (gpt-6.1-sol, medium) audited the merge and re-read the binary offsets. The merge applied the audit fixes.

## Answer

A bare `/code-review` runs the personal skill. The Skill tool with `skill:"code-review"` also runs the personal skill.

The bundled skill has the canonical name `code-review` and the alias `review`. It has no `bundled:` prefix. When a personal `code-review` exists, the bundled skill stays reachable as `/review`.

The init `skills` list holds one bare `code-review`. The list has no source tag. You cannot tell from the list which skill it stands for.

`skillOverrides` applies to bundled skills. The key `code-review` cannot select a source:
- `{"skillOverrides":{"code-review":"off"}}` disables both skills. `/review` is disabled too.
- `{"skillOverrides":{"review":"off"}}` in a `--settings` file disables only the bundled skill. The personal skill stays. This holds when the personal skill has no `review` alias and no canonical override defeats the alias key.
- For the tested skills, no key disables the personal skill and keeps the bundled skill.

`disableBundledSkills: true` (or `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS=1`) removes the bundled `code-review`. It also removes the other bundled skills, except a few marked survivors.

In plugin 1.2.3, `implement/SKILL.md:13` tells the model to use `/code-review`. No Matt Pocock skill names the bundled skill.

## Claims

1. **CONFIRMED.** A bare `/code-review` runs the personal skill when `~/.claude/skills/code-review` exists. Sources:
   - Side A probe: `claude -p "/code-review" --model claude-haiku-4-5-20251001 --output-format stream-json --verbose --max-turns 3`. Result event: `{"result":"PERSONAL-CODE-REVIEW-MARKER-112","num_turns":1,"is_error":false}`.
   - Side B binary, loader order at byte 210845858 (side B cited 210845558; the audit re-read the offset), `[...K,...so().attachedFolderSkills?.()??[],...H,...B,...g,...h,...S,...Xj()]`. `K` holds the local skill-directory commands. `h` holds the bundled skills.
   - Side B binary, byte 206407354, resolver `function Cs(e,n){let r;return n.find((h)=>{if(h.name===e)return!0;if(r===void 0&&v8(h,e))r=h;return!1})??r}`. The first exact name wins over an alias match.
   - Side B docs: skills page, "Resolve skills that share a name". Personal and project skills replace bundled commands. Bundled aliases stay.
2. **CONFIRMED.** The bundled skill has the canonical name `code-review` and the alias `review`. It has no `bundled:` prefix. Sources:
   - Side B binary: byte 205889591 `pW="code-review"`; `function an(){As(...)` at byte 216527723 and `As({name:pW,` at byte 216527737 (audit offsets; side B cited 216527732/216527741), `function an(){As({name:pW,aliases:["review"],menuDescription:"Review the current diff or a PR for bugs and cleanups"`; byte 206998968 `As` builds `type:"prompt",name:e.name` and `source:"bundled",loadedFrom:"bundled"`, then `l.bundledSkills.push(r)`.
   - Side A probe with an empty config dir (`CLAUDE_CONFIG_DIR=~/.cache/probe-112/cfg`, not logged in): init `skills` filtered for review gave `["code-review"]`.
   - Side A probe P1 (claim 3).
3. **CONFIRMED.** With a personal `code-review` present, `/review` runs the bundled skill. Sources:
   - Side A probe P1: `/review`, no settings. Init `["code-review"]`. Result: "Repository is empty with no commits. No code to review. Did you mean to: ...". No marker.
   - Side B docs ("Resolve skills that share a name": bundled aliases stay) and binary (claims 1, 2).
4. **CONFIRMED.** The init `skills` array holds one bare `code-review`. It holds no `review` and no `bundled:code-review` entry. The array holds plain strings with no source tag. Sources:
   - Side A probe. The review-matching init entries were: `claude-permissions-review`, `code-review` (once), `caveman:caveman-review`, `mattpocock-skills:code-review`, `phpstorm-plugin:php-code-review`, `superpowers:receiving-code-review`, `superpowers:requesting-code-review`, `security-review`.
   - Side B binary, init serializer `OVe` starts at byte 214318028 and the skills serializer at byte 214319213 (audit offsets; side B cited 214317976): `skills:Fl(e.skills,"name").filter((t)=>t.userInvocable!==!1).map((t)=>t.name)`. `Fl` keeps the first entry per name (`sz` starts at byte 206224391; the excerpt `while(K--)if(x[K]===H)continue e` is at byte 206224632). Init gets its list through `AS` at byte 226493570 (`Promise.all([V_e(jm(),e),Hi(e)])`).
5. **UNVERIFIED.** The init `slash_commands` array also holds one bare `code-review`. Source: side A probe only. Side B read the `slash_commands` serializer (`slash_commands:e.commands.filter((t)=>t.userInvocable!==!1).map((t)=>t.name)`). That serializer does not deduplicate. Side B states that the result rests on the side A probe.
6. **CONFIRMED after correction.** Both command objects exist. The bundled object is registered. `gLt` removes a shadowed bundled object from the list that it processes. This does not make the bundled object unreachable: `/review` still runs it. Sources:
   - Side B binary: `As` at byte 206998968 registers bundled objects. `gLt` at byte 208927942 removes a later bundled object when an earlier command owns its name: `if(S.type==="prompt"&&S.source==="bundled"&&r.has(S.name)) return s=!0,!1;`.
   - Side A probe P1: the bundled skill still answers to `/review`. This shows that the bundled object still exists.
   - Correction: claude-r1 claim 3 said "only one registered".
7. **CONFIRMED.** The bundled `code-review` is registered without a login. Sources:
   - Side B binary: the initializer near bytes 216666900-216667200 calls `an()` with no login condition.
   - Side A probe: the empty config dir, not logged in, listed `code-review`.
8. **UNVERIFIED.** A separate `CLAUDE_CODE_ENTRYPOINT==="local-agent"` branch returns before the ordinary bundled registration. Source: side B binary only (near bytes 216666900-216667200).
9. **CONFIRMED.** `skillOverrides` applies to bundled prompt skills. Among prompt commands, only plugin prompts are exempt. Sources:
   - Side B binary: `nR` starts at byte 208926560 and the exemption at byte 208926693 (audit offsets; side B cited 208926508), `if(e.type!=="prompt"||e.source==="plugin")return"on"`. `NP` tests `return nR(e)==="off"`.
   - Side A probe P4 (claim 10).
10. **CONFIRMED.** `{"skillOverrides":{"code-review":"off"}}` in a `--settings` file disables both same-named skills. The bundled skill does not come back as a fallback. `/review` is disabled too. Sources:
    - Side A probe (claude-r1 claim 4): init loses the bare `code-review`. `mattpocock-skills:code-review` stays. `/code-review` returns `Skill "code-review" is disabled via skillOverrides. Remove the override from your settings to run it.` with `num_turns` 0.
    - Side A probe P4: `/review` with the same key returns the same message. Init (filter `test("^(code-)?review$")`) is `[]`.
    - Side B binary: `Fie` starts at byte 208926059 and the canonical-name lookup at byte 208926075 (audit offsets; side B cited 208925978), `let n=lt().skillOverrides,r=FCe(e),s=LP(n,e.name)??LP(n,r)`. The lookup uses the name only, with no source discriminator. The slash path checks the resolved object at byte 228340701 (audit offset; side B cited 228340815): `if(NP(n)){ ... "is disabled via skillOverrides" ... }`.
    - The message names `code-review` also when the user typed `/review` (side A).
11. **CONFIRMED.** For the tested personal `code-review` (no aliases) and the bundled `code-review`, no `skillOverrides` key disables the personal skill and keeps the bundled skill. The lookup has no source selector. Sources: side A probe P4 (claim 10); side B binary (no source-specific key in `Fie`).
12. **CONFIRMED for the tested configuration.** `{"skillOverrides":{"review":"off"}}` in a `--settings` file disables only the bundled skill. The personal skill stays. Conditions: the personal skill has no `review` alias, and no higher-priority canonical override defeats the alias override. Sources:
    - Side A probe P2: `/code-review` with this setting returns `PERSONAL-CODE-REVIEW-MARKER-112`. Init `["code-review"]` (file b5b; the b5a init line scrolled off).
    - Side A probe P3: `/review` with this setting returns `Skill "code-review" is disabled via skillOverrides. Remove the override from your settings to run it.` Init `["code-review"]`.
    - Side B binary: byte 208925590 `kMt=["policySettings","flagSettings"]`. `SMt` adds the aliases: `return[...e.aliases??[],...e.unqualifiedName!=null?[e.unqualifiedName]:[]]`. `Fie` reads alias keys from these two sources.
    - Side B docs: skills page, "Override skill visibility from settings". Alias overrides work in managed settings and in `--settings`. An explicit canonical-name entry has precedence in the same source.
    - Condition (side B): the personal skill has no `review` alias. Matt Pocock's `code-review/SKILL.md` declares no alias.
13. **UNVERIFIED.** An alias key in user, project or local `settings.json` has no effect. Source: side B docs ("Override skill visibility from settings") and binary (`kMt` holds only `policySettings` and `flagSettings`). Side A did not test it.
14. **CONFIRMED.** `skillOverrides` accepts four values: `on`, `name-only`, `user-invocable-only`, `off`. The schema description is: "Per-skill listing overrides keyed by skill name. 'name-only' lists the skill without its description; 'user-invocable-only' hides it from the model but keeps /name; 'off' hides it from both. Absent = on." Sources: side A binary strings; side B binary byte 200336122 `["on","name-only","user-invocable-only","off"]` and the skills page "Override skill visibility from settings".
15. **CONFIRMED.** `disableBundledSkills: true` (env `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS=1`) removes the bundled `code-review`. The personal skill and the plugin skills stay. Sources:
    - Side A probe with `--settings {"disableBundledSkills":true}`: init lost `security-review`. Init kept the personal `code-review` and `mattpocock-skills:code-review`. `/code-review` still returned the marker.
    - Side A binary description: "Disable the skills and workflows that ship with Claude Code: bundled skills and workflows are removed entirely; built-in slash commands stay typable but are hidden from the model. Plugins, .claude/skills/, and .claude/commands/ are unaffected."
    - Side B binary: `LW` at byte 202951799, `return a.CLAUDE_CODE_DISABLE_BUNDLED_SKILLS||(i??lt()).disableBundledSkills===!0`. `Ooe` (after byte 206998968) filters the bundled list. Personal and plugin skills are collected apart from `Ooe()` at byte 210843897.
16. **UNVERIFIED.** `disableBundledSkills` does not remove every bundled skill. Marked survivors stay. Only side B (binary and docs) shows the survivors. The audit re-read agrees, but it is binary evidence too. Sources:
    - Side B binary: `Ooe` runs `if(LW())return e.bundledSkills.filter((o)=>e.bundledSkillKillSwitchSurvivors.has(o))`. `As` runs `if(e.survivesBundledKillSwitch) l.bundledSkillKillSwitchSurvivors.add(r)`. `doctor` (byte 216595529) and `design` (byte 216545372) set `survivesBundledKillSwitch:!0`. `design` has more conditions. The `code-review` registration has no survivor flag.
    - Side B docs: skills page, "Bundled skills", documents the `doctor` exception.
    - Side A probe (claim 15) shows that `security-review` goes and the personal marker stays. It does not test the survivor exception.
    - Correction: claude-r1 claim 6 said the switch removes all bundled skills.
17. **UNVERIFIED.** The setting removes `simplify`, `loop`, `schedule`, `update-config` and `claude-api`. Source: side A only. Side B did not check this list.
18. **CONFIRMED.** The Skill tool resolves `skill:"code-review"` to the personal skill, the same as the slash command. Sources:
    - Side A probe: `tool_use {"name":"Skill","input":{"skill":"code-review"}}`, then `Launching skill: code-review`, then the final result `PERSONAL-CODE-REVIEW-MARKER-112`.
    - Side B binary: `oe` at byte 215281267, `function oe(e,n,s){let r=s.agentId===void 0,c=Cs(e,n);`. It uses the same `Cs` resolver as claim 1.
19. **UNVERIFIED.** The Skill-tool list can replace an earlier entry that blocks model invocation with a later model-invocable prompt. Source: side B binary only, byte 215280475, `if(c===void 0||s(c)&&!s(r)&&r.type==="prompt"&&!(woe(c)&&!woe(r)))n.set(r.name,r)`. Here `s` tests `disableModelInvocation` or `FK`. Matt Pocock's `code-review/SKILL.md` frontmatter holds only `name` and `description` (side B read). Side A states that the marker skill has the same frontmatter shape. So the exception does not apply to this case.
20. **CONFIRMED.** Plugin 1.2.3 skills refer to `code-review` by name in three places. Sources: both sides, `rg -n -i 'code.review|bundled' ~/.claude/plugins/cache/claude-plugins-official/mattpocock-skills/1.2.3/skills`.
    - `skills/engineering/implement/SKILL.md:13`: "Once done, use /code-review to review the work."
    - `skills/engineering/ask-matt/SKILL.md:26`: `/implement` "closes out by running **`/code-review`**, a two-axis review (Standards + Spec) of the diff, before committing". The file also names `/code-review` "on its own whenever you want to review a branch or PR against a fixed point."
    - `skills/engineering/tdd/SKILL.md:38`: "**Refactoring is not part of the loop.** It belongs to the review stage (see the `code-review` skill), not the red → green implementation cycle."
    - `skills/engineering/code-review/SKILL.md:2`: `name: code-review`.

    These lines are prompt text. They are not executable calls.
21. **CONFIRMED.** No Matt Pocock skill names the bundled `code-review`. The references describe Matt Pocock's own review. `code-review/SKILL.md:6` begins: "Two-axis review of the diff between `HEAD` and a fixed point the user supplies:". Sources: both sides. Side B read all 35 `SKILL.md` files.
22. **UNVERIFIED.** The only `bundled` match in the plugin skills is the git-guardrails shell script. Source: side B only.
23. **CONFIRMED after audit.** `skills/engineering/implement/SKILL.md:4` holds `disable-model-invocation: true`. Sources: side A, and the read-only audit of plugin 1.2.3.
24. **CONFIRMED after audit.** Other references to `code-review` are in `README.md:201`, `README.md:212`, `.claude-plugin/plugin.json:16` (keyword) and `.claude-plugin/plugin.json:37` (skill path). `skills/engineering/code-review/agents/openai.yaml:2` holds `display_name: "Code Review"`. Sources: side A, and the read-only audit of plugin 1.2.3.
25. **UNVERIFIED.** Under the plugin delivery (no personal `code-review`), the bare `/code-review` in `implement` resolves to the bundled skill. Sources:
    - Side A: inferred from the `plugin:` prefix of plugin skills. Not probed.
    - Side B binary: `oe` at byte 215281267 returns a `Cs` exact match before its unqualified-name fallback. So an available exact bundled name wins over a namespaced plugin candidate. Plugin namespacing is in the skills page, "Resolve skills that share a name".
    - No side ran this case. The prompt does not prove which name the model submits: `code-review` or `mattpocock-skills:code-review`.

## Corrections to earlier claims

- claude-r1 claim 3 said "only one registered". Both objects exist. `gLt` removes the shadowed bundled object from the lists that it processes (claim 6).
- claude-r1 claim 3 implied that the bundled skill is unreachable. It is reachable as `/review` (claim 3).
- claude-r1 claim 4 left open whether `code-review:off` hides the personal skill only or both. It hides both (claim 10: probe P4 and binary).
- claude-r1 claim 4 found that `code-review:off` does not bring back the bundled skill. It did not test a bundled-only hide. The challenge probes show that `review:off` in `--settings` hides the bundled skill alone (claim 12).
- claude-r1 claim 6 said `disableBundledSkills` removes all bundled skills. Side B found marked survivors (claim 16, UNVERIFIED). The alias key in claim 12 is a selective way to hide the bundled `code-review`.
- codex-r1 claim 3 did not separate registered objects from listed objects. Codex-chal claim 9 adds `gLt`.
- codex-r1 claims 1, 4 and 5 implied that `/review` stays usable. It stays usable only while the personal skill merely shadows the name. After `code-review:off`, `/review` is disabled (claim 10).
- codex-r1 claims 3 and 8 marked the runtime result as unknown. Side A probes now cover them (claims 4, 18).

## Open points

- An alias key (`review`) in user `~/.claude/settings.json` was not tested. The docs and the binary say it has no effect there (claim 13).
- The Skill tool with `skill:"review"` was not probed, with or without `review:off`.
- `name-only` and `user-invocable-only` were not run against the collision.
- Under the plugin delivery, the name that the model submits from `implement` is not known (claim 25).
- Side A did not check the binary byte offsets of side B.
- The `slash_commands` deduplication mechanism is not known (claim 5).
- Side B's alias condition "no higher-priority canonical override defeats it" was not tested.
- The empty-config probe of side A was not logged in.

## Consequences for the map

ADR 0002 delivers the Matt Pocock skills with bare names in `~/.claude/skills`. The next grilling ticket is "How is each skill-name collision solved?". Its options per name are: deliver the skill, leave it out, or hide the built-in. These facts apply:

- **Operator's sessions under ADR 0002 (conditional).** If Matt Pocock's skill loads as the personal `code-review`, a bare `/code-review` and the Skill tool `code-review` run it (claims 1, 18). The bundled skill stays reachable as `/review`, if no other command owns `review` and no setting disables the bundled skill (claim 3). The init list shows one `code-review` and cannot show which one (claim 4). The probes used a marker skill. The real ADR 0002 delivery was not probed.
- **Operator's sessions under the current plugin delivery (UNVERIFIED).** Matt Pocock's skill is `mattpocock-skills:code-review`. If the bundled `code-review` is available and no personal or project skill replaces it, the exact name `code-review` resolves to the bundled skill (claim 25). No side probed this.
- **`implement`'s bare `/code-review` (`implement/SKILL.md:13`).** Under ADR 0002, the exact name `code-review` resolves to Matt Pocock's skill (claims 1, 18). Under the plugin delivery, the exact name `code-review` resolves to the bundled skill (claim 25, UNVERIFIED). The prompt text does not prove which name the model submits. `ask-matt` and `tdd` also refer to `code-review` (claim 20). No Matt Pocock skill names the bundled skill (claim 21).
- **"Leave it out" (UNVERIFIED for execution).** The bundled `code-review` keeps the bare name, if no other personal or project skill replaces it (claims 2, 25).
- **"Deliver the skill" (conditional).** A loaded personal `code-review` takes the bare name. The bundled skill keeps `/review`, if no other command owns `review` and no setting disables it (claims 1, 3).
- **"Hide the built-in": selective mechanism.** In a `--settings` file, `{"skillOverrides":{"review":"off"}}` hides only the bundled `code-review` (claim 12, probed). This needs no personal `review` alias and no higher-priority canonical override. Managed settings: side B read support in the docs and the binary; UNVERIFIED. User, project and local `settings.json`: side B's docs and binary say alias keys have no effect there; UNVERIFIED (claim 13).
- **"Hide the built-in": wide mechanism.** `disableBundledSkills: true` or `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS=1` removes the ordinary bundled skills (claim 15). Side B found marked survivors such as `doctor`. That exception is UNVERIFIED (claim 16).
- **Key on the shared name.** `{"skillOverrides":{"code-review":"off"}}` hides both skills, `/review` included (claim 10). The #105 method of hiding a personal skill per session with a `--settings` file therefore also hides a bundled skill of the same name. For the tested skills, no key hides the personal skill and keeps the bundled one (claim 11).
- Plugin prompt skills ignore `skillOverrides` (claim 9, and #105 claim 19). Side A saw `mattpocock-skills:code-review` stay under `code-review:off` and under `disableBundledSkills: true`.
