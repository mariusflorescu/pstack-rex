# pstack-rex design

pstack upstream runs on Cursor, where a subagent is a `Task` call. pstack-rex runs the same skills in Claude Code or Codex inside [Rex](https://www.superlogical.com/rex), and every subagent is another Claude Code or Codex agent in a Rex pane next to the one you're talking to.

Everything here was probed against Rex `0.0.1793299046` (API revision 7), Claude Code 2.1.316 and Codex 0.166.0 on 2026-11-01. "Probed" below means it was observed, not read in docs.

## Pane layout

```
┌────────────────────┬────────────────────┐
│                    │ interrogate claude │
│                    ├────────────────────┤
│    main agent      │ interrogate codex  │
│  (Claude or Codex) ├────────────────────┤
│                    │ watch PR 123       │
└────────────────────┴────────────────────┘
```

- The main agent's pane is `$REX_BLOCK`. It never moves.
- The first worker splits the main pane to the right (50%). Later workers stack in that column with equal heights.
- A column holds 3 workers (`PSTACK_REX_ROWS`). The 4th starts a new column to the right of the last one. The main pane keeps its width.
- Closing a worker rebalances its column. Closing the last one leaves the main pane alone in its tab.
- Workers always open with `focus=false`, so the cursor stays where Marius is typing.

## Workers

One CLI, `skills/rex-subagents/scripts/subagent`, owns the whole lifecycle. Skills never call `rex` directly for workers.

| Command | Does |
| --- | --- |
| `subagent spawn --name N --brief FILE [--agent claude\|codex] [--model M] [--effort E] [--entry "codex/M (E)"] [--worktree BRANCH [--base REF]] [--read-only]` | Opens the pane, starts the agent full-access, hands it the brief, prints JSON |
| `subagent run --name N -- CMD...` | A plain command in a worker pane (the `watch-pr` poller, a test loop, a timer). Its exit wakes the main agent |
| `subagent status [ID...]` | Every worker of this main pane: state, TASK STATUS, age |
| `subagent result ID` | The worker's last message, read from its own transcript |
| `subagent say ID (TEXT\|--file F)` | A follow-up to a worker that holds state |
| `subagent answer ID N` | Picks option N in a dialog a worker is blocked on |
| `subagent close (ID...\|--all) [--remove-worktree]` | Closes panes, rebalances, removes worktrees |
| `subagent wait [--for DUR]` | Blocks until a worker event arrives. Optional, see below |

Launch, per agent:

- **Claude:** `claude --dangerously-skip-permissions -n "<name>" --session-id <uuid> [--model M] [--effort E] "<pointer>"`. The session id is chosen up front, so the transcript is `~/.claude/projects/*/<uuid>.jsonl`.
- **Codex:** `codex --dangerously-bypass-approvals-and-sandbox [-m M] [-c model_reasoning_effort="E"]` with no prompt. Once it reports `idle`, `subagent` types `/rename <name>`, then the pointer. A slash command sent through `codex queue` arrives as plain text (probed), so renaming has to be typed. The pointer carries `(pstack-rex worker <id>)`, which finds the rollout in `~/.codex/sessions` and from it the thread id.
- **The pointer** is one line: read `<state>/workers/<id>/brief.md` in full and do what it says. The brief file is the main agent's brief plus a footer asking for `TASK STATUS: done|blocked|needs-review` as the last line.
- **Permissions are locked.** `subagent` has no pass-through for agent flags, so nothing can add `--permission-mode`, `--sandbox` or `--ask-for-approval`.
- **Defaults.** Claude runs on the main account (`~/.claude`) and its default model. Codex runs on the model in `~/.codex/config.toml`. A pane runs the login shell's environment, not the main agent's, so `subagent` passes the variables in `PSTACK_REX_PASS_ENV` (default `AWS_PROFILE AWS_REGION AWS_DEFAULT_REGION`) along.
- **Trust dialogs.** Both agents ask before working in a folder whose repository root they haven't trusted, even when a parent is trusted, and neither reports a status while the dialog is up (probed). A worker only ever runs in the main agent's repository or a worktree of it, and the main agent already runs there with full access, so `subagent` accepts the dialog when it names that folder, and reports `trust_accepted` in its JSON.
- **Names.** The pane label and the conversation name are the same (`interrogate codex`). The id is the name in kebab case (`interrogate-codex`), suffixed `-2`, `-3` on collision.

## The watcher and how results get back

```
worker pane ──OSC 7501──▶ Rex ──terminal.program_status_changed──▶ watch.lua (rex do -s SESSION)
                                  terminal.child_exited, block_closed        │
                                                                             ▼
                                                    subagent _event: record, read TASK STATUS
                                                                             │
                                  ┌──────────────────────────────────────────┤
                                  ▼                                          ▼
                        main is Codex: codex queue             main is Claude: rex send + enter
                        --thread $CODEX_THREAD_ID              into the main pane
```

- **One watcher per Rex session**, `rex do -s <session> watch.lua`, started detached by the first `spawn` and stopped when the session has no workers left. A pidfile keeps it single. `status` restarts it when it died.
- **Signals.** Claude Code and Codex both report through the Program Status Protocol (OSC 7501): `idle`, `working`, `done`, `blocked` (with `kind` and `msg`), `error`. The watcher reads only the root record of registered worker blocks, plus `terminal.child_exited` and `block_closed`.
- **What wakes the main agent.** A `done` whose last message carries `TASK STATUS:`. A `done` without one, once the pane stays quiet for 45s (a Claude worker with a background shell reports `done`, then works again when the shell finishes, probed). Any `blocked`, `error`, exit or close. Plain turn churn never does.
- **Codex rewrites `done` to `idle`** on a redraw or resize (probed), so the live record is not the truth after the fact. The watcher records each `done` when it fires, and `status` reads the record.
- **Delivery.** Each wake is one line, `[pstack-rex] interrogate-codex finished (TASK STATUS: done). 1 of 3 still running. Read it: <cli> result interrogate-codex`. Events within 2s go out as one line.
  - Codex main: `codex queue --thread $CODEX_THREAD_ID --message ...`. It starts a turn when Codex is idle and lands as the next turn when it's busy (probed).
  - Claude main: `rex send` plus `enter` into the main pane. It starts a turn when idle, and Claude takes it between tool calls when busy (probed). If the main pane is `blocked` on a dialog, the line waits until it isn't.
  - The main agent is detected from its own environment when it runs `subagent`: `CODEX_THREAD_ID` (Codex) or `CLAUDE_CODE_SESSION_ID` (Claude).
- **No polling.** The main agent spawns, says what it's waiting for, and ends its turn. The wake line starts its next turn. `subagent wait` exists for a script or a Claude main that would rather block in a background command; while one runs, the watcher doesn't type into that pane.
- **Results** come from the worker's own transcript, not its screen: the last assistant text in the Claude transcript, or `last_agent_message` of the latest `task_complete` in the Codex rollout. The screen is the fallback.

State lives in `~/.local/state/pstack-rex/`: `workers/<id>.json`, `workers/<id>/brief.md`, `by-block/<block>` links for the watcher, `inbox/<main>.ndjson`, `watchers/<session>.pid`, `log/`.

## Worktrees

`--worktree <branch>` gives a writer its own tree. `subagent` creates the branch at `--base` (default: the main checkout's `HEAD`), then runs the `WorktreeCreate` hook from `~/.claude/settings.json` when there is one (Marius's names the folder `<repo>/.claude/worktrees/<branch with - for />`), else `git worktree add` at the same place. Uncommitted edits don't reach a new worktree, so commit first. `close --remove-worktree` runs the `WorktreeRemove` hook or `git worktree remove`, refuses a dirty tree without `--force`, and deletes the branch only when it's merged.

## Models

`/setup-pstack` writes `~/.config/pstack/pstack-models.md`, one `role: entry` line per pstack role. An entry is `claude/<model> (<effort>)` or `codex/<model> (<effort>)`, or `inherit-parent` for the main agent's own harness on its default model. `claudeAgent/...` from the pstack-t3 file is read as `claude/...`, so an existing file keeps working. A family is the harness, `claude` or `codex`, which is what arena's cross-judge rule and the interrogate panel diversify on.

## What changes per skill

The layer is small on purpose: the runtime lives in one new skill, and the other skills change only on the lines that name a Cursor mechanism. [REX-NATIVE.md](./REX-NATIVE.md) is the translation contract, and `scripts/check-rex-native.mjs` enforces it.

| Upstream (Cursor) | pstack-rex |
| --- | --- |
| `Task` call, `subagent_type`, `run_in_background` | `subagent spawn` per `rex-subagents/SKILL.md`. Always async. End the turn and let the wake line arrive |
| `poteto-agent`, `comment-sicko` agent files | Briefs in `poteto-mode/references/` and `no-comments/references/`, pasted at the top of the brief |
| `readonly: true` | `--read-only`, which adds "read-only: inspect only, no writes, no git commands" to the brief |
| Model slugs, the Cursor models rule | Roles in `~/.config/pstack/pstack-models.md` |
| Cloud agent, `environment: "cloud"` | `spawn --worktree <branch>` |
| Resume or message a subagent | A fresh `spawn` with consolidated scope. `subagent say` only to a worker that holds needed state |
| `/loop`, wake-ups, the `watch-pr` poller | `subagent run -- <poteto-mode>/scripts/watch-pr/watch-pr ...` (upstream's poller, unchanged). Its exit wakes the main agent |
| Agent transcripts | `rex-subagents/scripts/sessions`, which lists and reads Claude Code transcripts and Codex rollouts |
| Origin forge, Graphite `gt` | `gh` and git |
| `AskQuestion`, Cursor todo list, `create-skill`, `control-ui`/`control-cli` | Ask in the chat, the harness's task list, `skill-creator`, the project's verification skill or the shell and Rex panes |

Per skill: `poteto-mode` (Subagents section, references), `setup-pstack` (reads models from Claude and Codex, writes the file), `swarm`, `arena`, `interrogate`, `architect`, `how`, `why`, `reflect` (spawn lines and model defaults), `recall`, `ketchup`, `automate-me`, `correct`, `session-pickup` (transcripts), `babysit`, `shipping`, `autopilot-*`, `orchestrate`, `opening-a-pr`, `multi-phase-plan` (PR waits via `subagent run`, worktrees via `spawn --worktree`), and single lines in the rest. `skills/rex-subagents/` is new. Every user-only skill also ships `agents/openai.yaml` so Codex hides it the way Claude Code does.

## Upstream sync

`UPSTREAM` pins the cursor/plugins commit. `scripts/sync-upstream.sh <sha>` does a three-way merge per file: base is upstream at the pinned commit, ours is `skills/`, theirs is upstream at `<sha>`. Files the port never touched fast-forward. Touched files merge, and only lines both sides changed conflict. Then it runs the checker, which flags any new Cursor mechanism the incoming text introduced, and bumps the pin. `scripts/sync-upstream.sh --layer` prints the whole Rex layer as a diff against the pin.
