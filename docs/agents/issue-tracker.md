# Issue tracker: GitHub

Issues and PRDs for this repo live as GitHub issues. Use the `gh` CLI for all operations.

## Approval gate

**`gh issue create` needs the operator's approval every time.** Propose the issue in the
conversation first: the title, the question, the reason. Wait for the answer. The same gate
covers closing an issue and changing its scope. See the rule and its reason in `AGENTS.md`.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --comments`, filtering comments by `jq` and also fetching labels.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close**: `gh issue close <number> --comment "..."`

Infer the repo from `git remote -v` — `gh` does this automatically when run inside a clone.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature requests; `/triage` reads this flag.)_

When set to `yes`, PRs run through the same labels and states as issues, using the `gh pr` equivalents:

- **Read a PR**: `gh pr view <number> --comments` and `gh pr diff <number>` for the diff.
- **List external PRs for triage**: `gh pr list --state open --json number,title,body,labels,author,authorAssociation,comments` then keep only `authorAssociation` of `CONTRIBUTOR`, `FIRST_TIME_CONTRIBUTOR`, or `NONE` (drop `OWNER`/`MEMBER`/`COLLABORATOR`).
- **Comment / label / close**: `gh pr comment`, `gh pr edit --add-label`/`--remove-label`, `gh pr close`.

GitHub shares one number space across issues and PRs, so a bare `#42` may be either — resolve with `gh pr view 42` and fall back to `gh issue view 42`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.

## Wayfinding operations

Used by `/wayfinder`. A new map is a GitHub **milestone**. It groups one **map issue**, the
decision tickets, the spec, the implementation tickets and the PRs that serve the map. One map
has one milestone. New maps use no sub-issues.

