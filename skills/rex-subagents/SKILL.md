---
name: rex-subagents
description: How pstack runs subagents in Rex. Every subagent is a Claude Code or Codex agent in a Rex pane to the right of the main agent, and a watcher wakes the main agent when one finishes or gets stuck. Read by the other pstack skills whenever they spawn, wait on, steer, or close a subagent, or wait on a long command.
disable-model-invocation: true
---

# Rex subagents

You are the main agent. Every subagent a pstack skill spawns runs as its own Claude Code or Codex agent in a Rex pane to the right of yours, in your tab. The user can watch any of them and click in. A watcher hears each worker through Rex and wakes you when it finishes, blocks, fails, or exits. Never use your harness's built-in subagents for pstack work (Claude Code's Agent tool, Codex's own agents): they don't get panes, models from `~/.config/pstack/pstack-models.md`, or the wake-up.

The CLI is `scripts/subagent` in this skill's directory, the one your harness gave when it loaded this file, else `~/.claude/skills/rex-subagents/` on Claude Code and `~/.agents/skills/rex-subagents/` on Codex. Call it by absolute path. `$SUB` below stands for that path. Every command prints JSON.

## Spawn

```sh
$SUB spawn --name "interrogate codex" --entry "codex/<model> (xhigh)" --brief /tmp/brief-codex.md
$SUB spawn --name "swarm slice 2" --agent claude --model <model> --effort high --brief-text "..."
$SUB spawn --name "arena b" --entry "claude/<model> (xhigh)" --worktree <branch> --brief /tmp/arena.md
```

- **Write the brief to a file** and pass `--brief`. The worker gets only the brief: the goal, absolute paths, constraints, the report format, and whether it may delegate further. `subagent` appends the report contract (a final message with the full report and a `TASK STATUS: done|blocked|needs-review` line).
- **`--name`** labels the pane and names the conversation. Name the skill and the role (`why investigator 2`). The JSON's `id` is the kebab-case name, and every other command takes it.
- **Models.** `--entry` takes a line entry from `~/.config/pstack/pstack-models.md` as written: `claude/<model> (<effort>)`, `codex/<model> (<effort>)`, `claudeAgent/...` (read as `claude`), or `inherit-parent`/`auto` (your own harness on its default model). Or pass `--agent claude|codex` with optional `--model` and `--effort low|medium|high|xhigh|max`. With neither, the worker runs your own harness on its default model: Claude Code on the main account's default, Codex on `~/.codex/config.toml`'s.
- **`--read-only`** adds "read-only: inspect only, no writes, no git commands." to the brief.
- **`--worktree <branch>`** gives a writer its own tree, from `--base` (default `HEAD`). Commit first: uncommitted edits don't reach a new worktree. Name the branch by the repository's convention. One writer per worktree or branch. Without it, workers share your checkout, so parallel writers there own disjoint files and run no git commands.
- **Spawn a fan-out in one turn**, one `spawn` call per worker. Each takes a few seconds.
- **Permissions are fixed.** Claude runs with `--dangerously-skip-permissions`, Codex with `--dangerously-bypass-approvals-and-sandbox`. `subagent` takes no agent flags, so nothing can change that.
- **`ok: false`** names a `reason`: `trust_dialog` (a folder outside your repository), `startup_dialog`, `no_status_after_60s`, `main_pane_unknown`, `rex_failed`. The `dialog` field shows the pane's last lines. Fix the cause and spawn again, or tell the user.

## Wait

After spawning, say in one line what you are waiting for and **end your turn**. Don't poll, sleep, or loop on `status`. When a worker finishes, blocks, errors, or exits, a line arrives as your next message:

```
[pstack-rex] interrogate-codex finished (TASK STATUS: done). 1 of 3 workers still running. Read a report: ... result <id>. All workers: ... status
```

- **Finished**: read the report with `$SUB result <id>` (the worker's final message, from its own transcript). Then wait for the rest, or move on.
- **Stopped without a TASK STATUS line**: the worker went quiet for 45s mid-task. Read its result and its pane (`rex capture -s <session> -b <block_id> --trim | tail -40`) and steer it or replace it.
- **Blocked**: it waits on a dialog or a question. Answer a dialog with `$SUB answer <id> <option number>`, or reply with `$SUB say <id> "<text>"`. Ask the user only when the brief and the context can't answer it.
- **Error, exited, closed**: read its pane, then spawn a fresh worker with consolidated scope, or record the dropout.
- `$SUB status` lists every worker of yours with its state and TASK STATUS. Use it after a wake-up that names several workers, or to rebuild context.
- `$SUB wait [--for 30m]` blocks until the next wake-up line and prints it. Use it only when you must have a result inside the current turn. While it runs, the line goes to it instead of to your chat.

## Steer, reuse, close

- **Fresh by default.** A fix round, follow-up, or retry is a new `spawn` with consolidated scope: the original brief, every later directive, the prior report and branch.
- **`$SUB say <id> "<text>"`** (or `--file F`) sends a follow-up to a worker that holds state you need: its worktree, uncommitted changes, a dev server it runs. Codex gets it through `codex queue`, Claude as typed input. Its next turn wakes you again.
- **`$SUB close <id>...`** when you have read a worker's report and need nothing else from it. `close --all` closes all of yours. Add `--remove-worktree` once a worktree's branch is pushed or merged: it refuses a dirty tree without `--force`, and deletes the branch only when it's merged. Close finished workers before a new fan-out, so the column stays readable.

## Long commands

`$SUB run --name "<label>" -- <command> [args...]` runs a plain command in a worker pane and wakes you when it exits, with its exit code. `$SUB result <id>` prints the end of its output. Use it for anything you would otherwise poll: a PR watch (`<poteto-mode dir>/scripts/watch-pr/watch-pr ...`), a long test or build, a timer (`sleep 3600` for an hourly cadence). Close it after reading.

## Other commands

- `$SUB models [--probe-claude]` lists what a worker can run: Codex models and efforts from its model cache, Claude Code's model aliases. `/setup-pstack` uses it.
- `$SUB whoami` prints your pane and records it. `$SUB poke --main <block> '<text>'` wakes that pane from outside, for a local page's server (`make-bot-ui`).
- If `subagent` can't find your pane (`main_pane_unknown`), set `PSTACK_REX_MAIN_BLOCK` to your block id and run it again.

## What you own

You own every worker's work. Read the diff or the evidence, not only the report, and write your own summary. Each worker's pane, conversation, worktree and branch are yours to clean up before you report back.
