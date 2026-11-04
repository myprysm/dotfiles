# opencode delta rules

`~/.claude/CLAUDE.md` is the single source of truth for how I want agents to
behave, and opencode already loads it via its Claude Code fallback (verified
2026-09-09: opencode quoted the sub-agent rule back verbatim). This file holds
**only** what does not translate from Claude Code to opencode. Do not restate
CLAUDE.md rules here — they are already in effect.

## Sub-agents

CLAUDE.md's approval gate, with its read-only lookup exception, applies to opencode's own agent
mechanism — subagents invoked via the task tool, and any agent defined under
`agent` in `opencode.json`. Present the plan and the models, wait for explicit
approval, then run. This includes agents a subagent would itself spawn.
