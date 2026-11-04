# opencode delta rules

`~/.claude/CLAUDE.md` is the single source of truth for how I want agents to
behave, and opencode already loads it via its Claude Code fallback. This file holds
**only** what does not translate from Claude Code to opencode. Do not restate
CLAUDE.md rules here — they are already in effect.

## Sub-agents

CLAUDE.md's approval gate covers opencode's own agent mechanism: subagents
invoked via the task tool, and any agent defined under `agent` in
`opencode.json`. Its read-only lookup exception names Claude Code agents, so no
opencode agent is exempt.
