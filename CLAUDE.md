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

## Critical skills

Consult the matching `.claude/skills/` guide **before** touching that area:

| Working on…                                              | Skill                                          |
| -------------------------------------------------------- | ---------------------------------------------- |
| App architecture / turning a design into components      | `reactivity-and-stores`, `pocopine-components` |
| Utility classes, `@theme` tokens, theming                | `pine-stylekit`                                |
| `<pine-icon>` / icon registration                        | `pine-icons`                                   |
| `.poco` markup, single-root, SVG                         | `poco-templates`                               |
| `pp-*` directives, `:data-*`, `@event`                   | `poco-directives`                              |
| `{{ }}`, `$store`, ternary (no arithmetic in templates)  | `poco-expressions`                             |
| `<slot>`, composition, `uses`                            | `slots-and-composition`                        |

## Building from a design

Turning a design (Claude Design or any mockup) into an app? Shape it
**store-centric** with layout/leaf components and Stylekit theming — see the
**"Shaping a real app"** and **"From a design to an app"** sections in
[`AGENTS.md`](./AGENTS.md), plus the gotchas there (notably `text-[#hex]` →
font-size, and that custom child tags need `uses`).

## Working here

- Dev loop: `just dev` / `just check` / `just fmt` (see `AGENTS.md` for all).
  After editing a `.poco` or its `#[component]`, run `just check` before moving on.
- Keep one root element per template; register new components + their icons in
  `main()`; prefer Pine Stylekit utilities over hand-written CSS.
- **Verify rendered output, not just compile** — serve and screenshot (flip
  themes) to catch Stylekit/theme/layout bugs `just check` can't.
