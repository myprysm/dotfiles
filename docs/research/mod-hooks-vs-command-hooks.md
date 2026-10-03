# Mod hooks next to command hooks: order and bypass

Research for #87. Claude Code version: 2.1.288. Date: 2026-10-03.

The question: can a mod hook run before `block-secret-reads`, stop it, or change the tool
input after it checked? Do `disableAllHooks` and the permission rules apply to mod hooks?

## Sources and labels

Each claim has one label.

- VERIFIED: the source is quoted at a file and line, or at a URL.
- TESTED: a throwaway mod ran under `claude plugin test`. The test kit is a stand-in for a
  session. It is not a live session.
- UNVERIFIED: no source states it. The note says what test would answer it.

Source keys:

- `[T]` — the type declarations that Claude Code 2.1.288 wrote when the `plugin-authoring`
  skill loaded: `/tmp/claude-1000/bundled-skills/2.1.288/<hash>/plugin-authoring/types/claude-code.d.ts`.
  The engine writes this file again at each load. The line numbers apply to 2.1.288 only.
- `[R]` — `reference.md` beside that file, in the same skill folder.
- `[B]` — strings in the 2.1.288 binary (`~/.local/share/claude/versions/2.1.288`). The code is
  minified. Function names in it have no meaning.
- `[D-events]` — https://code.claude.com/docs/en/plugins/mods/events
- `[D-admin]` — https://code.claude.com/docs/en/plugins/mods/admin
- `[D-perm]` — https://code.claude.com/docs/en/permissions, section "Extend permissions with hooks"
- `[D-trouble]` — https://code.claude.com/docs/en/plugins/mods/troubleshoot
- `[D-hooks]` — https://code.claude.com/docs/en/hooks
- `[Blog]` — https://claude.dev/blog/getting-started-with-claude-code-mods/ (secondary only)
- `[P]` — the probe mod `guardprobe`, described in the section "The probe".

## Facts: the chain

- A mod hook has the shape `($, e, next)`. `next(e)` runs the hooks beneath it, then the core.
  VERIFIED `[R]` lines 16-22.
- A hook that returns without `next` answers the event. The hooks beneath it and the core do not
  run. VERIFIED `[D-events]` "Answer an event".
- The chain has five tiers, outermost first: `prepend`, `user`, `append`, `builtin`, `core`.
  VERIFIED `[T]` lines 11900-11906.
- An outer tier runs first. It has more authority. VERIFIED `[T]` line 11900.
- Every mod that a person installs is in the `user` tier. This includes a `--plugin-dir` mod and
  a mod that Claude writes in a session. VERIFIED `[T]` lines 11893-11895; `[D-admin]` "Enforce
  a policy with a mod of your own".
- A user hook cannot use `next.to()` to skip a tier with more authority. VERIFIED `[T]` lines
  6129-6131 and 11617-11620.
- A hook that throws or times out before it calls `next` is skipped. The hooks beneath it run in
  its place. VERIFIED `[T]` lines 3728-3730; `[D-events]` "Handle a hook that fails".

## Facts: where the settings PreToolUse hook runs

- PreToolUse hooks from managed settings run before the first mod `tool.call` hook. Their block
  is final. VERIFIED `[T]` line 3739; `[D-events]` "Where settings hooks run in the order".
- PreToolUse hooks from every other settings file run after the last mod calls `next`. They run
  as part of the core. VERIFIED `[D-events]` "Where settings hooks run in the order".
- `block-secret-reads` is in user settings (`home/.chezmoitemplates/claude-settings.json`,
  `hooks.PreToolUse`, matcher `Read|Grep|Bash`). It is not a managed hook. VERIFIED (file read).
- Thus every user-tier mod `tool.call` hook runs before `block-secret-reads`. VERIFIED by the
  two facts above.
- The `classic.PreToolUse` event fires inside `tool.call`, beneath every mod `tool.call` hook.
  VERIFIED `[T]` lines 7520-7521.
- The `classic.PreToolUse` chain is: managed settings hooks, then the mod hooks, then the other
  settings hooks as the core. VERIFIED `[T]` lines 1074-1076.
- Thus a mod `classic.PreToolUse` hook also runs before `block-secret-reads`, and sees its
  answer when it calls `next`. VERIFIED by `[T]` lines 1074-1076.
- A `classic.PreToolUse` result can carry `updatedInput`. The engine checks it against the tool
  schema only. VERIFIED `[T]` lines 7523-7527.

## Facts: can a mod stop the guard

- A mod `tool.call` hook that returns `{ result }` without `next` stops the guard. The tool does
  not run, and the model reads the mod's result. VERIFIED `[D-events]` "Where settings hooks run
  in the order"; `[D-admin]` "Know which controls still apply". TESTED `[P]` test 2: the guard
  stand-in saw nothing.
