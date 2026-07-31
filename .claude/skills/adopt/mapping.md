# Mapping rules — inventory finding → repo destination

Deterministic mapping onto this repo's layout (`.chezmoiroot` = `home/`). Never invent a new
top-level location; a finding with no row here is `report`, not improvisation.

## Shell content → drop-in dirs

`~/.zshrc` stays the tracked 20-line skeleton. Its content maps out:

| Finding | Destination |
|---|---|
| env export, PATH entry | `home/dot_config/zsh/env.d/NN-<topic>.zsh` |
| alias | `home/dot_config/zsh/aliases.d/NN-<topic>.zsh` |
| completion file / fpath entry | `home/dot_config/zsh/completions.d/` |
| tool hook (`eval "$(starship init zsh)"`, direnv, mcfly, …) | `home/dot_config/zsh/rc.d/NN-<tool>.zsh` |
| shell function | `home/dot_config/zsh/rc.d/` (or completions.d if a completer) |
| omz plugin change | per-OS list in `home/.chezmoidata/zsh.yaml`; machine-one-off → `zshPluginsExtra` in the machine-local chezmoi config |
| machine-specific one-off | untracked `~/.zshrc.local` — not in the repo at all |
| bash alias/function (foreign setup) | same drop-in dirs, after zsh syntax check |

`NN` = two-digit ordering prefix; kebab-case names.

## Tool configs

| Finding | Destination |
|---|---|
| config under `~/.config/<tool>/` | `home/dot_config/<tool>/` (`chezmoi add`) |
| tool that reads `~/Library/...` on macOS but `~/.config` on Linux | single source in `home/.chezmoitemplates/<tool>`, two per-OS targets (k9s precedent) |
| single-value OS variance in a file | one `.tmpl` with a `.chezmoi.os` conditional |
| whole-file OS variance | per-OS files + templated `.chezmoiignore` — no runtime guards |
| per-machine drift (agent settings, …) | untracked `*.local` twin (`settings.local.json` pattern) |

## Packages

All package intent lives in `home/.chezmoidata/packages.yaml`; the `run_onchange_` scripts react to edits.

| Finding | Destination |
|---|---|
| brew formula | `core.brews`, an existing bundle, or per-OS list — match the tool's theme |
| cask | `core.darwin.casks` |
| apt package | the matching `apt` list |
| go binary | `bundles.go.tools` as a module path (`@latest` unless pinned) |
| krew plugin / helm repo / SDKMAN candidate | matching bundle key |
| npm global | `home/dot_nvm/default-packages` (corepack model) — or drop it |
| pinned-release binary (no formula) | dedicated `run_once_` script (kubeone precedent) |

## Secrets inside otherwise-adoptable configs

| Finding | Destination |
|---|---|
| secret value inline in a config | file becomes a `.tmpl`; value rendered via `{{ template "secret" (dict "domain" "<personal\|work>" "ref" "<consumer>-<artifact>" "field" "value") }}`; ref registered in `home/.chezmoidata/secrets.yaml` |
| whole secret-bearing file | not adopted — vault + `secrets-restore` path (secrets policy) |

Repo-visible refs follow the naming convention: kebab-case `<consumer>-<artifact>`, no domain
suffix, no infrastructure identifiers.
