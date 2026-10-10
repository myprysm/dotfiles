# Handoff — hindsight for Claude Code, codex and opencode: build spec (2026-10-04)

This spec closes the map "Hindsight for Claude Code, codex and opencode" (#121). A build
session works from it. It puts the decisions in order and gives the steps, the commits and the
checks. It does not copy the reasons. Each step cites the ticket that holds the decision.
**If this file and a ticket disagree, the ticket is correct.**

Words in this file have the meanings in `CONTEXT.md`: enrolled machine, hindsight pin,
hindsight bump, hindsight wiring, hindsight opt-out. ADR 0003 records who writes the wiring.

## Where things stand

- Today the legacy Claude Code plugin `hindsight-memory@hindsight` is on every machine. The
  settings template enables it (`home/.chezmoitemplates/claude-settings.json`). WSL has 0.7.2,
  the Mac has 0.7.5 (#125, #130). codex and opencode have no hindsight.
- After the build, hindsight is opt-in. A machine gets it only when its `hindsight` bundle is
  on (#126). The runtime is `@vectorize-io/hindsight-coding-agents` at one hindsight pin
  (#133, #129). chezmoi writes all of the wiring. The upstream installer never runs on a real
  machine (#134, ADR 0003).
- All agents on all machines use one static bank, `damien-main-memory`. Hermes uses the same
  bank (#127).
- The hindsight bundle wires each agent whose config the repo manages on that machine. WSL has
  `bundleList = ["ops","playwright","go"]`, so only Claude Code gets wiring there. The Mac has
  all eight bundles, so all three agents get wiring there (#125, #126).
- On the branch `damienbenon/hindsight-config`, not pushed: the glossary terms in `CONTEXT.md`
  (commits `2bcd307`, `b8e8a06`, `f144864`, `c350658`) and ADR 0003 (`e13619f`).
- The hindsight server is not changed by this build. talos-home owns it.

## Facts the build uses

- **Initial pin: 0.8.0** (#131, item 6). #127, #132 and #134 read the source of this version.
  - Tarball: `https://registry.npmjs.org/@vectorize-io/hindsight-coding-agents/-/hindsight-coding-agents-0.8.0.tgz`
  - sha256 of that tarball, calculated on 2026-10-04 from `npm pack`:
    `afc489206154f2e7254057e52b455be8751e8b8bbf5e4a720a104c136fbeed7c`. Calculate it again
    before commit 5. If it is different, stop and tell the operator.
  - The tarball root is `package/`. Thus `stripComponents = 1`.
- **Hook entry files** (`dist/installer.js:3740-3762` in 0.8.0):

  | Event | Timeout | Claude Code entry | codex entry |
  |---|---|---|---|
  | `SessionStart` | 30 s | `claude-sessionstart-hook.js` | `codex-sessionstart-hook.js` |
  | `UserPromptSubmit` | 30 s | `claude-hook.js` | `codex-hook.js` |
  | `Stop` | 60 s | `claude-stop-hook.js` | `codex-stop-hook.js` |

- **MCP server:** `node <home>/.hindsight/coding-agents/dist/mcp-server.js`. Claude Code env:
  `HINDSIGHT_MCP_HARNESS=claude-code`. codex env: `HINDSIGHT_MCP_HARNESS=codex`
  (`installer.js:5108`, `:5137-5140`).
- **opencode plugin:** the directory `<home>/.hindsight/coding-agents`. opencode v1 loads
  `dist/index.js` through `main`. opencode v2 loads the root `index.js` (#132, #134).
- **`~/.hindsight/coding-agent.json`** after an apply (#127, #128, #129, #131 item 7):

  | Key | Value | Source |
  |---|---|---|
  | `serverMode`, `apiUrl`, `apiToken` | from the restore | Bitwarden (#128) |
  | `optInOnly` | absent | the template removes it (#128) |
  | `bankId` | `"damien-main-memory"` | #127 |
  | `manageBankConfig` | `false` | #127 |
  | `pages` | all five keys `false`, no `customPages` | #127 |
  | `retainTags` | `["project:{gitProject}"]` | #127 |
  | `retainMetadata` | `{"repo": "{gitProject}"}` | #127 |
  | `autoSeed` / `gitIngest` | `false` / `"none"` | #127 |
  | `codebaseSurvey` | `false` | #127 |
  | `autoUpdate` | `false` | #129 |
  | `autoInject` | `"recall"` | #127, amended at enrollment |

  No `harnesses` section. `observationScopes`, `retainSessions` and `retainExtractionMode`
  stay at their defaults (#127). Read the five `pages` key names from
  the 0.8.0 README, section "Reference".
- **Bitwarden restore item** (#128, #126): personal domain, folder `dotfiles/restore`. Fields:
  `path` = `.hindsight/coding-agent.json`, `mode` = `600`, `bundle` = `hindsight`. Body: JSON
  with only `serverMode` (`"self-hosted"`), `apiUrl`, `apiToken` and `"optInOnly": true`. One
  item for both machines.
- **Gate expression:** `index .bundles "hindsight"` in every template. Do not use
  `.bundles.hindsight`. A config from before the bundle has no such key (#126, #27).
- **Bundle helper in the scripts:** `work_bundle_enabled` (`scripts/secrets-common.sh:118`)
  reads `chezmoi data` and treats an absent key as off. #126 names `chezmoi execute-template`.
  Both read the same data and give the same result. Use the existing pattern.

## Build

One branch, one PR. Make the commits in this order (#131, item 5). Commit format and
`Refs #<n>` trailers follow `AGENTS.md`. Each commit names its test. Run the test before the
commit.

### Commit 1 — `feat(secret-guard): deny the whole ~/.hindsight directory`

Decision: #128 "Guard rules".

1. In `cmd/secret-guard/policy.go`, replace the `.hindsight/claude-code.json` arm (line 123)
   with a directory arm for `~/.hindsight/`. The `cd` arm (line 398) stays.
2. In `cmd/secret-guard/glob.go`, replace the `.hindsight/claude-code.json` entry (line 49)
   with a directory entry.
3. Add test cases: a read of `~/.hindsight/coding-agent.json`, a read under
   `~/.hindsight/coding-agents/`, and a read under `~/.hindsight/coding-agents-logs/`. All
   are `deny`. The existing `claude-code.json` cases stay `deny`.
4. Test: `go test ./cmd/secret-guard/`.

The new rule reaches a machine only through a secret-guard release. See "After the commits".

### Commit 2 — `feat(claude): deny reads under ~/.hindsight`

Decision: #128 "Guard rules".

1. In `home/dot_claude/hooks/executable_block-secret-reads.sh.tmpl`, replace the
   `claude-code.json` arm (line 173) with a directory arm. Update the deny message (line 24).
2. In `home/.chezmoitemplates/claude-settings.json`, replace
   `Read(/{{ .chezmoi.homeDir }}/.hindsight/claude-code.json)` with
   `Read(/{{ .chezmoi.homeDir }}/.hindsight/**)`.
3. The adopt deny-list does not change. It already lists `~/.hindsight/`.
4. Test: `tests/test-block-secret-reads.sh` with new cases for the three paths of commit 1,
   and `tests/test-claude-settings.sh`.

### Commit 3 — `feat(secrets): gate a restore item on a bundle`

Decision: #126 "Restore gate".

1. In `scripts/secrets-common.sh`, add `bundle_enabled <name>`. It works like
   `work_bundle_enabled`: absent key or absent chezmoi means off.
2. In `scripts/secrets-restore.sh`, read the optional field `bundle` of each personal restore
   item. When the field is set and the bundle is off, skip the item before it reads the vault.
   An item without the field is not gated.
3. In `scripts/secrets-audit.sh`, print a note, not a finding, for a gated item when its bundle
   is off.
4. In `docs/secrets.md`, document the `bundle` field.
5. Test: `tests/test-secrets-common.sh`, with cases for `bundle_enabled` on, off, key absent
   and chezmoi absent.

### Commit 4 — `feat(hindsight): add the hindsight bundle`

Decisions: #126 "Mechanism", #131 item 4 (scope).

1. In `home/.chezmoi.toml.tmpl`, add `"hindsight"` to `$bundles`. The default list stays empty.
2. The scope `hindsight` is already in `AGENTS.md`. The commit of this spec added it, because
   that commit opened the area.
3. Expect the warning of #27 on both machines until `chezmoi init` runs.
4. Test: `chezmoi init --no-tty </dev/null` does not prompt, then
   `chezmoi data --format json | jq .bundles.hindsight` gives `false`.

### Commit 5 — `feat(hindsight): stage the pinned runtime and merge coding-agent.json`

Decisions: #129 "Pin", #134 item 3, #127, #128 "Mode", #131 items 6, 7.

1. **Pin.** Add `home/.chezmoidata/hindsight.yaml` with the version and the sha256 of
   "Facts the build uses". This is the one repo value of the hindsight pin (#129).
2. **External.** In `home/.chezmoiexternal.toml.tmpl`, add `[".hindsight/coding-agents"]`
   inside `{{ if index .bundles "hindsight" }}`: `type = "archive"`, the tarball URL built
   from the pin, `exact = true`, `stripComponents = 1`, `checksum.sha256` from the pin, no
   `refreshPeriod`. Add a one-line comment that points to `docs/runbooks/bump-hindsight-pin.md`.
3. **Config merge.** Add the modify template
   `home/private_dot_hindsight/modify_private_coding-agent.json`. It keeps `serverMode`,
   `apiUrl` and `apiToken` from stdin. It removes `optInOnly`. It sets the keys of the table in
   "Facts the build uses". The `private_` prefixes give mode 700 to `~/.hindsight/` and mode
   600 to the file (#131, item 7).
4. **Gate.** In `home/.chezmoiignore`, inside `{{ if not (index .bundles "hindsight") }}`,
   ignore `.hindsight/coding-agent.json`.
5. Test: render the template against fixtures in a scratch `HOME`, as
   `tests/test-codex-config.sh` does. Add `tests/test-hindsight-config.sh`. Cases: a restore
   body on stdin keeps the three credential keys and loses `optInOnly`; each key of the table
   has its value; empty stdin gives no credential key. Use dummy values only.

### Commit 6 — `feat(claude): wire hindsight hooks and MCP on an enrolled machine`

Decisions: #134 items 5, 6; #126 "Unenrollment"; #130 item 4.

1. **Wrapper.** Add `home/dot_claude/hooks/executable_hindsight-hook.sh`. It runs
   `exec node "$HOME/.hindsight/coding-agents/dist/$1"`. It has no other logic (#135,
   "Effect on other tickets"). Ignore it in `.chezmoiignore` when the bundle is off.
2. **Hooks.** In `home/.chezmoitemplates/claude-settings.json`, inside the bundle gate, add
   one entry to each of `SessionStart`, `UserPromptSubmit` and `Stop`. Command:
   `bash {{ .chezmoi.homeDir }}/.claude/hooks/hindsight-hook.sh <Claude Code entry>`. Use
   the timeouts of the table. The hook ownership of #73 applies without change.
3. **MCP allow entry.** Inside the bundle gate, add
   `mcp__hindsight__agent_knowledge_ingest` to `permissions.allow` (#130, item 4). Commit 9
   removes the old entry.
4. **MCP script.** Add `home/.chezmoiscripts/run_onchange_after_60-hindsight-mcp.sh.tmpl`. Put
   the gate value in a comment, so that the script hash changes with the gate.
   - Enrolled: `claude mcp remove --scope user hindsight`, then
     `claude mcp add --scope user hindsight --env HINDSIGHT_MCP_HARNESS=claude-code -- node {{ .chezmoi.homeDir }}/.hindsight/coding-agents/dist/mcp-server.js`.
   - Not enrolled: `claude mcp remove --scope user hindsight` only when the entry exists.
   - If `claude` is not on `PATH`, print a warning and exit 0.
5. Test: `tests/test-claude-settings.sh` with the bundle on and off. On: the three hook
   entries and the allow entry are present. Off: none of them are present.

### Commit 7 — `feat(codex): wire hindsight hooks and MCP in config.toml`

Decision: #134 item 4.

1. In the `codex-config.toml` template, inside the bundle gate, add `hooks.SessionStart`,
   `hooks.UserPromptSubmit`, `hooks.Stop` and `[mcp_servers.hindsight]`. Hook command:
   `bash {{ .chezmoi.homeDir }}/.claude/hooks/hindsight-hook.sh <codex entry>`. MCP:
   `command = "node"`, `args = ["<home>/.hindsight/coding-agents/dist/mcp-server.js"]`,
   `env = { HINDSIGHT_MCP_HARNESS = "codex" }`.
2. In `home/dot_codex/modify_private_config.toml`, own these four keys as it owns
   `hooks.PreToolUse`: replace each key whole, or remove it when the base does not have it.
   Pre-seed the trust hash of each new hook with the #96 formula. The event names are
   `session_start`, `user_prompt_submit` and `stop`. The template never touches `hooks.json`.
3. If codex 0.160 needs `[features] hooks = true` (see "Not verified"), the template also owns
   `features.hooks`.
4. Test: `tests/test-codex-config.sh`. Add cases: bundle on gives the four keys and a trust
   hash for each new hook; bundle off removes them; the `pre_tool_use` cases do not change.

### Commit 8 — `feat(opencode): add the hindsight plugin on an enrolled machine`

Decision: #134 item 7.

1. Rename `home/dot_config/opencode/opencode.json` to `opencode.json.tmpl`.
2. Inside the bundle gate, add `"plugin": ["{{ .chezmoi.homeDir }}/.hindsight/coding-agents"]`.
3. Test: `chezmoi execute-template` of the file, with the bundle on and off. Pipe each result
   through `jq`. On: `.plugin` is the one path. Off: `.plugin` is absent.

### Commit 9 — `feat(claude): remove the legacy hindsight plugin`

Decision: #130 items 1, 4.

1. In `home/.chezmoitemplates/claude-settings.json`, remove the line
   `"hindsight-memory@hindsight": true` from `enabledPlugins`. Remove the `hindsight` entry
   from `extraKnownMarketplaces`. No gate. The modify template owns both keys, so the next
   apply removes them from the live file.
2. Remove `mcp__plugin_hindsight-memory_hindsight__agent_knowledge_ingest` from
   `permissions.allow`.
3. Test: `tests/test-claude-settings.sh`.

### Commit 10 — `feat(hindsight): remove hindsight files from an unenrolled machine`

Decisions: #126 "Unenrollment", #130 item 3.

Build result: chezmoi 2.73.0 renders `.chezmoiremove` as a template and removes without a
prompt. But it does not remove a target that `.chezmoiignore` also lists. Thus, with the
operator's approval, `.chezmoiremove` lists only the legacy files, and the script
`run_onchange_after_61-hindsight-unenroll.sh.tmpl` removes the off-state files (#126).

1. `home/.chezmoiremove` lists `.hindsight/claude-code.json` and `.hindsight/codex.json` on
   every machine (#130, item 3).
2. When the bundle is off, the unenroll script removes `.hindsight/coding-agents`,
   `.hindsight/coding-agent.json` and `.claude/hooks/hindsight-hook.sh` (#126). The script
   hash holds the bundle state.
3. The Claude MCP entry is removed by the script of commit 6. The shared files lose their
   wiring through their templates.
4. Test: an apply in a scratch `HOME` with the bundle on, then off.

### Commit 11 — `docs(hindsight): add the hindsight bump runbook`

Decision: #129 "Bump checks", #134 item 8.

Write `docs/runbooks/bump-hindsight-pin.md`. Copy the six checks of #129. Check 2 is the dry
run of #132 in a scratch `HOME`; give its exact method from the #132 resolution. Check 6 is:
run `chezmoi apply` on each enrolled machine, then restart the open agent sessions (#134,
item 8). Add the step that calculates `checksum.sha256` from the registry tarball. Put the
"Checks" of this spec into the runbook. Every headless probe in the runbook sets
`HINDSIGHT_DISABLE_HOOKS=1` (#135, item 4).

### Commit 12 — `docs(agents): list the hindsight bump runbook`

Decision: #129 "Bump checks".

Add `bump-hindsight-pin.md` to the Runbooks section of `AGENTS.md`.

### Commit 13 — `docs(skills): set the hindsight opt-out on the headless probes`

Decision: #135 item 4.

Prefix each headless session with `HINDSIGHT_DISABLE_HOOKS=1` at these sites:

- `docs/runbooks/bump-skill-pin.md:183` (`claude -p`).
- `docs/runbooks/bump-skill-pin.md:200` (`codex exec`).
- `docs/handoff/2026-10-04-skills-delivery.md:152` (check 4, `claude -p`) and `:157`
  (check 6, `codex exec`).

On 2026-10-04, `git grep -n -E 'claude -p|codex exec|opencode run'` outside `docs/research/`
found no other probe. Run it again before the commit.

## After the commits: enroll WSL, then the Mac

Decisions: #130 items 2, 5, 6; #128 "Order"; #131 item 5.

1. **Guard release first.** Cut a secret-guard release from `main` with the rule of commit 1.
   Follow "TO CUT A RELEASE" in `home/.chezmoidata/secret-guard.yaml`. The tag push needs the
   operator's approval. Apply the new version on each machine before step 4 on that machine.
   No credential reaches a machine before its guard (#131, item 5).
2. **WSL only.** The operator creates the Bitwarden restore item of "Facts the build uses".
   The operator copies the URL and the token from `~/.hindsight/claude-code.json`. No agent
   reads that file. The item must exist before step 5.
3. Pull the source without an apply: `chezmoi git pull -- --ff-only`. Do not run
   `chezmoi update`.
4. Add `hindsight` to `bundleList` in `~/.config/chezmoi/chezmoi.toml`. Run `chezmoi init`.
5. Run `scripts/secrets-restore.sh`.
6. Run `chezmoi diff`, then `chezmoi apply`. This stages the runtime, merges
   `coding-agent.json`, writes the wiring, removes the legacy plugin keys and removes the
   legacy files.
7. Run `claude plugin uninstall hindsight-memory@hindsight`, then
   `claude plugin marketplace remove hindsight`. `claude plugin list` must show no hindsight
   entry (#130, item 2).
8. If `~/.claude/plugins/data/hindsight-memory-hindsight/` still exists, remove it with
   `rm -rf`. It holds recalled memory text (#130, "Build checks").
9. Restart the agent sessions. Run the checks below.
10. **The Mac.** Do steps 3 to 9. Skip step 2: the item is shared (#128). Do not look for the
    source of the old Mac settings (#130, item 6).

Run `chezmoi apply` after each later restore. A restore writes the whole file and removes the
repo-owned keys (#128, "Order").

## Unenroll

Decision: #126 "Unenrollment".

1. Remove `hindsight` from `bundleList`. Run `chezmoi init`.
2. Run `chezmoi apply`. The unenroll script removes the runtime, `coding-agent.json` and the
   wrapper (#126). `.chezmoiremove` cannot remove them, because `.chezmoiignore` lists them
   when the bundle is off. The MCP script removes the Claude MCP entry. The templates remove
   the hooks, the codex keys and the opencode entry.
3. Restart the agent sessions.
4. The vault keeps the item. A new enrollment restores it.

## Checks

Run these on each machine after the apply. The runbook reuses them. The guard denies every
path under `~/.hindsight/` to an agent. **The operator runs the checks marked (operator)** in
a terminal without an agent.

1. **Modes** (operator). `~/.hindsight/` is 700 and `coding-agent.json` is 600. Linux:
   `stat -c '%a %n' ~/.hindsight ~/.hindsight/coding-agent.json`. macOS:
   `stat -f '%Lp %N' ~/.hindsight ~/.hindsight/coding-agent.json`.
2. **Repo keys** (operator). This prints no credential:
   `jq '{bankId, autoUpdate, optInOnly, manageBankConfig, codebaseSurvey, gitIngest}' ~/.hindsight/coding-agent.json`.
   Expect `damien-main-memory`, `false`, `null`, `false`, `false`, `"none"` (#127, #129).
3. **Runtime** (operator). `jq -r .version ~/.hindsight/coding-agents/package.json` gives the
   pin. `~/.hindsight/coding-agents/.install-origin.json` does not exist (#134, item 3).
4. **Guard.** An agent `Read` of `~/.hindsight/coding-agent.json` is denied. An agent
   `cat ~/.hindsight/coding-agents/package.json` is denied.
5. **Claude Code wiring.**
   `jq '[.hooks[][] .hooks[].command | select(test("hindsight-hook"))]' ~/.claude/settings.json`
   gives three commands. `claude mcp get hindsight` shows the `node` command and
   `HINDSIGHT_MCP_HARNESS=claude-code`.
6. **codex wiring** (Mac). `python3 -c 'import tomllib,sys; c=tomllib.load(open(sys.argv[1],"rb")); print(sorted(c["hooks"]), "hindsight" in c["mcp_servers"])' ~/.codex/config.toml`
   lists `SessionStart`, `Stop` and `UserPromptSubmit` (beside `PreToolUse` and `state`) and
   gives `True`.
7. **opencode wiring** (Mac). `jq .plugin ~/.config/opencode/opencode.json` gives the one path.
8. **Legacy gone.** `claude plugin list` has no hindsight entry. `enabledPlugins` and
   `extraKnownMarketplaces` in `~/.claude/settings.json` have no hindsight key. (operator)
   `~/.hindsight/claude-code.json` and `~/.hindsight/codex.json` do not exist.
9. **End to end.** In each wired agent, call the `hindsight_diagnose` MCP tool. Then recall
   one memory from `damien-main-memory` (#130, item 5).
10. **Reflect latency.** Measure `autoInject` `reflect` with `low` effort on this server, and
    record the result (#127).

## Known limit

Every session on an enrolled machine retains its transcript to `damien-main-memory` (#135).
A secret that a session reads, prints or receives goes into the bank. The legacy plugin
already retains full sessions on WSL, so this risk is not new (#131, item 1).

## Not in this build

- The hindsight server: hosting, upgrade, configuration. talos-home owns it.
- A hindsight bump past 0.8.0. It is the first use of the runbook. Do it in a separate PR.
- A per-repo bank. The override exists (`mapPathToBank` or `banks.<id>`), but no repo gets one
  (#127).
- The bundled `hindsight-coding-agent` skill (#134, item 2).
- Per-machine tokens, a move of bank data, the hermes config, native Windows.
- Consumption of the talos-home mental models by codex and opencode (#131).
- Hindsight for Loop Actors. The Loop owns the Actor config (#135). The proposed Loop ticket
  "Mask `~/.hindsight` in the Actor sandbox" is for the operator to decide (#135).

## Not verified — do not assume these

- The #96 hash formula for `session_start`, `user_prompt_submit` and `stop`. It is verified
  only for `pre_tool_use` (#134).
- If codex 0.160 needs `[features] hooks = true` (#134).
- chezmoi renders `.chezmoiremove` as a template, and `chezmoi apply` removes without a
  prompt (#126).
- `.chezmoiremove` removes a target that `.chezmoiignore` also lists. Commits 5, 6 and 10 use
  both on the same paths.
- The `private_` prefix on a `modify_` template sets mode 600 on a file that exists with mode
  644 (#128, #131 item 7).
- The runtime writes no file inside `~/.hindsight/coding-agents/`. The external is `exact`. A
  file that the runtime writes there is removed by the next apply, or stops the apply. If it
  writes one, add a `.chezmoiignore` entry, as for `.oh-my-zsh/cache/*`.
- What the runtime does when `coding-agent.json` has no `apiUrl`, for example after an apply
  without a restore. Step 5 comes before step 6 for this reason.
- A restored file with `"optInOnly": true` and no opt-in path retains nothing (#128).
- The runtime logs under `~/.hindsight/coding-agents-logs/` mask the token. The guard treats
  them as a credential until this is verified (#128).
- `claude plugin uninstall` removes `~/.claude/plugins/data/hindsight-memory-hindsight/`
  (#130). Step 8 covers the case where it does not.
- The new MCP server exposes `agent_knowledge_ingest` with the same name (#130). Check it in
  `claude mcp get hindsight` or in the tool list after the restart.
- What Claude Code does with an installed plugin that is not in `enabledPlugins` (#130).
  Record the answer.
- `claude -p` and `opencode run` run the hooks and the plugin (#135). `codex exec` runs trusted
  hooks (#96).
- secret-guard blocks an agent edit of the source path `home/private_dot_hindsight/` (#131,
  item 7). The source path does not contain `.hindsight`.
- The precedence of the env var `HINDSIGHT_AUTO_UPDATE` (#129). The build does not use it.
