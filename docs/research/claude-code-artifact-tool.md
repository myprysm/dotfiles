# How do you turn the Claude Code Artifact tool family off by default, and back on for one project or session?

Ticket: myprysm/dotfiles#146

Versions tested: Claude Code 2.1.296 on WSL (binary `~/.local/share/claude/versions/2.1.296`, embedded `// Version: 2.1.296`). The docs are from code.claude.com, read 2026-10-11. The docs are not versioned. One agent did this work. No second model checked it. No live session was run with the settings below. Every claim about behaviour comes from docs text or from reading the minified bundle.

"Artifact tool family" means the `Artifact` tool, the tools `ArtifactComments`, `ArtifactData` and `ArtifactCheck`, and the skills `artifact-design`, `artifact-capabilities` and `artifact-diagramming`.

## Answer

Use the settings key `enableArtifact: false` in `~/.claude/settings.json`. It is the documented switch. In the bundle it also switches off the three companion tools and the artifact skills.

```json
{
  "enableArtifact": false
}
```

You cannot turn it back on for one project or one session while this key is set in user settings. The docs say that once artifacts are off in a user or `--settings` file, or by the env var, "no settings file turns them back on". A project `"enableArtifact": true` does nothing.

The only per-session switch that works is to keep the user settings file silent about the key, and to set `CLAUDE_CODE_DISABLE_ARTIFACT=1` in the process environment by default. Then a session that starts without the variable has artifacts. That route has a cost: see claim 7.

`home/dot_claude/modify_private_settings.json` passes through unknown keys, but it replaces only the keys in `$owned`. The repo manages `enableArtifact` only when the key is in `$owned` and in `claude-settings.json`.

## Claims

1. **CONFIRMED.** A dedicated settings key exists. The schema text in the bundle reads: "Turn the Artifact tool on or off. Off in any of managed, --settings, or user settings wins; project and local settings can only turn it off. Unset defaults to on once the feature is available." The deprecated key `disableArtifact` reads: "Deprecated: use enableArtifact: false. Still honored — true disables the Artifact tool; false is ignored." Sources:
   - Docs, artifacts page, section "Disable artifacts": `"enableArtifact": false` in a settings file; "The deprecated `"disableArtifact": true` also turns artifacts off".
   - Bundle, settings schema (byte 208950221 region).
   - Docs, settings page, table "Exceptions to managed settings precedence": `enableArtifact` `false` from any scope is honored "even when a managed source sets `true`; nothing turns the Artifact tool back on. Requires Claude Code v2.1.242 or later".

2. **CONFIRMED.** An env var exists, with the exact name `CLAUDE_CODE_DISABLE_ARTIFACT`. Sources:
   - Docs, env-vars page: "Set to `1` to turn off the Artifact tool, which publishes session output as a private web page on claude.ai. Once you set it, no settings file turns the tool back on."
   - Bundle: the name is in the env-var registry (byte 207537453) and in the feature descriptor `{enableKey:"enableArtifact",legacyDisableKey:"disableArtifact",envDisableVar:"CLAUDE_CODE_DISABLE_ARTIFACT",defaultOn:!0}` (byte 215020769).
   - The variable still exists in 2.1.296. Operator-reported, not from docs: the operator measured about 20k tokens less context with this variable when the Artifact feature was released. I did not measure it. See "Unverified".

3. **CONFIRMED.** A `/config` toggle exists. The docs say: "Turn the **Artifacts** row off, which writes `"enableArtifact": false` to your user settings". The bundle `/config` row `{id:"artifacts",label:"Artifacts",...onChange: P({enableArtifact:o,disableArtifact:void 0})}` agrees (byte 229167229). The row is shown only when the bundle flag `Xe` is true. I did not check what `Xe` tests. The toggle writes user settings, so it is global, not per project.

4. **CONFIRMED.** `permissions.deny: ["Artifact"]` is a fourth documented way. The docs table in "Disable artifacts" lists "Add `Artifact` to `permissions.deny`".

5. **CONFIRMED.** A bare tool name in `deny` removes the tool definition from the model context. It does not only block calls. Docs, permissions page: "A bare tool name like `Bash` removes the tool from Claude's context entirely, so Claude never sees it." A scoped rule such as `Bash(rm *)` leaves the tool listed and blocks matching calls.

