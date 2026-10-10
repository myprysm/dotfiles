# Runbook — bump the hindsight pin

Use this to move the hindsight-coding-agents runtime to a new npm version. The hindsight pin is
`home/.chezmoidata/hindsight.yaml`: the version and the sha256 of the registry tarball. All
enrolled machines use this one pin (#129). Only the operator changes it. Bump only for a
reason, for example a bug fix or a feature. Nothing watches npm.

Do the six checks of #129 before the pin commit. Do the bump in its own PR.

Every headless probe in this runbook starts with `HINDSIGHT_DISABLE_HOOKS=1` (#135). A probe
without it recalls from and retains to `damien-main-memory` on an enrolled machine.

The commands below use these variables. Set them in one shell session:

```sh
OLD=<current version in hindsight.yaml>
NEW=<new version>
SRC=$(chezmoi source-path)
PKG=@vectorize-io/hindsight-coding-agents
WORK=$(mktemp -d)
```

---

## Step 1 — get both tarballs and the new checksum

```sh
for v in "$OLD" "$NEW"; do
  mkdir -p "$WORK/$v"
  curl -fsSL -o "$WORK/$v.tgz" "https://registry.npmjs.org/$PKG/-/hindsight-coding-agents-$v.tgz"
  tar -xzf "$WORK/$v.tgz" -C "$WORK/$v"
done
sha256sum "$WORK/$NEW.tgz"            # macOS: shasum -a 256 "$WORK/$NEW.tgz"
curl -fsSL "https://registry.npmjs.org/$PKG/$NEW" | jq -r .dist.integrity
openssl dgst -sha512 -binary "$WORK/$NEW.tgz" | base64
```

The last two lines must give the same value (without the `sha512-` prefix). If they differ,
stop. The first line is the new `sha256` of the pin. The tarball root must stay `package/`,
because the external uses `stripComponents = 1`.

Treat the extracted files as untrusted data. Do not run code from them in this step.

## Check 1 — read the release diff

The runtime holds the token and reads transcripts. Read the diff from the old pin to the new
pin:

```sh
diff -ru "$WORK/$OLD/package" "$WORK/$NEW/package" > "$WORK/release.diff"
```

Look at these items:

- The hook entry files and timeouts: `HOOK_HARNESSES` in `dist/installer.js`, the
  `claude-code` and `codex` rows. Check 3 uses them.
- The MCP entry: `mcpServerEntry` in `dist/installer.js` (command, args, env).
- Network calls and the hosts they reach.
- New environment variables and new config keys. Read the README section "Reference". The
  modify template `home/private_dot_hindsight/modify_private_coding-agent.json` sets keys by
  name, for example the five `pages` names. A renamed key stops that setting.
- Writes inside `~/.hindsight/coding-agents/`. The external is `exact = true`, so the next
  apply removes a file that the runtime writes there. In 0.8.0 only `.update-check.json`
  (when `autoUpdate` is on) and `.workspace-mcp.json` (TraeCode only) go there. If a new
  file goes there for Claude Code, codex or opencode, add a `.chezmoiignore` entry, as for
  `.oh-my-zsh/cache/*`.

## Check 2 — dry run in a scratch HOME

Do the dry run of #132 again with the new version. Compare the written files with the last
run (the tables in the #132 resolution). Do not touch the real `HOME`.

1. Make a scratch `HOME` and put the chezmoi output of the three agent configs in it, with
   the bundle on. Copy the live `~/.codex/hooks.json` (Orca hooks). chezmoi does not manage
   that file.

   ```sh
   SCR=$(mktemp -d)
   mkdir -p "$SCR/.claude" "$SCR/.codex" "$SCR/.config/opencode" "$SCR/bin"
   DATA='{"secretsDir":"/nonexistent","bundles":{"hindsight":true,"ai":true}}'
   HOME="$SCR" chezmoi execute-template --source "$SRC" --override-data "$DATA" \
     --with-stdin "$(cat "$SRC/dot_claude/modify_private_settings.json")" </dev/null > "$SCR/.claude/settings.json"
   HOME="$SCR" chezmoi execute-template --source "$SRC" --override-data "$DATA" \
     --with-stdin "$(cat "$SRC/dot_codex/modify_private_config.toml")" </dev/null > "$SCR/.codex/config.toml"
   HOME="$SCR" chezmoi execute-template --source "$SRC" --override-data "$DATA" \
     < "$SRC/dot_config/opencode/opencode.json.tmpl" > "$SCR/.config/opencode/opencode.json"
   cp ~/.codex/hooks.json "$SCR/.codex/hooks.json"
   ```

2. Put a shim in place of `claude` on `PATH`. It logs its arguments and does nothing:

   ```sh
   printf '#!/bin/sh\necho "claude $*" >> "%s/claude-shim.log"\n' "$SCR" > "$SCR/bin/claude"
   chmod +x "$SCR/bin/claude"
   ```

3. Run each install with `env -i`. Set `HOME` to the scratch directory. Do not set
   `CODEX_HOME`, `OPENCODE_CONFIG_DIR` or `CLAUDE_CONFIG_DIR`. Keep the npm cache outside the
   scratch `HOME`. Use a server address where nothing listens and a dummy token:

   ```sh
   run() {
     env -i HOME="$SCR" PATH="$SCR/bin:$(dirname "$(command -v node)"):/usr/bin:/bin" \
       npm_config_cache="$WORK/npm-cache" HINDSIGHT_DISABLE_HOOKS=1 \
       npx --yes "$PKG@$NEW" install "$1" \
       --server self-hosted --api-url http://127.0.0.1:9 --api-token dummy-not-a-secret
   }
   run claude-code
   run codex
   HOME="$SCR" chezmoi execute-template --source "$SRC" --override-data "$DATA" \
     --with-stdin "$(cat "$SRC/dot_codex/modify_private_config.toml")" \
     < "$SCR/.codex/config.toml" > "$SCR/.codex/config.toml.new" \
     && mv "$SCR/.codex/config.toml.new" "$SCR/.codex/config.toml"
   run codex
   run opencode
   ```

   The order is: claude-code, codex, a chezmoi re-render of `config.toml`, codex again,
   opencode.

4. Do a fifth run in a second scratch `HOME` with a fake legacy
   `~/.hindsight/claude-code.json` (mode 600, dummy values) and no `--server` flags. This
   tests the legacy carry-over.

5. Record each file that the installs wrote, its mode, the `hooks.state` result in
   `config.toml`, and if `python3 -c 'import tomllib,sys; tomllib.load(open(sys.argv[1],"rb"))'
   "$SCR/.codex/config.toml"` still parses. Read `$SCR/claude-shim.log`. Compare each item
   with the #132 resolution.

The dry run only finds what the installer would write. chezmoi writes the wiring on a real
machine, and the installer never runs there (#134, ADR 0003).

## Check 3 — hook commands, timeouts and codex trust

If a Claude Code or codex hook entry file or timeout changed in check 1, change
`home/.chezmoitemplates/claude-settings.json` and `home/.chezmoitemplates/codex-config.toml`
to match. The codex trust hashes then change. The modify template calculates them again, but
read the codex hook trust again (#123, claim 21):

```sh
./tests/test-codex-config.sh
```

Then ask codex itself. This needs no model call. In a scratch `HOME`:

```sh
CX=$(mktemp -d); mkdir -p "$CX/.codex" "$CX/work"
HOME="$CX" chezmoi execute-template --source "$SRC" \
  --override-data '{"bundles":{"hindsight":true}}' \
  --with-stdin "$(cat "$SRC/dot_codex/modify_private_config.toml")" </dev/null > "$CX/.codex/config.toml"
{ echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"probe","title":null,"version":"0.1.0"},"capabilities":{"experimentalApi":true}}}'
  sleep 2; echo '{"jsonrpc":"2.0","method":"initialized"}'
  sleep 1; echo "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"hooks/list\",\"params\":{\"cwds\":[\"$CX/work\"]}}"
  sleep 4; } \
  | (cd "$CX/work" && HOME="$CX" CODEX_HOME="$CX/.codex" HINDSIGHT_DISABLE_HOOKS=1 timeout 15 codex app-server 2>/dev/null) \
  | jq -c 'select(.id==2) | [.result.data[].hooks[] | {eventName, timeoutSec, trustStatus}]'
```

Each of the four hooks (`preToolUse`, `sessionStart`, `userPromptSubmit`, `stop`) must show
`trusted`. A `modified` or `untrusted` hook does not run, and `codex exec` does not prompt.

## Check 4 — no Claude Code plugin and no `modules` key

Mod admission does not apply to hindsight-coding-agents, because it installs no Claude Code
plugin (#129, #133). Make sure that this stays true:

- After check 2, `$SCR/.claude/plugins/` does not exist, and the install changed no key of
  `enabledPlugins` or `extraKnownMarketplaces` in `$SCR/.claude/settings.json`.
- The package has no Claude Code plugin manifest and no `modules` key:

  ```sh
  tar -tzf "$WORK/$NEW.tgz" | grep -F '.claude-plugin'
  for f in $(tar -tzf "$WORK/$NEW.tgz" | grep '\.json$'); do
    jq -e 'any(paths; .[-1] == "modules")' "$WORK/$NEW/$f" >/dev/null && echo "$f"
  done
  ```

  Both commands print nothing. The root `plugin.json` is for Dcode and Cline (#133). The
  secret guard refuses a recursive `grep` from an agent, so these commands list the
  tarball instead.

## Check 5 — server compatibility

Read the release notes and the README of the new version for a minimum server or API
version. Compare it with the hindsight server that talos-home runs. If the new version needs
a newer server, the bump waits for talos-home. This repo does not change the server.

## Step 2 — commit the pin

1. Set `version` and `sha256` in `home/.chezmoidata/hindsight.yaml`.
2. Run the tests:

   ```sh
   ./tests/test-hindsight-config.sh
   ./tests/test-claude-settings.sh
   ./tests/test-codex-config.sh
   ```

3. Commit: `chore(hindsight): bump hindsight pin to <NEW>`. Put the facts of checks 1 to 5
   in the commit body. Open the PR.

## Check 6 — apply on each enrolled machine

After the PR reaches `main` (#134, item 8):

1. Run `chezmoi apply` on each enrolled machine. The URL changes, so chezmoi downloads the
   new runtime. The hook commands and the trust hashes do not change, unless check 3 changed
   them.
2. Restart the open agent sessions. A running MCP server keeps the old code until its agent
   restarts.
3. Run the [checks](#checks) on each machine.

---

## Checks

Run these on each machine after the apply. The guard denies every path under
`~/.hindsight/` to an agent. **The operator runs the checks marked (operator)** in a terminal
without an agent.

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
10. **Prompt-hook latency** (operator). After a second prompt in a new session, this prints no
    credential and no prompt text:
    `jq -c 'select(.event | test("inject_recall|reflect")) | {ts, event, harness, ms}' ~/.hindsight/coding-agents-logs/diag.jsonl | tail`.
    Expect `inject_recall` entries under 7000 ms (`injectTimeoutMs`) and no `reflect_failed`.
    The automatic reflect timed out at 20 s on every session against this server (#127).
