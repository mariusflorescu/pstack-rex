# pstack for Rex

> **Moved to [mariusflorescu/the-kit](https://github.com/mariusflorescu/the-kit).** pstack-rex now lives there in `plugins/pstack-rex/`, with its full history, next to thermos-rex. This repo is archived and gets no more updates. Install from the kit with `npx skills add mariusflorescu/the-kit/plugins/pstack-rex -g -a claude-code -a codex -s '*' -y`.

pstack is an engineering skill library for coding agents. Lauren Tan ([poteto](https://x.com/poteto)) wrote it for Cursor: one mode skill that routes every task to a playbook, principles that ground each decision, and verification strict enough to parallelize with confidence. This repo ships it to Claude Code and Codex running in [Rex](https://www.superlogical.com/rex), Superlogical's terminal multiplexer, as 60 skills. Every subagent a skill spawns opens as its own Claude Code or Codex agent in a Rex pane to the right of yours, and you get woken when it finishes or gets stuck.

```
┌────────────────────┬────────────────────┐
│                    │ interrogate claude │
│                    ├────────────────────┤
│   your agent       │ interrogate codex  │
│ (Claude or Codex)  ├────────────────────┤
│                    │ watch PR 123       │
└────────────────────┴────────────────────┘
```

## Install

```bash
npx skills add mariusflorescu/pstack-rex -g -a claude-code -a codex -s '*' -y
```

This puts one copy of each skill in `~/.agents/skills/` (Codex reads it there) and a symlink in `~/.claude/skills/` (Claude Code reads it there). Refresh just this pack by running that command again. `npx skills update -g` also works, but it updates every globally installed skill, not only pstack's. Install globally or per project, not both: when a skill name exists in both `~/.agents/skills` and a project's `.agents/skills`, Codex resolves neither on `$<name>`.

You also need Rex, `jq`, `gh` (the only forge pstack uses), `perl` (macOS has it), and [Bun](https://bun.sh) for the `watch-pr` script.

## Get started

1. Open Rex, start `claude` or `codex` in a pane, and work there as usual.
2. Run `/setup-pstack` once. It lists the models each harness can run (Codex from its model cache, Claude Code's `opus`, `sonnet`, `haiku` and `fable` aliases, each probed with one tiny request), asks for a reasoning budget, and writes `~/.config/pstack/pstack-models.md`: one `role: claude/<model> (<effort>)` or `role: codex/<model> (<effort>)` line per pstack role. A pstack-t3 file keeps working.
3. Use `/poteto-mode` for anything that needs rigor. It picks one of 23 playbooks and runs the other skills as the steps need them.
4. Stuck, or unsure which skill fits? Ask `/poteto-help`.

Codex runs every skill as `$<name>` where this README and the skills write `/<name>`.

## How it works in Rex

- **Workers are panes.** A skill spawns a subagent with `subagent spawn` from the bundled `rex-subagents` skill. The first worker splits your pane to the right, later ones stack in that column (three per column, then a new column). Each pane is labelled with the role (`interrogate codex`), and the agent's conversation carries the same name. You can watch any worker, click in, or type to it.
- **Mixed panels.** A role line can name `claude` or `codex`, so `/interrogate`, `/arena` and `/architect` put both harnesses on the same diff, whichever one you run.
- **Always full access.** Claude workers run with `--dangerously-skip-permissions`, Codex workers with `--dangerously-bypass-approvals-and-sandbox`. The CLI passes no agent flags, so nothing can change that. Claude runs on your main account (`~/.claude`) and Codex on the model in `~/.codex/config.toml` unless a role says otherwise.
- **Wake-ups, not polling.** A watcher (`rex do` with a Lua script) hears each worker through Rex's Program Status events. When one finishes (its last line is `TASK STATUS: done|blocked|needs-review`), blocks on a dialog, errors, or exits, a one-line `[pstack-rex] ...` message lands in your agent's chat: typed into Claude Code's pane, or queued to Codex with `codex queue`. The agent reads the report from the worker's own transcript and carries on.
- **Worktrees.** A writer that needs its own tree gets `--worktree <branch>`. If `~/.claude/settings.json` has a `WorktreeCreate` hook, it names the folder, else it lands in `<repo>/.claude/worktrees/`.
- **PR watches and timers.** `subagent run -- <command>` runs a command in a worker pane and wakes the agent when it exits. Babysit runs upstream's `watch-pr` poller that way, and long programs use `sleep 3600` as an hourly tick.
- **Past conversations.** `/recall`, `/reflect`, `/automate-me` and session pickup read your Claude Code transcripts and Codex rollouts through `rex-subagents/scripts/sessions`.
- **Both harnesses.** Almost every skill is user-only: `disable-model-invocation` hides it on Claude Code and `agents/openai.yaml` hides it on Codex. Skills reach each other by reading `../<name>/SKILL.md` from their own directory, and a brief hands a worker the absolute path of any skill it must follow.

[DESIGN.md](./DESIGN.md) explains the runtime and what was probed to build it. [REX-NATIVE.md](./REX-NATIVE.md) is the contract that maps every Cursor mechanism upstream uses to its Rex equivalent. `node scripts/check-rex-native.mjs` enforces it.

## Driving workers yourself

The CLI works from any agent or shell in a Rex pane:

```bash
S=~/.agents/skills/rex-subagents/scripts/subagent
$S spawn --name "review codex" --agent codex --brief-text "Review the diff on this branch for bugs."
$S status                 # every worker of this pane
$S result review-codex    # its final report
$S say review-codex "Also check the tests."
$S close --all
```

## Skills

`/poteto-mode` runs most of these for you when a step needs them. The table is for when you want one directly.

| Skill | Use it when |
|---|---|
| `/poteto-mode` | Default entry point for any non-trivial task. |
| `/poteto-help` | You're new to pstack, or unsure which skill, playbook, or principle fits. |
| `/setup-pstack` | You want to pick which models pstack uses per role. |
| `/in-your-own-words` | You want the agent to play back your goal and the problem before it starts. |
| `/sharpen` | You want a prompt rewritten deeper, not bigger, before you send it. It returns the prompt and doesn't do the task. |
| `/how` | You want a walkthrough of how a subsystem works. |
| `/why` | You want to know why something was built this way, from every evidence source your MCP tools reach. |
| `/recall` | You're starting or resuming work and want your recent context rebuilt from your own conversations. |
| `/ketchup` | You want what changed in this chat since your last message, in a few plain sentences and small visuals, with just enough context on each action item to make the call. |
| `/ketchup-video` | You want a `/ketchup` catch-up as a short silent video of slides, with the waiting calls as text under it. |
| `/blast-radius` | A small-looking change might break something else, and you want the safety fact proven by running code. |
| `/architect` | You're about to write code that crosses a function boundary and want its shape settled first. |
| `/arena` | You want N parallel attempts at the same thing, then the best parts of each. |
| `/swarm` | You want N parallel workers across slices or races, then one report. |
| `/interrogate` | You have a diff and want different models to try to break it. |
| `/automate-me` | You want your own `-mode` skill, drafted from how you've actually worked. |
| `/make-bot-ui` | You want a page whose buttons wake your agent in its Rex pane. |
| `/reflect` | A long task landed and you want the recipe captured as a skill edit. |
| `/correct` | You keep correcting agents for the same mistakes and want each fixed at the highest level that works. |
| `/teach` | You want to actually understand a change or subsystem. |
| `/tdd` | You're fixing a bug and there's a cheap local test path. |
| `/benchmark-checklist` | You measured a speedup or regression and need to vet the number. |
| `/no-comments` | Strip comments before review. Spawns Comment Sicko. |
| `/deslop` | Remove AI code slop from the branch before you commit. |
| `/typescript-best-practices` | You're reading or editing TypeScript. Loads on its own for `.ts` and `.tsx` files. |
| `/figure-it-out` | No bundled playbook fits. Designs a rigorous playbook for the task. |
| `/show-me-your-work` | You want a reviewable decision trail. |
| `/create-verification-skill` | Your project has no scripted way to prove app behavior. |
| `/maintain-verification-skill` | Your verify skill's feature map has drifted from the app. |
| `/create-formal-verification-skill` | You want a race, invariant, or other property that tests rarely reach formally verified, with a project-local skill to recheck it. |
| `/maintain-formal-verification-skill` | The code a formal verification covers changed, and you want it back in line and each failure called drift or a bug. |
| `/statechart` | You want how a system moves between states drawn as a chart checked by a TLA+ model, with the shortest path to each state that breaks a rule. |
| `/unslop` | You're cleaning up writing. |
| `/bro` | You want the last message restated in plain language. |
| `/technical-writing` | Docs, RFCs, readmes, PR descriptions, commit messages. |
| `/rex-subagents` | You want to read how workers, wake-ups and PR watches work in Rex. The other skills use it. |

The 24 `principle-*` skills are indexed inside `poteto-mode` and read by the other skills by name.

## Differences from upstream

- Every Cursor mechanism is swapped for its Rex equivalent per [REX-NATIVE.md](./REX-NATIVE.md). Everything else keeps upstream's wording.
- `skills/rex-subagents/` is new: the worker CLI, the watcher, and the transcript reader.
- The model config is a plain file at `~/.config/pstack/pstack-models.md` instead of a Cursor rule.
- `watch-pr` is upstream's poller, unchanged. It runs in a worker pane, so its exit is the wake-up.
- `make-bot-ui` wakes the agent's pane through a local server instead of a Cursor webhook routine.
- `deslop` is bundled from `cursor-team-kit`. The `poteto-agent` and Comment Sicko briefs live in the skills that use them.
- Not ported: the benny Slack automations, the Cursor guide in `docs/`, and the Cursor plugin manifest.

## Staying current with upstream

`UPSTREAM` pins the upstream commit this port matches and maps upstream paths to this repo. `scripts/sync-upstream.sh` merges upstream from the pin to its latest commit (or a given SHA), file by file: files the port never touched fast-forward, and only lines both sides changed conflict. It then runs the checker on the skills that changed, so new upstream text that names a Cursor mechanism gets translated per REX-NATIVE.md. `scripts/sync-upstream.sh --status` lists upstream commits since the pin, and `--layer` prints the whole Rex layer as one diff. [AGENTS.md](./AGENTS.md) holds the rules for agents doing this.

## Credit

Adapted from [cursor/plugins pstack](https://github.com/cursor/plugins/tree/main/pstack) by [Lauren Tan](https://x.com/poteto). `skills/deslop` comes from cursor/plugins `cursor-team-kit`. This port is not affiliated with Cursor, Superlogical, or the pstack author. The worker runtime borrows ideas from [pstack-t3](https://github.com/mariusflorescu/pstack-t3).

## License

MIT. [LICENSE](./LICENSE) keeps the upstream copyright notices.
