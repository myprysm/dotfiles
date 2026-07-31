# chezmoi Best Practices (verified against primary sources, 2026-07-31)

All claims cite the owning primary source: chezmoi.io official docs, the twpayne/chezmoi GitHub repo, docs.brew.sh, and bitwarden.com/help. Where a doc did not state something, that is said explicitly.

---

## 1. Source repo layout conventions

### Source-state attributes (prefixes and suffixes)

chezmoi encodes target-file metadata in source file names. Prefixes, in their required order, per the official reference (https://www.chezmoi.io/reference/source-state-attributes/):

| Prefix | Meaning (quoted from docs) |
|---|---|
| `after_` | "Run script after updating the destination" |
| `before_` | "Run script before updating the destination" |
| `create_` | "Ensure that the file exists, and create it with contents if it does not" |
| `dot_` | "Rename to use a leading dot, e.g. `dot_foo` becomes `.foo`" |
| `empty_` | "Ensure the file exists, even if is empty. By default, empty files are removed" |
| `encrypted_` | "Encrypt the file in the source state" |
| `external_` | "Ignore attributes in child entries" |
| `exact_` | "Remove anything not managed by chezmoi" (directories) |
| `executable_` | "Add executable permissions to the target file" |
| `literal_` | "Stop parsing prefix attributes" |
| `modify_` | "Treat the contents as a script that modifies an existing file" |
| `once_` | "Only run the script if its contents have not been run successfully before" |
| `onchange_` | "Only run the script if its contents have not been run successfully before with the same filename" |
| `private_` | "Remove all group and world permissions from the target file or directory" |
| `readonly_` | "Remove all write permissions from the target file or directory" |
| `remove_` | "Remove the file or symlink if it exists or the directory if it is empty" |
| `run_` | "Treat the contents as a script to run" |
| `symlink_` | "Create a symlink instead of a regular file" |

Suffixes: `.tmpl` = "Treat the contents of the source file as a template"; `.literal` = "Stop parsing suffix attributes". The `literal_` prefix and `.literal` suffix "can appear anywhere and stop attribute parsing", for filenames that collide with attribute names.
Source: https://www.chezmoi.io/reference/source-state-attributes/

Examples of the mapping:

```
dot_zshrc.tmpl                  -> ~/.zshrc              (templated)
private_dot_ssh/config          -> ~/.ssh/config         (dir mode 0700-ish: group/world perms stripped)
executable_dot_local/bin/foo    -> ~/.local/bin/foo      (chmod +x)
symlink_dot_vimrc               -> ~/.vimrc is a symlink; source file contains the link target
exact_dot_config/nvim/          -> ~/.config/nvim, extra unmanaged files inside get deleted on apply
```

### Special files and processing order

Special files, evaluated in order (https://www.chezmoi.io/reference/special-files/):

1. `.chezmoiroot` — read first; redirects the source-state root.
2. `.chezmoi.$FORMAT.tmpl` — used by `chezmoi init` to generate/update the config file; applied before the rest (works with `--init`, e.g. `chezmoi apply --init`).
3. `.chezmoidata.$FORMAT` files / `.chezmoidata/` directory — data read before template processing.
4. `.chezmoitemplates/` — shared templates usable via `{{ template "name" . }}`.
5. `.chezmoiignore` — ignore rules.
6. `.chezmoiremove` — files to remove on apply.
7. `.chezmoiexternal.$FORMAT` / `.chezmoiexternals/` — externals, read in lexical order.
8. `.chezmoiversion` — minimum required chezmoi version.

**`.chezmoiroot`**: "If a file called `.chezmoiroot` exists in the root of the source directory then the source state is read from the directory specified in `.chezmoiroot` interpreted as a relative path to the source directory." Use it to keep the repo root clean (README, CI, docs at top level; dotfiles under e.g. `home/`). The docs warn that special files like `.chezmoi.$FORMAT.tmpl` must move into the new root too.
Source: https://www.chezmoi.io/reference/special-files/chezmoiroot/

```
repo/
├── .chezmoiroot        # contains the single line: home
├── home/               # actual chezmoi source state
│   ├── .chezmoi.toml.tmpl
│   └── dot_zshrc.tmpl
├── README.md
└── .github/
```

**`.chezmoiignore`** (https://www.chezmoi.io/reference/special-files/chezmoiignore/):
- "Patterns are matched using `doublestar.Match` and match against the target path, not the source path."
- "Patterns can be excluded by prefixing them with a `!` character. All excludes take priority over all includes."
- "`.chezmoiignore` is interpreted as a template, whether or not it has a `.tmpl` extension. This allows different files to be ignored on different machines."
- "`.chezmoiignore` files in source state subdirectories apply only to that subdirectory."
- Comments start with `#` (mid-line `#` must be preceded by whitespace).

### Modular shell config layout

The source tree mirrors the target tree, with per-component attributes (source: attribute semantics above, https://www.chezmoi.io/reference/source-state-attributes/). A common modular layout:

```
dot_config/                 -> ~/.config/
  zsh/
    ...
dot_zshrc.tmpl              -> ~/.zshrc (thin loader)
dot_zshrc.d/                -> ~/.zshrc.d/ (one file per concern)
  10-aliases.zsh
  20-path.zsh.tmpl
  30-work.zsh.tmpl
```

with `~/.zshrc` sourcing every file in `~/.zshrc.d/`. Note: the split-directory pattern itself is a community convention; what the official docs provide is the `dot_` mapping, per-file templating, and `exact_` to keep such a directory free of strays. Scripts can live in `.chezmoiscripts/`, whose contents "execute as normal scripts without creating corresponding target directories" (https://www.chezmoi.io/user-guide/use-scripts-to-perform-actions/).

---

## 2. Per-OS / per-machine templating

Primary source for this whole section: https://www.chezmoi.io/user-guide/manage-machine-to-machine-differences/ plus the variables reference https://www.chezmoi.io/reference/templates/variables/.

### `.tmpl` files and OS branching

Files with the `.tmpl` suffix are rendered with Go `text/template`. OS branch (verbatim pattern from the user guide):

```
{{- if eq .chezmoi.os "darwin" }}
# macOS configuration
{{- else if eq .chezmoi.os "linux" }}
# Linux configuration
{{- end -}}
```

Reference variables (quoted from https://www.chezmoi.io/reference/templates/variables/):
- `.chezmoi.os` — "Operating system, e.g. `darwin`, `linux`, etc. as returned by runtime.GOOS"
- `.chezmoi.arch` — "Architecture, e.g. `amd64`, `arm`, etc. as returned by runtime.GOARCH"
- `.chezmoi.hostname` — "The hostname of the machine chezmoi is running on, up to the first `.`"
- `.chezmoi.fqdnHostname` — "The fully-qualified domain name hostname of the machine chezmoi is running on"
- `.chezmoi.osRelease` — "The information from `/etc/os-release`, Linux only, run `chezmoi data` to see its output"

### Distro detection

The Linux machine guide shows combining OS + distro into one value using `.chezmoi.osRelease.id` (i.e. the `ID=` field of `/etc/os-release`, exposed lowercase):

```
{{ .chezmoi.os }}-{{ .chezmoi.osRelease.id }}   # e.g. "linux-debian", "linux-fedora"
```

Source: https://www.chezmoi.io/user-guide/machines/linux/. The variables reference does not document a key-renaming rule for `osRelease`; the docs' own advice is "run `chezmoi data` to see its output" (https://www.chezmoi.io/reference/templates/variables/).

### Hostname branching

```
{{- if eq .chezmoi.hostname "work-laptop" }}
# work-laptop only configuration
{{- end }}
```

Source: https://www.chezmoi.io/user-guide/manage-machine-to-machine-differences/

### Whole-file inclusion/exclusion via templated `.chezmoiignore`

Since `.chezmoiignore` is always a template, exclude whole files per OS instead of littering a file with `if` blocks. Logic is inverted ("ignore unless"), because chezmoi applies everything by default:

```
{{- if ne .chezmoi.os "darwin" }}
Library/Application Support/App/file.conf
{{- end }}
```

Sources: https://www.chezmoi.io/user-guide/manage-machine-to-machine-differences/ and https://www.chezmoi.io/reference/special-files/chezmoiignore/ (which also shows a data-driven example: `{{- if ne .email "firstname.lastname@company.com" }} .company-directory {{- end }}`).

### `.chezmoidata` — static shared data

- Formats: "chezmoi supports multiple file `$FORMAT`s for configuration and data: JSON, JSONC, TOML, and YAML" — as `.chezmoidata.$FORMAT` files or a `.chezmoidata/` directory.
- Read before template execution; ".chezmoidata.$FORMAT files cannot be templates because they must be present prior to the start of the template engine."
- Multiple files "all merge to the root of the data dictionary and they are read in lexical (alphabetic) filesystem order"; "Only dictionaries are merged; all other values (in particular lists) are replaced" (later files win).

Source: https://www.chezmoi.io/reference/special-files/chezmoidata-format/

### `.chezmoi.toml.tmpl` — per-machine config with prompts

`chezmoi init` renders `.chezmoi.$FORMAT.tmpl` into the machine-local config file (https://www.chezmoi.io/reference/special-files/). Init-only prompt functions (https://www.chezmoi.io/reference/templates/init-functions/): `promptBool`/`promptBoolOnce`, `promptChoice`/`promptChoiceOnce`, `promptInt`/`promptIntOnce`, `promptString`/`promptStringOnce`, `promptMultichoice`/`promptMultichoiceOnce`, plus `exit` and `writeToStdout`. They exist only during `chezmoi init` (or `chezmoi execute-template --init`).

`promptStringOnce` signature: `promptStringOnce map path prompt [default]` — "returns the value of map at path if it exists and is a string value, otherwise it prompts the user" (so re-running `init` does not re-ask).
Source: https://www.chezmoi.io/reference/templates/init-functions/promptStringOnce/

Example `.chezmoi.toml.tmpl` (email prompt is verbatim from the docs):

```
{{ $email := promptStringOnce . "email" "What is your email address" -}}
[data]
    email = {{ $email | quote }}
```

Machine-specific variables can also just be written by hand into the local config's `[data]` section, e.g. `~/.config/chezmoi/chezmoi.toml`:

```toml
[data]
    email = "me@home.org"
```

Source: https://www.chezmoi.io/user-guide/manage-machine-to-machine-differences/

### Shared template fragments

Put common content in `.chezmoitemplates/file.conf` and reference with `{{- template "file.conf" . -}}` from OS-specific files.
Source: https://www.chezmoi.io/user-guide/manage-machine-to-machine-differences/

---

## 3. Package installation with scripts

Primary source: https://www.chezmoi.io/user-guide/use-scripts-to-perform-actions/

### Script semantics

- `run_` scripts run on every `chezmoi apply`.
- `run_once_` scripts run once per unique content: chezmoi tracks the SHA256 hash of the script contents in its state database and will not re-run unless the contents change — even if the filename changes.
- `run_onchange_` scripts re-run whenever their contents differ from the last successful run. For `.tmpl` scripts, the hash is computed after template rendering — this is what makes the hash-comment trick work.
- Scripts should be idempotent; they run in alphabetical order; `before_` runs before the destination is updated, `after_` after (e.g. `run_once_before_install-password-manager.sh`).
- Scripts need a `#!` shebang (or be binary); the executable bit in the source is unnecessary; an empty/whitespace-only rendered template is skipped (dynamic disable).
- Reset state: `chezmoi state delete-bucket --bucket=entryState` (onchange) / `--bucket=scriptState` (once).

### Hash-in-comment trick (re-run on data change)

Verbatim pattern from the docs (dconf example) — embed a hash of another file in a comment so the rendered script content, and thus its hash, changes when the data changes:

```bash
#!/bin/bash
# dconf.ini hash: {{ include "dconf.ini" | sha256sum }}
dconf load / < {{ joinPath .chezmoi.sourceDir "dconf.ini" | quote }}
```

Source: https://www.chezmoi.io/user-guide/use-scripts-to-perform-actions/

### `brew bundle` from a chezmoi-generated Brewfile

The official macOS guide's pattern — `run_onchange_darwin-install-packages.sh.tmpl` feeding `brew bundle` an inline Brewfile via `--file=/dev/stdin`:

```
{{- if eq .chezmoi.os "darwin" -}}
#!/bin/bash

brew bundle --file=/dev/stdin <<EOF
brew "git"
cask "google-chrome"
EOF
{{ end -}}
```

Source: https://www.chezmoi.io/user-guide/machines/macos/. The docs' snippet hardcodes packages; combining it with `.chezmoidata` (section 2) lets you generate the lines with a `range` loop, e.g. `.chezmoidata/packages.yaml` + `{{ range .packages.darwin.brews }}brew {{ . | quote }}{{ "\n" }}{{ end }}` — the loop itself is an application of documented templating, not a verbatim doc example. Because the loop output is part of the script body, any package-list change changes the rendered content and re-triggers the `run_onchange_` script (script-hash semantics above).

### apt fallback for Ubuntu/Debian

Verbatim multi-OS script from the scripts guide:

```
{{ if eq .chezmoi.os "linux" -}}
#!/bin/sh
sudo apt install ripgrep
{{ else if eq .chezmoi.os "darwin" -}}
#!/bin/sh
brew install ripgrep
{{ end -}}
```

Source: https://www.chezmoi.io/user-guide/use-scripts-to-perform-actions/. For distro precision, branch on `.chezmoi.osRelease.id` (section 2).

### `scriptEnv` and script environment

- `scriptEnv` (top-level config): "Extra environment variables for scripts, hooks, and commands." Source: https://www.chezmoi.io/reference/configuration-file/variables/
- chezmoi also sets `CHEZMOI=1`, `CHEZMOI_OS`, `CHEZMOI_ARCH` and other template data as env vars during script execution. Source: https://www.chezmoi.io/user-guide/use-scripts-to-perform-actions/

```toml
[scriptEnv]
    MY_VAR = "my_value"
```

### Homebrew on Linux (linuxbrew)

From official Homebrew docs (https://docs.brew.sh/Homebrew-on-Linux):
- Default prefix: `/home/linuxbrew/.linuxbrew` (sudo used during install only; "Homebrew does not use sudo after installation").
- Debian/Ubuntu prerequisites: `sudo apt-get install build-essential procps curl file git`.
- PATH setup: `eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"` appended to `~/.bashrc` / `~/.zshrc`.

From https://docs.brew.sh/Support-Tiers: Tier 1 Linux = "ARM64/AArch64 or Intel x86_64 with SSSE3 support", "system `glibc` version ≥ 2.39", "Linux kernel version ≥ 3.2", default prefix, Ubuntu in standard support window. glibc 2.13–2.38 drops to Tier 2 ("Homebrew's own glibc formula will be installed automatically"), as does a non-default prefix.

---

## 4. One-liner bootstrap

Primary source: https://www.chezmoi.io/install/

### Install one-liners (verbatim)

```sh
# binary only, into ./bin
sh -c "$(curl -fsLS https://get.chezmoi.io)"
sh -c "$(wget -qO- https://get.chezmoi.io)"          # wget variant

# into ~/.local/bin
sh -c "$(curl -fsLS get.chezmoi.io/lb)"               # /lb == install to ~/.local/bin
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b $HOME/.local/bin   # explicit -b DIR

# install + init + apply from GitHub in one shot
sh -c "$(curl -fsLS https://get.chezmoi.io)" -- init --apply $GITHUB_USERNAME
sh -c "$(curl -fsLS https://get.chezmoi.io)" -- init --apply git@github.com:$GITHUB_USERNAME/dotfiles.git  # private via SSH
```

Requirements of the get.chezmoi.io script on a naked system: `sh` plus either `curl` or `wget`. Default install dir is `./bin`; `get.chezmoi.io/lb` (or `chezmoi.io/getlb`) targets `.local/bin`. Source: https://www.chezmoi.io/install/

### `chezmoi init` repo expansion

`chezmoi init user` expands `user` to HTTPS `https://user@github.com/user/dotfiles.git` (SSH form `git@github.com:user/dotfiles.git`) — the repo name defaults to `dotfiles`. Flags: `--apply` = "Run `chezmoi apply` after checking out the repo and creating the config file"; `--depth` = shallow clone depth.
Source: https://www.chezmoi.io/reference/commands/init/

### `--one-shot`

Quoted: `--one-shot` "is the equivalent of `--apply`, `--depth=1`, `--force`, `--purge`, and `--purge-binary`. It attempts to install your dotfiles with chezmoi and then remove all traces of chezmoi from the system. This is useful for setting up temporary environments (e.g. Docker containers)."
Source: https://www.chezmoi.io/reference/commands/init/

### Is git required?

chezmoi has a builtin git. Config setting `useBuiltinGit`, default `auto`: "Use builtin git if `git` command is not found in `$PATH`." So `chezmoi init` can clone a dotfiles repo on a machine with no git installed.
Source: https://www.chezmoi.io/reference/configuration-file/variables/ (note: the install page's prerequisites table mentions git for `init --apply`, but the builtin-git fallback is the documented behavior when `git` is absent from `$PATH`).

### Naked-machine prerequisites in practice

- **Ubuntu (minimal/container images)**: the bootstrap needs `sh` + `curl` or `wget` (https://www.chezmoi.io/install/); if neither is present, `apt-get update && apt-get install -y curl` first. I could not verify from a primary source which of curl/wget ships preinstalled on any given Ubuntu flavor — check the target image.
- **macOS**: chezmoi's install one-liner only needs curl/wget + sh (same source); with builtin git (`useBuiltinGit` = `auto`, above), installing Xcode Command Line Tools is not required just to `init --apply` over HTTPS.

---

## 5. Secrets: source-agnostic patterns (Bitwarden, 1Password, HashiCorp Vault); public-repo hygiene

chezmoi is secret-source agnostic: each supported password manager is exposed as a set of template functions that shell out to that manager's CLI at render time. Bitwarden is treated below as the personal default; 1Password and Vault are covered for professional contexts, plus patterns for not hard-wiring one backend into templates.

Primary sources: https://www.chezmoi.io/user-guide/password-managers/bitwarden/ , https://www.chezmoi.io/user-guide/password-managers/1password/ , https://www.chezmoi.io/user-guide/password-managers/vault/ , https://www.chezmoi.io/reference/templates/bitwarden-functions/ , https://bitwarden.com/help/cli/

### Session requirement (`bw login` / `bw unlock` / `BW_SESSION`)

- Bitwarden CLI: `bw login` authenticates (email/password login also returns a session key); `bw unlock` generates a session key after API-key/SSO auth. "With the BW_SESSION environment variable set, `bw` commands will reference that variable"; alternatively pass `--session` per command. Source: https://bitwarden.com/help/cli/
- chezmoi's guide (quoted): "API key and SSO logins always require an explicit unlock step", and gives `export BW_SESSION=$(bw unlock --raw)` (already logged in), `export BW_SESSION=$(bw login $BITWARDEN_EMAIL --raw)`, and `export BW_SESSION=$(bw login --sso && bw unlock --raw)`.
- Convenience: "If you set the `bitwarden.unlock` configuration variable to `auto` in your config file, chezmoi will automatically call `bw unlock`" when the session variable is unset. Source: https://www.chezmoi.io/user-guide/password-managers/bitwarden/

### Template functions (examples verbatim from chezmoi docs)

```
{{ (bitwarden "item" "example.com").login.username }}
{{ (bitwardenFields "item" "example.com").token.value }}
{{ bitwardenAttachment "id_rsa" "bf22e4b4-ae4a-4d1c-8c98-ac620004b628" }}
{{ bitwardenAttachmentByRef "id_rsa" "item" "example.com" }}
{{ (bitwardenSecrets "be8e0ad8-d545-4017-a55a-b02f014d4158" .accessToken).value }}   # Bitwarden Secrets Manager (bws)
```

Source: https://www.chezmoi.io/user-guide/password-managers/bitwarden/ (reference pages under https://www.chezmoi.io/reference/templates/bitwarden-functions/).

### `rbw` alternative

chezmoi has an `rbw` template function: the name "is passed to `rbw get --raw`" and output parsed as JSON, with caching per identical invocation. Examples from the reference:

```
username = {{ (rbw "test-entry").data.username }}
password = {{ (rbw "test-entry" "--folder" "my-folder").data.password }}
```

Source: https://www.chezmoi.io/reference/templates/bitwarden-functions/rbw/

### 1Password (`op` CLI v2)

Source: https://www.chezmoi.io/user-guide/password-managers/1password/

Template functions:

- `onepassword` — structured data parsed from `op item get $UUID --format json`.
- `onepasswordRead` — "The output of `op read $URL` is available as the `onepasswordRead` template function":

  ```
  {{ onepasswordRead "op://app-prod/db/password" }}
  ```
- `onepasswordDetailsFields` — restructures item output so fields are looked up by key name instead of array index.
- `onepasswordItemFields` — accesses additional custom fields (not all 1Password item types support this).
- `onepasswordDocument` — retrieves a document's contents by UUID: `onepasswordDocument "$UUID"`.

Account/session handling (quoted): "Log in and get a session using: `op account add --address $SUBDOMAIN.1password.com --email $EMAIL` … `eval $(op signin --account $SUBDOMAIN)`". Biometric unlock via the desktop app bypasses the explicit signin; chezmoi validates the session and re-prompts interactively when expired. The `onepassword.prompt` setting controls this sign-in prompting; the docs warn that with `prompt = false` legacy behavior, interactive session tokens can be visible in process listings on shared systems.

`onepassword.mode` config selects how chezmoi talks to 1Password:

| Mode | Use | Restrictions |
|---|---|---|
| `account` (default) | desktop/CLI account | none |
| `connect` | 1Password Connect server | no `onepasswordDocument`; no account parameters |
| `service` | service account token | no account parameters |

```toml
[onepassword]
    mode = "connect"
```

### HashiCorp Vault (`vault` CLI)

Source: https://www.chezmoi.io/user-guide/password-managers/vault/

- Prerequisite (quoted): "The vault CLI needs to be correctly configured on your machine, e.g. the `VAULT_ADDR` and `VAULT_TOKEN` environment variables must be set correctly." Verify with `vault kv get -format=json $KEY`.
- Function (quoted): "The structured data from `vault kv get -format=json` is available as the `vault` template function." KV v2 nests data twice:

  ```
  {{ (vault "$KEY").data.data.password }}
  ```

**Multiple Vault instances**: the chezmoi docs do not document multi-instance targeting for the `vault` function (it inherits whatever `VAULT_ADDR`/`VAULT_TOKEN` are in the environment). Two patterns built from documented primitives:

1. Per-context environment: set `VAULT_ADDR` per machine/shell before running chezmoi (the function just runs the CLI in your environment — same source as above).
2. Explicit address via the generic `output` function plus `fromJson`:

   ```
   {{ $db := output "vault" "kv" "get" "-format=json" (printf "-address=%s" .vaultAddr) "secret/db" | fromJson }}
   {{ ($db).data.data.password }}
   ```

   `output` "returns the output of executing the command name with args"; "If executing the command returns an error then template execution exits with an error. The execution occurs every time that the template is executed" (no caching), and "It is the user's responsibility to ensure that executing the command is both idempotent and fast." Source: https://www.chezmoi.io/reference/templates/functions/output/ (`fromJson`: https://www.chezmoi.io/reference/templates/functions/fromJson/). The snippet is an application of these documented functions, not a verbatim doc example.

### Abstracting the secret source (no hard-wired backend)

Documented primitives that compose into a backend-agnostic layer:

- **Backend selector as per-machine data**: init functions include `promptChoice`/`promptChoiceOnce` (https://www.chezmoi.io/reference/templates/init-functions/), so `.chezmoi.toml.tmpl` can set a data key once per machine:

  ```
  {{ $backend := promptChoiceOnce . "secretBackend" "Secret backend" (list "bitwarden" "onepassword" "vault") -}}
  [data]
      secretBackend = {{ $backend | quote }}
  ```

- **Wrapper template in `.chezmoitemplates/`**: shared templates are stored in `.chezmoitemplates/` and invoked with `{{ template "name" . }}` (https://www.chezmoi.io/user-guide/manage-machine-to-machine-differences/, https://www.chezmoi.io/reference/special-files/). Since "All standard `text/template` and text template functions from `sprig` are included" (https://www.chezmoi.io/reference/templates/functions/), sprig's `dict` can pass arguments. Example composition (not a verbatim doc example) — `.chezmoitemplates/getSecret`:

  ```
  {{- if eq .backend "onepassword" -}}
  {{- onepasswordRead (printf "op://%s/%s" .vault .ref) -}}
  {{- else if eq .backend "vault" -}}
  {{- (vault .ref).data.data.value -}}
  {{- else -}}
  {{- (bitwardenFields "item" .ref).value.value -}}
  {{- end -}}
  ```

  used from any `.tmpl` file as:

  ```
  token = {{ template "getSecret" (dict "backend" .secretBackend "vault" "app-prod" "ref" "db-password") }}
  ```

- **Escape hatch**: any CLI not natively supported works through `output` (semantics quoted above).

There is no chezmoi mechanism for user-defined Go template *functions*; named templates + `output` are the documented extension points (function list: https://www.chezmoi.io/reference/templates/functions/).

### Fresh-machine CLI prerequisites and bootstrap ordering

Per-CLI install channels (primary vendor docs):

- **`bw` (Bitwarden)**: native executables for Windows/macOS/Linux x64; `npm install -g @bitwarden/cli` (recommended for arm64); Chocolatey/Snap/Flatpak. Source: https://bitwarden.com/help/cli/
- **`op` (1Password)**: macOS `brew install 1password-cli`; Debian/Ubuntu via 1Password apt repo then `sudo apt update && sudo apt install 1password-cli`; `winget install 1password-cli`; Alpine `apk add 1password-cli`; direct binary download. Biometric/desktop integration: 1Password app → Settings → Developer → "Integrate with 1Password CLI". Source: https://www.1password.dev/cli/get-started/ (redirect target of developer.1password.com/docs/cli/get-started/)
- **`vault`**: macOS `brew tap hashicorp/tap && brew install hashicorp/tap/vault`; Debian/Ubuntu via HashiCorp apt repo (`wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg` … `sudo apt update && sudo apt install vault`); binaries at releases.hashicorp.com. Source: https://developer.hashicorp.com/vault/install
- **`rbw`**: third-party Rust client, linked from the chezmoi Bitwarden guide (https://www.chezmoi.io/user-guide/password-managers/bitwarden/ → https://github.com/doy/rbw).

**Ordering problem**: with `sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply $USER`, templates that call secret functions render during that first apply — the secret manager CLI must already be installed *and* authenticated, or rendering fails. Documented mitigations:

1. **`run_once_before_` script**: the scripts guide's own example name is `run_once_before_install-password-manager.sh`, which "runs before updates" (https://www.chezmoi.io/user-guide/use-scripts-to-perform-actions/).
2. **`read-source-state` pre hook**: hooks (`hooks.EVENT.pre`/`.post` in the config file) run around events including `read-source-state`, i.e. before chezmoi reads/renders the source state, and "hooks are always run, even if `--dry-run` is specified" — the earliest documented place to install a CLI (https://www.chezmoi.io/reference/configuration-file/hooks/).
3. **Two-step init**: run `chezmoi init $USER` *without* `--apply` (`--apply` is opt-in: "Run `chezmoi apply` after checking out the repo and creating the config file", https://www.chezmoi.io/reference/commands/init/), then install/auth the CLI (`bw login` + `export BW_SESSION=...`, `eval $(op signin ...)`, `export VAULT_ADDR=... VAULT_TOKEN=...`), then `chezmoi apply`. Simplest and most robust on a naked machine.

### Public-repo hygiene

- **Never commit plaintext secrets or private keys.** With password-manager template functions, the repo contains only the template reference (e.g. `{{ (bitwarden "item" "example.com").login.password }}`), and the secret is fetched at render time (https://www.chezmoi.io/user-guide/password-managers/bitwarden/).
- **`private_` affects permissions only, not secrecy**: it means "Remove all group and world permissions from the target file or directory" — the source file in your repo is still plaintext (https://www.chezmoi.io/reference/source-state-attributes/).
- **Encryption alternative**: chezmoi supports age, gpg (plus git-crypt and transcrypt); `encrypted_`-prefixed files are stored "ASCII-armored" in the source and decrypted transparently (`chezmoi edit` decrypts/re-encrypts). Add with `chezmoi add --encrypt ~/.ssh/id_rsa`. Source: https://www.chezmoi.io/user-guide/encryption/
- **Machine-local untracked data**: the config file lives at `$HOME/.config/chezmoi/chezmoi.$FORMAT` (TOML/JSON/JSONC/YAML) — it is per-machine, outside the source repo, so per-machine `[data]` values (and secrets config) never enter git; it is (re)generated from `.chezmoi.$FORMAT.tmpl` by `chezmoi init`. Sources: https://www.chezmoi.io/reference/configuration-file/ , https://www.chezmoi.io/reference/special-files/
- **Machine-local override files** (e.g. a `~/.zshrc.local` your `.zshrc` sources): chezmoi only touches files it manages — unmanaged files are left alone unless inside an `exact_` directory, which "Remove[s] anything not managed by chezmoi" (https://www.chezmoi.io/reference/source-state-attributes/). So keep local override files out of `exact_` dirs, or list machine-only paths in templated `.chezmoiignore` (https://www.chezmoi.io/reference/special-files/chezmoiignore/).

---

## 6. Managing oh-my-zsh (externals, pitfalls)

Primary source: https://www.chezmoi.io/user-guide/include-files-from-elsewhere/ (reference: https://www.chezmoi.io/reference/special-files/chezmoiexternal-format/)

### Official `.chezmoiexternal.toml` example (archive type)

Verbatim from the user guide:

```toml
[".oh-my-zsh"]
    type = "archive"
    url = "https://github.com/ohmyzsh/ohmyzsh/archive/master.tar.gz"
    exact = true
    stripComponents = 1
    refreshPeriod = "168h"

[".oh-my-zsh/custom/plugins/zsh-syntax-highlighting"]
    type = "archive"
    url = "https://github.com/zsh-users/zsh-syntax-highlighting/archive/master.tar.gz"
    exact = true
    stripComponents = 1
    refreshPeriod = "168h"

[".oh-my-zsh/custom/themes/powerlevel10k"]
    type = "archive"
    url = "https://github.com/romkatv/powerlevel10k/archive/v1.15.0.tar.gz"
    exact = true
    stripComponents = 1
```

Notes from the same page: pinned-tag URLs (powerlevel10k) omit `refreshPeriod`; use `include` patterns to limit imported files for performance, e.g. `include = ["*/*.zsh", "*/.version", "*/.revision-hash", "*/highlighters/**"]`.

### `refreshPeriod` and `exact` semantics

- `refreshPeriod`: "The default is zero meaning that chezmoi will never re-download unless forced." Force with `-R`/`--refresh-externals`. Practical values: `24h`, `168h` (week), `672h`. Downloads for `file`/`archive` externals are cached.
- `exact = true` on an archive external: "the directory and all subdirectories will be treated as exact directories, i.e. `chezmoi apply` will remove entries not present in the archive."
- `stripComponents` removes leading path components (1 drops GitHub's `ohmyzsh-master/` top dir).

Source: https://www.chezmoi.io/reference/special-files/chezmoiexternal-format/

### Why archive beats git-repo and beats running install.sh

`git-repo` type limitations, quoted from the user guide:
- "chezmoi's support for `git-repo` externals is limited to running `git clone` and/or `git pull` in a directory."
- "Using a `git-repo` external delegates management of the directory to git. chezmoi cannot manage any other files in that directory."
- "The contents of `git-repo` externals will not be manifested in commands like `chezmoi diff` or `chezmoi dump`"
- "If you need to manage extra files in a `git-repo` external, use an `archive` external instead with the URL pointing to an archive of the git repo's `master` or `main` branch."

Source: https://www.chezmoi.io/user-guide/include-files-from-elsewhere/

The same reasoning applies to a `run_once_` script that executes oh-my-zsh's `install.sh`: the resulting `~/.oh-my-zsh` is entirely outside chezmoi's state (no diff, no exact cleanup, no pinning, no declarative updates), and `run_once_` won't re-run to update it. The archive external keeps the tree declarative, diffable, pinnable, and refreshable.

### Auto-update conflict

Quoted warning from the official docs: "When using Oh My Zsh, make sure you disable built-in auto-updates by setting `DISABLE_AUTO_UPDATE="true"` in `~/.zshrc`." Otherwise oh-my-zsh's self-updater mutates the `exact = true` tree in place and the next `chezmoi apply` reverts/removes its changes — the two updaters fight. Let chezmoi's `refreshPeriod` (or `chezmoi apply -R`) be the only updater.
Source: https://www.chezmoi.io/user-guide/include-files-from-elsewhere/

---

## Sources

- https://www.chezmoi.io/reference/source-state-attributes/
- https://www.chezmoi.io/reference/special-files/
- https://www.chezmoi.io/reference/special-files/chezmoiroot/
- https://www.chezmoi.io/reference/special-files/chezmoiignore/
- https://www.chezmoi.io/reference/special-files/chezmoidata-format/
- https://www.chezmoi.io/reference/special-files/chezmoiexternal-format/
- https://www.chezmoi.io/user-guide/manage-machine-to-machine-differences/
- https://www.chezmoi.io/reference/templates/variables/
- https://www.chezmoi.io/reference/templates/init-functions/
- https://www.chezmoi.io/reference/templates/init-functions/promptStringOnce/
- https://www.chezmoi.io/user-guide/use-scripts-to-perform-actions/
- https://www.chezmoi.io/user-guide/machines/macos/
- https://www.chezmoi.io/user-guide/machines/linux/
- https://www.chezmoi.io/install/
- https://www.chezmoi.io/reference/commands/init/
- https://www.chezmoi.io/reference/configuration-file/
- https://www.chezmoi.io/reference/configuration-file/variables/
- https://www.chezmoi.io/user-guide/password-managers/bitwarden/
- https://www.chezmoi.io/user-guide/password-managers/1password/
- https://www.chezmoi.io/user-guide/password-managers/vault/
- https://www.chezmoi.io/reference/templates/bitwarden-functions/
- https://www.chezmoi.io/reference/templates/bitwarden-functions/rbw/
- https://www.chezmoi.io/reference/templates/functions/
- https://www.chezmoi.io/reference/templates/functions/output/
- https://www.chezmoi.io/reference/templates/functions/fromJson/
- https://www.chezmoi.io/reference/configuration-file/hooks/
- https://www.chezmoi.io/user-guide/encryption/
- https://www.chezmoi.io/user-guide/include-files-from-elsewhere/
- https://docs.brew.sh/Homebrew-on-Linux
- https://docs.brew.sh/Support-Tiers
- https://bitwarden.com/help/cli/
- https://www.1password.dev/cli/get-started/
- https://developer.hashicorp.com/vault/install
- https://github.com/doy/rbw