6. **PARTLY CONFIRMED.** What each mechanism removes:
   - `enableArtifact: false` or the env var. The bundle computes one switch (`y()` is true when the feature is off, `Jx()` is true when it is on). Three things read it:
     - The skills `artifact-design`, `artifact-diagramming` and the other artifact skills register with `isEnabled:Jx` (byte 225051913 region).
     - The availability test for the companion tools, `tGe(e){return bf()&&Jx()&&Id()===null&&Ke(e)}`, requires `Jx()`. The tools are `ArtifactComments`, `ArtifactData` and `ArtifactCheck`.
     - The `/artifacts` command has `isEnabled:()=>JI()&&...`, and `JI()` also requires `Jx()`.
     - So one entry covers the tool, the companion tools and the skills. I read the code. I did not run a session to see the tool list.
   - `permissions.deny: ["Artifact"]`. The bundle has a map `h_t={ArtifactComments:"Artifact",ArtifactData:"Artifact",ArtifactCheck:"Artifact"}` and an action map `y_t` (byte 216104605). It looks like a rule for `Artifact` is applied to the companion tools by action. I did not read how permission checks use that map, and I did not read how the tool list is filtered. Whether a bare `Artifact` deny also removes the three companion tools from the context is UNVERIFIED. The skills do not read the deny rules (their `isEnabled` is `Jx`), so a deny rule leaves the three artifact skills listed. Inference from the code, not tested.
   - `skillOverrides` and `disableBundledSkills`. See claim 8.

7. **CONFIRMED, with a gap.** Re-enabling. Sources: docs artifacts page, settings page, env-vars page, bundle function `L(e)` (byte 215020703 region).
   - The bundle function decides `enabled` as: no source says off, and `defaultOn` is true. A source says off when: the env var is truthy; `enableArtifact` is `false` in `policySettings`, `flagSettings` (`--settings`), `userSettings`, `localSettings` or `projectSettings`; or `disableArtifact` is `true` in any of them. A `true` never cancels a `false`.
   - So a project `.claude/settings.json` cannot turn on what user settings turned off. The docs say the same: "An `"enableArtifact": true` in either file doesn't turn them back on."
   - The env var is read from the process environment, from `env` in `flagSettings` and from `env` in `userSettings` (bundle `ae(e)`: `a[e]`, then `cn(n)&&Ne(E(fe(n)?.env,e))` for `["flagSettings","userSettings"]`). A project `env` block is not in that list. Do not rely on this to set it per project.
   - The docs say the `env` block in `settings.json` works for ordinary variables, and the env-vars page states no scope limit for `CLAUDE_CODE_DISABLE_ARTIFACT`. So `"env": {"CLAUDE_CODE_DISABLE_ARTIFACT": "1"}` in `~/.claude/settings.json` should work. The bundle supports it for user settings. Setting it there cannot be undone per session, because the user file is always read.
   - Per session: there is no CLI flag for artifacts. The only per-session lever is the process env var set by the shell, with the user settings file silent on the key. Starting `claude` without the variable then gives artifacts. Whether an empty or `0` value counts as off is UNVERIFIED (`Ne` was not read). Use `env -u CLAUDE_CODE_DISABLE_ARTIFACT claude` for a session that wants artifacts.
   - `--settings` (flag settings) can only turn artifacts off, never on. A `--settings` file with `enableArtifact: true` cannot override a user `false`.
   - Cost of the env route: the variable must be set wherever `claude` starts (zsh, Orca terminals, IDE launchers, the Mac). A launcher that skips the shell profile starts a session with artifacts on. The settings key does not have this gap.

8. **CONFIRMED for semantics, UNVERIFIED for the artifact skills.** Docs, skills page, "Override skill visibility from settings": `skillOverrides` is a map from skill name to `"on"`, `"name-only"`, `"user-invocable-only"` or `"off"`. `"off"` hides the skill from the model and from the `/` menu. A hidden skill returns the `skillOverrides` error. "In user, project, and local settings, Claude Code matches entries against skill names only." "Plugin skills are not affected by `skillOverrides`." It applies to bundled skills (see `docs/research/claude-code-skill-name-collision.md`, claim on `skillOverrides`). I did not confirm that `artifact-design` and `artifact-capabilities` are bundled skills that `skillOverrides` can reach. The bundle registers them with `Gs({name:J4,...})` like other bundled skills. `skillOverrides` would hide the skills but leave the `Artifact` tool and its long description in the context. It is the weaker option. `disableBundledSkills: true` (docs, settings page; also `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS=1`) removes all bundled skills and workflows. It is far wider than the goal.

9. **CONFIRMED.** Headless does not load the family. Docs, artifacts page, "Availability", row Surface: "Off by default in the Agent SDK, the GitHub Action, and MCP-server contexts, when you run Claude Code with `-p` from your own terminal or scripts, and when `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` is set." This matches the operator's `claude -p "/context"` measurement. The bundle also has `isArtifactSdkDefaultOff` and `c_r()` (SDK, GitHub Action and MCP entry points).

