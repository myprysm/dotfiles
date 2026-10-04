# How does codex 0.160 find skills, which name does it use, does it follow symlinks, what happens on a collision, and can a session turn off the global skill directories?

Ticket: myprysm/dotfiles#106

Versions tested: codex-cli 0.160.0 (`codex --version`). The source is openai/codex tag `rust-v0.160.0`, commit `a956835d020762cb2b570053af06f643a11c0ecc` (both sides). Paths are relative to `codex-rs/`. Claude ran probes with `codex exec` in `probe-r2`. Codex ran only `--help` and `features list`.

## Answer

codex scans these roots:
- `$CODEX_HOME/skills` (deprecated, but still read)
- `$HOME/.agents/skills`
- the bundled `$CODEX_HOME/skills/.system`
- the admin root of the system config layer
- the project config `skills` folder
- every `<dir>/.agents/skills` from the project root down to cwd
- the skill roots of enabled plugins

`config.toml` has no key for extra paths. `[[skills.config]]` turns found skills on or off, by `name` or by `SKILL.md` path. It never adds a root.

The skill name is the frontmatter `name`. If `name` is missing or empty, the name is the directory name of the canonical file. A plugin manifest adds the prefix `ns:`.

Directory symlinks are followed in the User, Repo and Admin scopes. A symlinked `SKILL.md` file is skipped.

On a collision there is no name dedup and no error: both skills load. A plain `$name` that matches two or more enabled skills selects none.

No switch turns off only the global dirs. `skip_host_skill_discovery` exists, but it does nothing in the stock CLI. A session can disable skills by name or path with `-c skills.config=...`. It can also override `HOME`, which hides `~/.agents/skills`.

## Claims

1. **CONFIRMED.** The User layer adds `$CODEX_HOME/skills`, `~/.agents/skills` and `.system` (System scope). A comment calls `$CODEX_HOME/skills` deprecated. The System layer adds its `skills` folder (Admin scope). The Project layer adds its config `skills` folder (Repo scope), but only when a repository filesystem exists. Source: `ext/skills/src/host_roots.rs` ~85-119 (both sides).
2. **CONFIRMED.** The resolver adds each existing `<dir>/.agents/skills` from the project root to cwd. The project root comes from `project_root_markers`; without a marker, the resolver uses cwd. Source: `host_roots.rs` 137-268 (both sides).
3. **CONFIRMED.** Roots are deduplicated by path only. Source: `host_roots.rs` 271-274, `seen.insert(root.path.clone())` (both sides).
4. **CONFIRMED.** `SkillsConfig` has only `bundled`, `include_instructions`, `max_context_tokens` and `config`. There is no `paths` key. Sources: `config/src/skills_config.rs` 18-54; `core/config.schema.json` with `additionalProperties:false` (both sides).
5. **CONFIRMED.** Extra roots come only from the app-server RPC `skills/extraRoots/set`. The handler calls `set_extra_roots`, and those roots get User scope after plugin roots. Sources: `ext/skills/src/host_service.rs:154-162`; `app-server/src/request_processors/catalog_processor.rs:595-610` (both sides).
6. **CONFIRMED.** Each `[[skills.config]]` entry has `enabled` and exactly one selector, `name` or `path`. An entry with both selectors is ignored, with a warning. Only the User and SessionFlags (`-c`) layers are read. Later rules override earlier ones. A `name` rule matches every skill with that name. Source: `skills_config.rs` 90-125 and 149-210 (both sides).
7. **CONFIRMED.** A `path` selector is canonicalized. It matches the `SKILL.md` document path, not the directory. Sources: `skills_config.rs` 70-75 and 94-119; `loader/host.rs:387` (codex; Claude-chal confirmed by source). This was not probed.
8. **CONFIRMED.** A disabled skill stays loaded, but it is left out of enabled lookups and counts. Sources: `host_outcome.rs:52-69`; `skills/src/name_counts.rs` (both sides).
9. **CONFIRMED.** The name comes from frontmatter `name`, with whitespace normalized and a limit of 64 characters. When `name` is missing or empty, the name is the parent directory of the **canonical** `SKILL.md`, and in the last case `"skill"`. An empty `description` is an error. Sources: `skills/src/parser.rs` 43-95; `loader/host.rs` 394-403 (both sides).
   - Claude's probe: `dirC` without `name` was listed as `dirC`.
   - Not probed: a symlinked dir without `name` takes the name of the target dir.
10. **CONFIRMED.** A plugin namespace gives `namespace:base_name` only under a valid plugin manifest. Without one, the name is plain. Source: `ext/skills/src/loader/namespace.rs` (both sides).
11. **CONFIRMED.** Directory symlinks are followed in User, Repo and Admin scopes, and ignored in System scope. Hidden directories are skipped. The limits are depth 6, 2000 dirs and 20000 entries per root. Sources: `loader/host.rs` 164-180; `loader/mod.rs` 31-32 (both sides). Claude's probe: `linkdir -> ../../real/sym-real` was listed.
12. **CONFIRMED.** A symlinked `SKILL.md` file is skipped. Sources:
    - `exec-server/src/local_file_system.rs:835-837`: `if is_symlink && (!options.follow_directory_symlinks || !metadata.is_dir()) { continue; }` (both sides)
    - Claude's probe: `dirF/SKILL.md` was not listed.
