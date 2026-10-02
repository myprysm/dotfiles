# Apply order: files first, scripts last

Every script in `home/.chezmoiscripts/` is a `run_once_after_` or `run_onchange_after_`
script. `chezmoi apply` therefore writes every file and every external first, and runs the
scripts last. Before this decision, chezmoi sorted each script as the target
`.chezmoiscripts/<name>`, which is ahead of `.claude`, `.config` and `.zshrc`. One failing
script then stopped the apply before any file was written, and the machine had no working
shell (#13, #52).

A script that fails still stops the apply. No script gets its own failure policy. This is
acceptable only because the scripts run last: when a script fails, the files are already
written, so the machine keeps a working shell and only the remaining scripts are lost.

## Consequences

- Write the attributes in this order: `run_once_after_<NN>-<name>` and
  `run_onchange_after_<NN>-<name>`. chezmoi does not parse `once_` after `after_`.
  `run_after_once_20-b.sh` renders the target `once_20-b.sh`, and the script silently loses
  its once-ness.
- `run_once_` and `run_onchange_` scripts do not form two groups. They interleave by the
  numeric prefix alone (measured on chezmoi 2.71.1). The prefix sets the order inside the
  script phase.
- A file template must not need a tool that a script installs, because every script runs
  after every file. Today no file template calls an external binary at apply time (#50).
- A file can arm a tool that is not installed yet. For example, `.gitconfig` points git at
  the gitleaks hook before the brew script installs gitleaks. If that script fails, the
  hook fails closed on the next commit.
- A rename with unchanged contents does not re-run a script. chezmoi keys `run_once_` and
  `run_onchange_` on the rendered contents, not on the name.