10. **CONFIRMED.** The artifact family has other availability limits that already switch it off: a claude.ai login is required, and Bedrock, Vertex and Foundry are excluded (docs, "Availability"). They do not help here, because the operator's sessions are logged in.

## claude.ai connectors (measurement only, no recommendation)

The Gmail, Calendar, Drive and Claude Docs servers come from claude.ai. They are separate from the artifact switch. `enableArtifact: false` does not turn them off. The docs, "Share session output as artifacts", say the Claude Docs connector is a separate path from the Artifact tool.

- `disableClaudeAiConnectors: true` in any settings scope turns off the connectors that Claude Code fetches itself. Docs, MCP page, "Disable claude.ai connectors": "`true` in any settings source takes precedence … a project-level `false` can't re-enable connectors that a user- or policy-level `true` has disabled. Servers passed explicitly via `--mcp-config` are unaffected." It does not reach connectors that a cloud host or the desktop app delivers.
- `ENABLE_CLAUDEAI_MCP_SERVERS=false` in the environment has "the same effect for the current shell session" (same docs section). I did not find its row in the env-vars page text I read.
- `deniedMcpServers` blocks single connectors by name or URL, for example a `serverName` entry `"claude.ai Slack"` or `"claude.ai Claude Docs"`.
- `/mcp` toggles one connector off for the current project only. Claude Code writes the name to `disabledMcpServers`.
- `syncClaudeAiSkills: false` stops the sync of skills enabled on claude.ai. Docs, skills page, "How synced skills behave": set it in user settings; synced skills move to `~/.claude/skills/.trash/` at the next start. The settings table lists the scopes as "User, local, or managed", and `.claude/settings.json` is ignored for it ("a `false` in `.claude/settings.json` is ignored").
- `syncClaudeAiPlugins: false` does the same for synced plugins.

## Trade-offs

| Mechanism | Removes the tool | Removes the companion tools and skills | Per-project or per-session re-enable | Notes |
| :- | :- | :- | :- | :- |
| `enableArtifact: false` (user settings) | yes (docs) | yes (bundle `Jx()`, not run) | no (docs) | Documented. Repo must add the key to `$owned`. `/config` flips the same key globally. |
| `CLAUDE_CODE_DISABLE_ARTIFACT=1` in the `env` block | yes (docs) | yes (same switch) | no | Same effect as the key. No benefit over it. |
| `CLAUDE_CODE_DISABLE_ARTIFACT=1` in the shell profile only | yes | yes | yes, per session: start `claude` without it | A launcher that skips the profile gets artifacts on. Empty or `0` behaviour unverified. |
| `permissions.deny: ["Artifact"]` | yes (docs: bare name leaves the context) | companion tools unverified; skills stay | no (a deny beats any allow, docs) | The repo already owns `permissions`. |
| `skillOverrides` on the artifact skills | no | skills only | project and local files may use `"on"`; a user `"off"` precedence is not documented | Leaves the tool and its description in every turn. |
| `disableBundledSkills` | no | all bundled skills | no | Too wide. |

## Recommendation

Use `"enableArtifact": false` in `~/.claude/settings.json`, owned by the template. It is the documented key. It covers the tool, the companion tools and the skills in one entry. It does not depend on how the session starts.

Accept the loss: there is no per-project or per-session turn-on from a settings file. For a rare artifact session, flip the `/config` Artifacts row (writes the user file, global), or edit the file. If the operator needs a real per-session turn-on, drop the key and use the shell-profile env var route, and accept that launchers which skip the profile start with artifacts on.

## Unverified

- No session was run. The context drop from `enableArtifact: false` was not measured. The tool-list claims come from the bundle code.
- The operator's "about 20k tokens" figure is operator-reported, from the feature release. Not checked against 2.1.296.
- Whether a bare `Artifact` deny rule also removes `ArtifactComments`, `ArtifactData` and `ArtifactCheck` from the context (claim 6).
- Whether `CLAUDE_CODE_DISABLE_ARTIFACT=0` or an empty value counts as off (the helper `Ne` was not read).
- Whether the `env` block of a project `.claude/settings.json` can set the variable. The bundle checks only the process env, `--settings` env and user settings env, but I did not read the full env merge code.
- Whether `skillOverrides` can reach `artifact-design` and `artifact-capabilities` by name. The `/skills` menu was not checked.
- What the bundle flag `Xe` tests before the `/config` Artifacts row shows. The row may be hidden on some accounts.
- The `ENABLE_CLAUDEAI_MCP_SERVERS` env-vars row was not read. The claim rests on the MCP page.
