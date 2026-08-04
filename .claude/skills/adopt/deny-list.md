# Deny-list — paths the adopt skill refuses to stage

Seeded from both machine inventories (§3.3) and the agent-tooling decision. Patterns are
tool-generic on purpose (redaction rule: this file is public). `~` = the inventoried user's home.

## Hard deny — never staged, in any form (plaintext, `encrypted_`, templated whole-file)

| Pattern | Class |
|---|---|
| `~/.ssh/**` (keys, `known_hosts`, `config`) | SSH — vaulted per the secrets policy, restored by `secrets-restore`, never via chezmoi |
| `~/.gnupg/**` | GPG private keyring |
| `~/.kube/**`, `~/.talos/**` | cluster credentials — also out of scope per the map |
| `~/.aws/**`, `~/.azure/**` | cloud credentials/state |
| `~/.config/gh/hosts.yml` | OAuth token (`config.yml` beside it is fine) |
| `~/.config/rclone/rclone.conf` | object-store keys — restored from vault fragments |
| `~/.mc/config.json` | S3 key pairs (minio retired; still deny) |
| `~/.docker/config.json` | registry auths + credsStore |
| `~/.config/argocd/config` | cluster names + auth tokens |
| `~/.cloudflared/**` | tunnel credentials |
| `~/.vault-token` | live token |
| `~/.secrets/**` | vault password files (legacy location — kept denied while any machine still has it) |
| the machine-local secrets directory — resolve it at runtime with `chezmoi data \| jq -r .secretsDir`, deny everything under it | vault password files; the path itself is an infrastructure identifier and is never published here |
| `~/.ansible/galaxy_token` | API token |
| `~/.devvit/token`, `~/.devvit/session-id` | session credentials |
| `~/.composer/auth.json` | registry auth |
| `~/.config/Bitwarden CLI/**`, `~/.config/op/**`, `~/.config/1Password/**` | secret-manager state |
| `~/.claude.json` | agent state incl. MCP config (can carry tokens) |
| `~/.claude/projects/**`, `~/.claude/sessions/**`, `~/.claude/plugins/**`, `~/.claude/history.jsonl`, `~/.claude/shell-snapshots/**`, `~/.claude/settings.local.json`, `~/.claude/*.bak`, `~/.claude/{daemon,cache,debug}*/**` | per-machine agent state (only `CLAUDE.md`, `settings.json`, `statusline.sh`, hand-written skills migrate) |
| `~/.agents/**` except `~/.agents/.skill-lock.json` | skills-CLI-managed tree; only the lockfile migrates |
| `~/.copilot/`, `~/.codex/`, `~/.gemini/`, `~/.cline/`, `~/.ai/`, `~/.cagent/`, `~/.codemod/`, `~/.openclaw/`, `~/.hindsight/` | agent-tool state, self-managed |
| `$HOME/*.env*`, `backup-*.env.*`, filenames containing `credential`/`token`/`secret` | loose secret artifacts — route to the vault, never the repo |
| `**/.*_history`, `**/*_history`, `~/.lesshst`, `~/.viminfo`, `~/.local/share/mcfly/**`, `~/Library/Application Support/McFly/**` | typed-input stores — whatever a tool saved of what was typed or yanked. A shell history is every credential ever typed at a prompt; a vim register is whatever was yanked out of a file these rules protect. `.chezmoiignore` refuses `chezmoi add` on these, but it says nothing about a hand-write into `home/`, which is what this row denies. A history *database* (McFly's `history.db`, atuin's) has no naming convention and is denied by directory: a new one needs a new entry, on both lists |
| `~/.hermes/**`, `~/.qbit/**`, `~/.config/spacetime/cli.toml` | tool state, possibly token-bearing |
| project-specific config dirs holding API keys or env values | identified during inventory, deny by content class |

## Review-first — may be adopted, only after the full strip-and-review pass

| Pattern | Watch for |
|---|---|
| `~/.npmrc` | registry auth lines |
| `~/.claude/settings.json` | permission allowlists carrying internal hostnames (redaction rule) |
| `~/.claude/CLAUDE.md` | internal paths or names |
| `~/.gitconfig` | `signingkey` → leave it in `~/.gitconfig.local`, never adopt it (per-machine key, secrets policy rule 5); also `core.sshCommand`, `includeIf` work-tree blocks, `safe.directory` |
| any shell rc or alias file | inline credentials, internal URLs, work-specific values |