13. **CONFIRMED.** The walk keeps a set of canonical directories. A link to a directory that was already walked is skipped. Source: `local_file_system.rs` 862-888 (both sides).
14. **CONFIRMED.** Skill identity is the canonical path. The same payload reached through two roots is one skill, and the first one is kept. The discovery path is also kept, so a path mention can use it. Sources: `loader/host.rs` 130-135, 192-207, 325-329; `loader/host_merge.rs` 215-249 (both sides).
15. **CONFIRMED.** Two skills with one name and different canonical paths both load, with no error. Sources: `host_merge.rs` has no name dedup (both sides); Claude's probe listed `probe-dup-r2` twice. "No warning" comes only from Claude's probe.
16. **CONFIRMED.** The merge order is Repo, User, System, Admin, then name, then path. The catalog render order is System, Admin, Repo, User, then name. Sources: `host_merge.rs` 232-268; `ext/skills/src/render.rs` 48-63 (both sides).
17. **CONFIRMED.** A plain `$name` selects a skill only when exactly one enabled skill has that name and no connector has that slug. Canonical and discovery-path mentions disambiguate enabled skills. A path cannot select a disabled skill. Source: `skills/src/selection.rs` 141-194 (both sides).
18. **CONFIRMED.** Disabling by name disables every duplicate. Sources: `skills_config.rs:109-119` (codex); Claude's probe with `-c 'skills.config=[{name="probe-dup-r2",enabled=false}]'` removed both entries.
19. **CONFIRMED.** `~/.agents/skills` comes from `dirs::home_dir()`, which is separate from `CODEX_HOME`. Sources: `host_roots.rs` 35-36 and 95-113 (both sides). Claude's probe with `HOME=<empty> CODEX_HOME=~/.codex` removed `computer-use`, `find-skills`, `orca-cli` and `orchestration`. Repo skills and bundled skills stayed.
20. **CONFIRMED.** `skills.include_instructions=false` removes only the automatic instructions block. `skills.bundled.enabled=false` removes only System roots. Sources: `skills_config.rs:36-38`; `extension.rs:194-200`; `host_service.rs:260-270` (both sides).
21. **CONFIRMED.** Load errors in System scope are swallowed. Other scopes collect `SkillError`. Discovery warnings are still logged. Sources: `loader/host.rs` 183-185 and 325-334 (both sides).
22. **CONFIRMED.** The feature `skip_host_skill_discovery` exists. Its stage is "under development" and its default is false. It skips host discovery only when the feature is on **and** no extension requires host discovery. Sources: `core/src/session/turn_context.rs:1207-1229`; `codex features list` -> `skip_host_skill_discovery  under development  false` (both sides).
23. **CONFIRMED-CORRECTED.** In the stock 0.160.0 CLI, `--enable skip_host_skill_discovery` has no effect. Correction: codex-r2 said "A session can skip all host skill discovery".
    - Source: the skills extension returns `requires_host_skill_discovery() = self.providers.has_host_provider()` (`ext/skills/src/extension.rs:349-350`; I re-read it). The trait default is `true` (`ext/extension-api/src/contributors.rs:338-340`; I re-read it).
    - Probe: `codex exec --enable skip_host_skill_discovery ...` still listed all 12 skills (Claude-chal).
    - Codex-chal kept "exists, conditional". It did not rebut the probe or `extension.rs:349`.
24. **CONFIRMED.** No setting removes only the global dirs and keeps repo discovery. `resolve_skill_roots` has no root-type filter. Sources: `host_roots.rs` (both sides).
25. **UNVERIFIED.** The current docs (learn.chatgpt.com/docs/build-skills) are not versioned. They say `name` is required. They omit `$CODEX_HOME/skills`. Source: codex only. Claude did not fetch these docs.
26. **CONFIRMED.** The skill roots of enabled plugins are also appended to the root list. Runtime extra roots come after them. Sources: `host_roots.rs` 56-119 and `resolve_skill_roots_with_home_dir` (codex-r2 claim 3; claude-chal-r2 claim 3 confirmed by source). Not probed.

## Corrections to earlier claims

- codex-r2 Answer and claim 9 say a session can skip host discovery. This is corrected by claim 23: the flag does nothing in the stock CLI.
- claude-r2 Answer, "No switch turns off ~/.agents/skills or ~/.codex/skills": a switch exists, but it has no effect. So the practical statement stands.
- claude-r2 claim 11 gives the name fallback as "the directory name". It is the canonical (target) directory name, and an empty `name` also falls back (claim 9).
- Codex-chal re-derived the line numbers from the same clean checkout. No line-number dispute is open.

## Open points

- Does the project `.codex/skills` root need a trusted project? Not examined.
- What `HOME` override does outside skills (gitconfig and other `$HOME` files)? Not tested.
- Does `-c skills.config=...` act the same in the TUI as in `exec`? The code path is the same, but only `exec` was probed.
- With two same-name skills in the catalog, which one does the model read? Not probed.

## Consequences for the map

- codex reads `~/.agents/skills` and `$CODEX_HOME/skills`. A skills-CLI payload in `~/.agents/skills` reaches codex with no extra link (claims 1, 19).
- codex has no `skills.paths` equivalent in `config.toml`. A pinned checkout reaches codex only through a discovery root: `~/.agents/skills`, a repo `.agents/skills`, `$CODEX_HOME/skills`, an admin root, the project config `skills` folder, the root of an enabled plugin, or the app-server RPC (claims 1, 2, 4, 5, 26).
- A name collision gives two loaded skills, and a plain `$name` is then ambiguous. No root wins (claims 15, 17).
- A session cannot drop only the global dirs. It can disable named skills with `-c skills.config`, or point `HOME` at another dir (claims 18, 19, 23, 24).
- The name comes from frontmatter `name`. Only when `name` is missing or empty does codex use the parent directory of the canonical `SKILL.md`. Two folders with the same frontmatter `name` collide (claim 9).
- Symlinked skill directories work. Symlinked `SKILL.md` files do not (claims 11, 12).

