# CLAUDE.md

Guidance for Claude Code (claude.ai/code) working in this pocopine app.

**Start with [`AGENTS.md`](./AGENTS.md)** — it covers the framework model, the
`just` task runner, and the project conventions. Everything there applies here.

## Skills

This project uses the pocopine framework's feature guides as Claude Code skills
in `.claude/skills/` — one per feature (components, templates, directives,
routing, server functions, styling, auth, storage, sync, …). They are picked up
automatically; consult the relevant one before changing that area of the code.

The guides are **living**: they evolve in their own repo, so keep them current —
- `pocopine skills install` if `.claude/skills/` is empty,
- `pocopine skills check` to see if newer guides exist, then
- `pocopine skills update` (or `just skills`) to refetch the latest.

## Working here

- Use `just` recipes for the dev loop (`just dev`, `just check`, `just fmt`) —
  see `AGENTS.md` for the full list.
- After editing a `.poco` template or its `#[component]`, run `just check` to
  confirm it still compiles before moving on.
- Keep one root element per template, register new components in `main()`, and
  prefer Pine Stylekit utility classes over hand-written CSS.