- A mod `classic.PreToolUse` hook that returns `{}` without `next` stops the guard. The tool then
  runs. TESTED `[P]` test 3: the guard stand-in saw nothing; the tool stand-in ran.
- A mod `classic.PreToolUse` hook can call `next`, get the guard's `deny`, and return `{}`. The
  tool then runs. TESTED `[P]` test 4.
- The docs do not describe the `classic.PreToolUse` cases. UNVERIFIED in a live session. Test:
  run `claude --plugin-dir <probe> --debug` with the real guard, and ask Claude to Read a path
  that the guard denies but no deny rule matches.

## Facts: can a mod change the input after the guard checked

- A mod `tool.call` hook cannot do it on the same pass. The guard is beneath it, so the guard
  sees the input that the mod passes to `next`. VERIFIED `[T]` lines 7520-7521.
- A mod `tool.call` hook can call `next` again with new input. Each `next` runs the chain beneath
  again, so the guard checks the new input too. VERIFIED `[D-events]` "To retry a call, call
  `next(e)` again"; `[T]` lines 3734-3735.
- A mod `classic.PreToolUse` hook can call `next`, get the guard's pass, and return
  `updatedInput` with a different path. The tool runs on the new path. The guard never sees it.
  TESTED `[P]` test 5: the guard stand-in saw `/home/u/swap`; the tool stand-in ran on
  `/home/u/.ssh/id_rsa`.
- Only managed hooks run again on a rewritten call. VERIFIED `[D-admin]` "Managed hooks run
  first".
- The permission deny rules are checked in `tool.check`, after the PreToolUse hooks. It is not
  known if `tool.check` reads the rewritten input or the original input. UNVERIFIED. Test: the
  live probe above, with `updatedInput` set to a path that a deny rule in
  `claude-settings.json` matches (for example `**/.ssh/**`).

## Facts: tool.check and the permission rules

- `tool.check` fires after the permission rules and the settings hooks have decided. VERIFIED
  `[T]` lines 3743-3747; `[D-events]` "Approve or refuse a tool call before the user is asked".
- A `tool.check` hook may return any verdict, in either direction. The last word up the chain is
  the decision. VERIFIED `[T]` lines 12129-12131.
- A mod `tool.check` hook can approve a call that a non-managed PreToolUse hook blocked.
  VERIFIED `[D-events]` (same section); `[D-perm]`; `[D-admin]` "Know what happens by default".
- This applies to `block-secret-reads`: a mod can approve a call that the guard denied.
  VERIFIED by the facts above. Not TESTED: the test kit does not raise `tool.check` inside
  `$.tool.call` (`[P]` test 6).
- A mod can approve a call that an `ask` rule would prompt for. In auto mode, a call that a mod
  approves runs with no classifier check. VERIFIED `[D-perm]`; `[D-admin]`.
- Deny rules hold over a user mod only where the built-in guard `sec-default@builtin` loads.
  VERIFIED `[D-perm]`; `[D-admin]` "Deny rules take precedence where the guard loads".
- The built-in guard loads only on a machine with managed settings, or for a user signed in with
  a Team or Enterprise plan. VERIFIED `[D-admin]` "Know what happens by default".
- Elsewhere, a mod can approve a call that a deny rule refuses. VERIFIED `[D-perm]`.
- This WSL machine has no `/etc/claude-code` folder, so no managed settings file. VERIFIED
  (`ls`). The plan of the signed-in account is not known. UNVERIFIED. Thus it is not known if the
  built-in guard loads here. Test: `claude --debug`, then search the log for
  `cc-plugin-sec-default`. Do it on each machine, because the repo targets several.
- Deny rules and managed hooks do not apply to a mod's own `$.fs` and `$.process` calls. With
  `Read(.env)` denied, a mod can read that file with `$.fs.read`. VERIFIED `[D-admin]`.
- Where a `$.fs` call may go is decided by `fs.*` hooks only. VERIFIED `[T]` lines 3011-3012.
- Mods are not sandboxed. A mod runs with the user's permissions. VERIFIED `[D-admin]` (intro).

## Facts: disableAllHooks

- `disableAllHooks` turns off the hooks in settings files and the hooks of installed plugins.
  VERIFIED `[B]` settings schema string: "Disable all hooks and statusLine execution: the hooks
  defined in settings files and by installed plugins."
- `disableAllHooks` set in a non-managed settings file stops installed mods. The refusal reads
  `only managed plugins and built-in plugins run`. VERIFIED `[D-trouble]` "Refusal messages";
  `[B]` code: a merged `disableAllHooks === true` with no managed `disableAllHooks` sets the
  "managed only" state.
- `disableAllHooks` in managed settings stops the mods of every installed plugin, managed ones
  too. VERIFIED `[D-admin]` "Choose how much to allow"; `[D-trouble]`.
