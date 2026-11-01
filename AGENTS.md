# pstack-rex contributor guide

This repo is [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan, adapted to Claude Code and Codex running in Rex. `UPSTREAM` pins the upstream commit it matches.

Before you edit anything under `skills/`, read [REX-NATIVE.md](./REX-NATIVE.md) in full. It is the translation contract: which Cursor mechanism becomes which Rex mechanism, how skills reference each other, where skills and the model config live, and the definition of done. [DESIGN.md](./DESIGN.md) explains the worker runtime in `skills/rex-subagents/`.

## Rules

- Keep upstream wording wherever it is harness-neutral. Change only what names a Cursor mechanism, and keep each change as small as the contract allows, so upstream syncs merge cleanly.
- Rex mechanics live in `skills/rex-subagents/`. Other skills point to it and don't restate it.
- Upstream names stay: `poteto-mode`, `poteto-help`, `setup-pstack`, role names, playbook names.
- `node scripts/check-rex-native.mjs` must exit 0. Pass skill names to check a subset.
- Script changes keep `bun test` and `bun run typecheck` green in `skills/poteto-mode/scripts`.
- `skills/rex-subagents/scripts/` stays bash 3.2 compatible, because the watcher may run it with the system bash. Re-probe Rex, Claude Code and Codex before you change a rule that rests on a fact in REX-NATIVE.md's table.
- Workers always run full access. Never add a way to pass agent flags through `subagent`.
- A delegated worker writes only the files its brief names and runs no git commands.

## Syncing upstream

Run `scripts/sync-upstream.sh` (or pass a SHA). It merges each file three ways from the pinned commit, adds and deletes what upstream added and deleted, bumps the pin, and runs the checker on the skills that changed. Resolve every conflict marker, translate each checker finding per REX-NATIVE.md, run the checker and the script tests, then commit as `sync upstream pstack <old>..<new>`. `scripts/sync-upstream.sh --layer` shows the whole Rex layer, which is the place to look when a merge is unclear.