The open maps #1 and #168 keep their sub-issues. Map #168 also has the milestone
`dependency-manager` (#178, amendment).

- **Milestone**: title = the map slug. Create it with
  `gh api --method POST repos/myprysm/dotfiles/milestones -f title=<slug> -f description="Map: #<map>"`.
  Create the map issue first, so the description can name it.
- **Map issue**: an issue labelled `wayfinder:map`, on the milestone
  (`gh issue create --label wayfinder:map --milestone <slug>`). Its body has the standard
  sections, plus `## Route` and `## Next sessions` (see "Session close-out rule"). The milestone
  lists the tickets. The body has no ticket list.
- **Ticket**: an issue on the milestone (`--milestone <slug>` on create, or
  `gh issue edit <n> --milestone <slug>`). Labels: `wayfinder:<type>`
  (`research`/`prototype`/`grilling`/`task`). The spec and the implementation tickets go on the
  same milestone. The spec has a `Map: #<map>` line. In a map with sub-issues, a ticket is a
  sub-issue of the map (`gh api` on the sub-issues endpoint).
- **Mode (HITL/AFK)**: labels carry it, never the body. `wayfinder:research` means AFK.
  `wayfinder:prototype` and `wayfinder:grilling` mean HITL. A `wayfinder:task` ticket also
  carries `ready-for-agent` (AFK) or `ready-for-human` (HITL).
- **Pull requests**: put each PR that serves the map on its milestone
  (`gh pr create --milestone <slug>`).
- **Blocking**: GitHub's **native issue dependencies**. Add an edge with
  `gh api --method POST repos/myprysm/dotfiles/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`.
  `<blocker-db-id>` is the numeric **database id** of the blocker
  (`gh api repos/myprysm/dotfiles/issues/<n> --jq .id`), not the `#number` or the `node_id`.
  `issue_dependencies_summary.blocked_by` counts the open blockers only. A ticket is unblocked
  when every blocker is closed.
- **Operator order**: when the operator orders work after another map or ticket, add native
  blockers. Text in `## Route` or `## Next sessions` is not sufficient. The blocker blocks each
  ticket that has no other open blocker. Why: in who-books-nuxt map #807, the order was only in
  the map text, so a lone `/implement` could start a ticket too early.
- **Frontier query**: list the open issues of the map (`gh issue list --milestone <slug> --state open`,
  or the map's sub-issues). Drop the map issue, each issue with an open blocker and each issue
  with an assignee. Order by the map's `## Route`. A map with no Route uses the milestone order
  (ascending issue number), or the sub-issue order.
- **Claim**: `gh issue edit <n> --add-assignee @me`. This is the first write of the session.
- **Resolve**: `gh issue comment <n> --body "<answer>"`, then `gh issue close <n>`, then add a
  context pointer (gist + link) to the map's Decisions-so-far.
- **Map end**: every `## Route` step is struck, `## Not yet specified` is `None.`, and no
  decision ticket is open.
  1. The session that closes the last decision ticket writes the Spec entry in
     `## Next sessions`.
  2. The `/to-spec` session publishes the spec on the milestone, with a `Map: #<map>` line. Then
     it writes the Tickets entry.
  3. The `/to-tickets` session creates the implementation tickets on the milestone, with a mode
     label and native blockers. Then it writes one Implementation entry.
  4. A map whose Notes carry execution ends with its last task ticket. It has no spec.
     `docs/handoff/` gets no new spec files.
- **Cleanup at map end**. Each step needs operator approval:
  1. Close the map issue, then the milestone
     (`gh api --method PATCH repos/myprysm/dotfiles/milestones/<number> -f state=closed`).
  2. Delete the prototype branches that `wayfinder:prototype` resolutions link, local and remote.
  3. Delete a `research/<name>` branch only when its content is already merged under
     `docs/research/`.

## Session close-out rule

This rule applies to each session that starts from a `## Next sessions` entry: a wayfinder
ticket, `/to-spec`, `/to-tickets`, `/implement-spec` and `/implement`. It is one step of
`sessions.md` › Session end. The other steps apply too.

Update `## Next sessions` with one entry for each session that can start now:

- each open decision ticket on the frontier gets its own `/wayfinder #<map> #<ticket>` entry;
- a spec with open implementation tickets gets one Implementation entry for the whole run,
  never one entry for each ticket;
- a lone ticket gets an `/implement #<ticket>` entry in the `## Next sessions` of map #1.

Only a triaged, actionable lone ticket gets an entry. A `needs-triage` issue gets no entry
until it is triaged. An issue that a bot opens gets no entry (the Renovate Dependency
Dashboard). If the operator closes or re-scopes map #1, revise this rule (#179).

Each entry has a bold label, then `` (`model: <model>`) ``. The default model is `opus`. The
ticket is named by its title, with a link. On the next line, indented, comes the command. Lines
with specifics can follow: HITL prerequisites, amendments, environment state.

```markdown
- **<label>** (`model: opus`): resolve [<ticket title>](<url>). Run `/model opus`, then send:
  /wayfinder #<map> #<ticket>
```

```markdown
- **<label>** (`model: opus`): implement [<ticket title>](<url>). Run `/model opus`, then send:
  /implement #<ticket>
```

At map end, write the entry for the current step:

```markdown
- **Spec** (`model: opus`): write the spec of <map title> (#<map>). Run `/model opus`, then send:
  /to-spec #<map>
  Inputs: `## Decisions so far` of this map and each resolution that it links. Publish the spec on milestone `<slug>` with a `Map: #<map>` line. Then follow the Session close-out rule.
```

```markdown
- **Tickets** (`model: opus`): break the spec <spec title> (#<spec>) into tickets. Run `/model opus`, then send:
  /to-tickets #<spec>
  Create the tickets on milestone `<slug>` with a mode label and native blockers. Then follow the Session close-out rule.
```

```markdown
- **Implementation** (`model: opus`): implement the spec <spec title> (#<spec>), tickets #<first> to #<last>. Run `/model opus`, then send:
  /implement-spec #<spec>
  Start from `main`. Commits and PRs use `Refs #<n>`, never a closing keyword. Give the `ready-for-human` tickets to the operator. Then follow the Session close-out rule.
```

The closing session writes these entries itself. It repeats them word for word in its final
message. It never tells the operator to ask for the prompt.

**Route.** A map has a `## Route` section. It holds the planned order and marks the parallel
lanes: `1. A → 2. { B ∥ C } → 3. D`. Keep a space inside each brace. Strike a step when it is
done. Re-plan the Route when a resolution changes the frontier. Map #1 keeps its order in its
Notes.

**Map write discipline.** `gh issue edit --body-file` replaces the whole body, and parallel
sessions share the map issue.

1. Re-fetch the body right before the write:
   `gh issue view <map> --json body --jq .body > <f>`, where `<f>` comes from `mktemp`. Never
   write from a copy that you loaded earlier.
2. Change only the lines of this session: its Decisions-so-far pointer, its own
   `## Next sessions` entry (remove), the entries that it unblocks (add), and the Route or fog
   edits that its resolution needs.
3. Write once, re-fetch, and confirm that the lines are there. If a line is missing, start
   again at step 1.