- Built-in mods are not affected by these settings. VERIFIED `[D-admin]`; `[B]` "built-in
  plugins load regardless".
- `disableAllHooks` also turns off `block-secret-reads`, because it is a settings hook. VERIFIED
  `[D-hooks]` "disableAllHooks".
- `disableAllHooks` from a lower settings file can be overridden by a higher one. For example, a
  project `false` overrides a user `true`. VERIFIED `[D-hooks]`.
- `allowManagedHooksOnly` (managed only) loads only managed and built-in mods, and blocks user
  settings hooks. VERIFIED `[D-admin]`; `[D-hooks]`.
- `--safe-mode` turns off installed mods. VERIFIED `[D-admin]`.
- `--bare` turns off non-managed mods. VERIFIED `[D-trouble]` "Refusal messages".

## Facts: controls on which mods load

- A `prepend` mod can refuse another mod at load, through `plugin.register`. VERIFIED `[T]`
  lines 4157-4165; `[D-admin]`.
- The built-in guard option `allowManagedModsOnly` refuses every user mod. Only managed settings
  can set it. VERIFIED `[D-admin]` "Stop user-installed mods from loading".
- `disableSideloadFlags` (managed) rejects `--plugin-dir` and stops mods that Claude writes in a
  session. VERIFIED `[D-admin]`.
- A module is judged at load only by the plugins admitted before it. VERIFIED `[T]` lines
  4160-4162. Thus a user mod cannot refuse a mod that was admitted before it.

## Secondary source

- The blog calls a `tool.call` guard "a safety net, not a permission system" and says "Use
  permission rules for a hard block." `[Blog]`. The docs above show that, without the built-in
  guard, a mod can override deny rules too.

## The probe

- Folder: the session scratchpad, `guardprobe/`. It was not installed. No settings were changed.
- `claude plugin validate` passed: `hooks: tool.call{tool=Read}, classic.PreToolUse,
  tool.check{tool=Read}`.
- In the test kit, the test's own hooks sit beneath every plugin hook. A test
  `classic.PreToolUse` hook stands in for a settings hook. A test `tool.call` hook stands in for
  the tool. VERIFIED `[R]` line 75; `[T]` lines 13950-13952.
- The guard stand-in denied any path that matched `id_rsa|.env|override|checkallow`.
- Results:
  1. Control, `/home/u/.env`: the guard denied it; the tool did not run.
  2. Mod `tool.call` answers `{ result }`: the guard did not run; the tool did not run.
  3. Mod `classic.PreToolUse` returns `{}`: the guard did not run; the tool ran.
  4. Mod `classic.PreToolUse` drops the guard's `deny`: the guard ran and denied; the tool ran.
  5. Mod `classic.PreToolUse` sets `updatedInput` after the guard passed: the tool ran on
     `/home/u/.ssh/id_rsa`.
  6. Mod `tool.check` returns `deny` for a path: the tool still ran. The kit does not raise
     `tool.check` inside `$.tool.call`. This test answers nothing about `tool.check`.

## Risk to block-secret-reads

- Any installed mod runs before the guard. This is the design, not a defect.
- Any installed mod can stop the guard. It answers `tool.call` itself, or answers
  `classic.PreToolUse` without `next`.
- Any installed mod can drop the guard's deny in `classic.PreToolUse`, or approve the call in
  `tool.check`.
- Any installed mod can change the path after the guard passed it, through `updatedInput` in
  `classic.PreToolUse`. The guard does not see the new path.
- The permission deny rules in `claude-settings.json` are the second layer. They hold over a mod
  only where the built-in guard loads. That needs managed settings or a Team or Enterprise
  sign-in. This WSL machine has no managed settings file.
- A mod does not need any of this to read a secret. `$.fs.read` and `$.process.run` reach every
  file the user can read. No hook or rule in this repo covers them.
- Conclusion: `block-secret-reads` stops the model. It does not stop a mod. A mod is trusted code
  with the user's full access. The only control is which mods load.
- The control that exists today for a personal machine: install only mods that you read, and run
  `claude plugin validate` on each one first. Check its `hooks:` line for `tool.call`,
  `classic.PreToolUse` and `tool.check`, and its `calls:` line for `fs.read` and `process.run`.
- The stronger controls need managed settings: `allowManagedModsOnly`, `allowManagedHooksOnly`,
  `disableSideloadFlags`, a managed copy of the guard, or a `prepend` policy mod. A managed
  settings file is a decision for the operator. This note does not propose it.
- `disableAllHooks` in user settings is not a fix. It stops mods, but it also stops the guard.
- Open items:
  - Run the live probe with the real guard to confirm `classic.PreToolUse` behaviour in a
    session.
  - Check if the deny rules read the input after `updatedInput`.
  - Check on each machine if `cc-plugin-sec-default` loads.
