# Research: bw CLI password login fails against Vaultwarden (`KeyIdBackfillError`)

Ticket: [bw CLI password login fails against Vaultwarden](https://github.com/myprysm/dotfiles/issues/81).
Sources checked on 2026-10-03. Every claim links to a primary source.

## Answer

- The bw CLI runs the backfill from `cli-v2026.9.0`. The last release without it is `cli-v2026.8.0`.
- Vaultwarden implements the endpoint on `main` only. No release up to `1.37.3` has it. The first
  release after `1.37.3` will have it.
- No feature flag, env var or CLI option skips the step. A server setting cannot skip it either.

## 1. What the CLI does

- The CLI sends `POST /api/accounts/key-management/user-key-id` with the body
  `{"userKeyId": "<key id>"}`.
  - SDK API client: [`accounts_key_management_api.rs`](https://github.com/bitwarden/sdk-internal/blob/main/crates/bitwarden-api-api/src/apis/accounts_key_management_api.rs).
  - SDK request and error: [`key_id_backfill.rs`](https://github.com/bitwarden/sdk-internal/blob/main/crates/bitwarden-user-crypto-management/src/key_id_backfill.rs).
    `KeyIdBackfillError::Api` is "API call failed during user key id backfill". Any API failure,
    a 404 included, maps to it.
  - Bitwarden server route: [`AccountsKeyManagementController.cs`](https://github.com/bitwarden/server/blob/main/src/Api/KeyManagement/Controllers/AccountsKeyManagementController.cs).
- The clients repo runs it as an encrypted migration:
  [`user-key-id-backfill-migration.ts`](https://github.com/bitwarden/clients/blob/cli-v2026.9.1/libs/common/src/key-management/encrypted-migrator/migrations/user-key-id-backfill-migration.ts).
  - The migration runs only when the server holds no key id and the local user key has one.
  - Its own comment says: "Servers older than the one introducing the backfill endpoint answer
    with a 404".
  - On an API error it sets a 24-hour cooldown
    ([df0e539](https://github.com/bitwarden/clients/commit/df0e5396b7cfa5fc50fdc21002090d35e6423d9c)),
    but it still rethrows the error.
- The migrator registers it with no condition:
  [`default-encrypted-migrator.ts`](https://github.com/bitwarden/clients/blob/cli-v2026.9.1/libs/common/src/key-management/encrypted-migrator/default-encrypted-migrator.ts).
  The V2 key rotation migration next to it is skipped for the CLI. The backfill is not.
- Two CLI commands call `runMigrations` inside their `try` block, so the error fails the command:
  - `bw login`: [`login.command.ts`](https://github.com/bitwarden/clients/blob/cli-v2026.9.1/apps/cli/src/auth/commands/login.command.ts), about line 424.
  - `bw unlock`: [`unlock.command.ts`](https://github.com/bitwarden/clients/blob/cli-v2026.9.1/apps/cli/src/key-management/commands/unlock.command.ts), line 74.
- No gate: the migration and the migrator use no `ConfigService` and no feature flag.
  [`feature-flag.enum.ts`](https://github.com/bitwarden/clients/blob/main/libs/common/src/enums/feature-flag.enum.ts)
  has no backfill or key id entry.

## 2. CLI versions

- [PR #22444 "[PM-40814] Add key id support"](https://github.com/bitwarden/clients/pull/22444)
  added the backfill. It was merged on 2026-08-20.
- The migration file is absent at `cli-v2026.8.0`. It is present at `cli-v2026.9.0` and at
  `cli-v2026.9.1`, with the same blob as `main` (`100988c1`). Checked with
  `gh api repos/bitwarden/clients/contents/<path>?ref=<tag>`.
- Releases ([list](https://github.com/bitwarden/clients/releases)):

  | Tag | Published | Backfill |
  |---|---|---|
  | `cli-v2026.8.0` | 2026-08-20 | no |
  | `cli-v2026.9.0` | 2026-09-17 | yes |
  | `cli-v2026.9.1` | 2026-10-01 (latest) | yes, unchanged |

- [Vaultwarden issue #7750](https://github.com/dani-garcia/vaultwarden/issues/7750) reports the
  same failure with CLI 2026.9.0. It says CLI 2026.8.0 still logs in.

## 3. How to pin `cli-v2026.8.0`

- **Homebrew (macOS and Linux).** The
  [formula](https://github.com/Homebrew/homebrew-core/blob/main/Formula/b/bitwarden-cli.rb)
  builds from the clients source with `node`. Its bottle is `all`, so macOS and Linuxbrew get the
  same build. No versioned formula was found. The 2026.8.0 bump is homebrew-core commit
  `ed929429be`. Not run:

  ```sh
  brew tap-new <user>/local
  brew extract --version=2026.8.0 bitwarden-cli <user>/local
  brew uninstall bitwarden-cli
  brew install <user>/local/bitwarden-cli@2026.8.0
  brew pin bitwarden-cli@2026.8.0
  ```

  An extracted formula has no bottle, so it builds from source.
- **npm.** `@bitwarden/cli@2026.8.0` is on the
  [registry](https://registry.npmjs.org/@bitwarden/cli): `npm i -g @bitwarden/cli@2026.8.0`.
- **Release zip.** [`cli-v2026.8.0`](https://github.com/bitwarden/clients/releases/tag/cli-v2026.8.0)
  publishes `bw-linux-`, `bw-linux-arm64-`, `bw-macos-`, `bw-macos-arm64-` and the `bw-oss-*`
  variants, as `<name>-2026.8.0.zip`. No `.sha256` files are published. The GitHub API `digest`
  field of each asset gives the sha256.

The `packages` manifest installs `bitwarden-cli` from brew, and `brew bundle` keeps it upgraded.
A pin must therefore replace the brew entry, not sit beside it. This research did not design that
change.

## 4. Vaultwarden

- The route is on `main`: `#[post("/accounts/key-management/user-key-id")]` in
  [`src/api/core/accounts.rs`](https://github.com/dani-garcia/vaultwarden/blob/main/src/api/core/accounts.rs).
  It stores the key id. It returns 422 when the user already has one. A database migration
  `2026-09-02-120000_add_key_id` adds the `users.key_id` column.
- [PR #7693 "[web-v2026.8.1] store the user key ID"](https://github.com/dani-garcia/vaultwarden/pull/7693)
  added it. It was merged on 2026-09-18 as `9c8aa235`. It closed issue #7750.
- The latest release is [`1.37.3`](https://github.com/dani-garcia/vaultwarden/releases), published
  on 2026-09-13. `9c8aa235` is 3 commits ahead of `1.37.3`, and no tag contains it.
- The `/api/config` handler
  ([`src/api/core/mod.rs`](https://github.com/dani-garcia/vaultwarden/blob/main/src/api/core/mod.rs),
  [`src/config.rs`](https://github.com/dani-garcia/vaultwarden/blob/main/src/config.rs)) sends
  only the experimental flags an admin allows, plus one hard-coded flag. None of them relates to
  the key id. The client reads no flag for this step anyway.
- The Vaultwarden README states no supported client version range.

## Options

1. **Wait for the first Vaultwarden release after `1.37.3`, then upgrade the server.** Until then,
   `bw login --sso` works.
2. **Pin the CLI to `cli-v2026.8.0`** on every machine (section 3).
3. **Run a Vaultwarden build from `main` at or after `9c8aa235`.** This is an unreleased build.

## Not verified

- Why SSO login does not hit the error. The `runMigrations` call sits on the path that SSO also
  takes. One guess: the backfill needs a local user key that has a key id, and the SSO session may
  not have one. Not confirmed.
- Whether `bw unlock` of an SSO session fails in the same way.
- Whether the 24-hour cooldown survives a failed `bw login`.
- The `brew extract` steps were not run.
- Whether `cli-v2026.8.0` has other problems against Vaultwarden.
- The SDK source was read on `main`, not at the SDK version that `cli-v2026.9.1` pins
  (`0.2.0-main.1034`).
