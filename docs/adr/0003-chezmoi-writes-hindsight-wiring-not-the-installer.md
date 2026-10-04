# chezmoi writes the hindsight wiring, not the upstream installer

Upstream connects Claude Code, codex and opencode to hindsight with the
`@vectorize-io/hindsight-coding-agents` installer. This repo does not run that installer on a
real machine. chezmoi stages the runtime from a pinned npm tarball (an external) and writes
the hindsight wiring through the files that it already owns: the hooks in
`~/.claude/settings.json` through one wrapper, the hooks and MCP keys in `~/.codex/config.toml`
with seeded trust, the `plugin` entry in `opencode.json`, and a script that runs
`claude mcp add` (#134). The dry run (#132) found four installer failures, and each one is in
a file that chezmoi owns. The installer runs only in the dry run of a hindsight bump (#129).

## Considered Options

- **The installer writes, chezmoi repairs**: rejected. Each install needs a repair. A second
  codex install writes `[mcp_servers.hindsight]` two times into a chezmoi-indented
  `config.toml`, and then `chezmoi apply` stops. The installer ignores `CODEX_HOME` and
  `OPENCODE_CONFIG_DIR`.
- **The installer stages the runtime and registers the Claude MCP, chezmoi writes the rest**:
  rejected. Two writers for one runtime.
- **codex hooks in `hooks.json`**: rejected. Orca writes that file, and the installer gives
  the new hooks no trust entry.

## Consequences

- No agent gets the bundled `hindsight-coding-agent` skill. It describes per-repo banks and
  seeding, which #127 turned off.
- chezmoi writes no `.install-origin.json`, so the runtime never updates itself.
- A hindsight bump must compare the files that the new installer writes with the chezmoi
  wiring, because upstream can change a hook entry point or a timeout (#129, check 2).
