# Agent guide

This is a [pocopine](https://github.com/mambisi/pocopine) app — reactive Rust
compiled to WebAssembly. A **component** is a `#[component]` struct paired with a
same-named `.poco` template (`Counter` ⇄ `src/Counter.poco`).

## Commands

This project uses [`just`](https://github.com/casey/just) as the task runner —
run `just` to list recipes. The common ones:

| Recipe        | What it does                                  |
| ------------- | --------------------------------------------- |
| `just dev`    | build + serve with live reload (everyday loop)|
| `just build`  | release build — wasm bundle + Pine Stylekit CSS|
| `just serve`  | serve the built app                           |
| `just check`  | `cargo check` (no wasm build)                 |
| `just fmt`    | `cargo fmt`                                   |
| `just doctor` | check the local toolchain + project config    |
| `just setup`  | one-time: add the wasm target + wasm-pack     |
| `just skills` | refresh the agent guides in `.claude/skills/` |

(All wrap the `pocopine` CLI; you can call it directly too — `pocopine dev`.)

## Conventions

- **Register** every component in `main()` via `App::new().register::<T>()`.
- `#[prop]` fields are seeded from host-element attributes
  (`<counter label="clicks">`); `#[model]`/state fields are reactive.
- `#[handlers]` methods fire from `@event` / `pp-on:` bindings.
- A `.poco` template needs a **single root element** (RFC-045).
- Interpolate with `{{ expr }}` (RFC-040) or `pp-text="expr"`; `<slot>` projects
  child content.
- Styling is **Pine Stylekit** (RFC-092): utility classes (`flex`, `p-4`,
  `bg-card`, `rounded-lg`, `hover:bg-ink-10`) backed by `@theme` tokens in
  `app.css`, compiled to `pkg/stylekit.css`.
- The `pp-init` / `pp-cloak` / `pp-data` directives were **removed** (RFC-063) —
  don't reach for them.

## Framework knowledge

Detailed, per-feature guides live in `.claude/skills/` — one skill per feature
(components, templates, directives, routing, server functions, styling, auth,
storage, sync, and more). Read the relevant skill before working on that area;
`.claude/skills/README.md` is the index.

The guides are **living** — they evolve in the
[`pocopine-skills`](https://github.com/mambisi/pocopine-skills) repo, separately
from any framework release:

- `pocopine skills install` — fetch the guides into `.claude/skills/` (if empty).
- `pocopine skills check` — see whether newer guides are available.
- `pocopine skills update` — refetch the latest (`just skills`); run it when
  `check` reports an update.
