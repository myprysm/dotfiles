# dotfiles

Cross-machine environment setup for Linux/Mac, managed with chezmoi.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for myprysm/dotfiles (gh CLI). See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-label vocabulary (needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: root CONTEXT.md + docs/adr/. See `docs/agents/domain.md`.

### Adopting configs into the repo

Any adoption of a machine's config, package, or shell setup into this repo — full-machine
migration or a single item — follows the `/adopt` skill at `.claude/skills/adopt/SKILL.md`
(deny-list and mapping rules beside it). The repo is public: the skill's secret-safety
layers are mandatory for every write under `home/`.
