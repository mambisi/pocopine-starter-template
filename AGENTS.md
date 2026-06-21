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

## Shaping a real app (beyond the demo)

The `Counter` / `WelcomeApp` files are a throwaway demo — delete them once you
start. For anything past a toy (e.g. an app built from a design) structure it
**store-centric**, the way the upstream `keep` example does:

- **One `#[store]` singleton owns shared state.** Read it in templates as
  `$store.<name>.<field>`; mutate from a component handler via
  `pocopine::store::<MyStore>().update(|s| s.action(...))`. Keep derived/display
  state as plain fields recomputed by a `rebuild()` the store calls at the end of
  each action (or as `#[computed]` fields). → skill: `reactivity-and-stores`.
- **Components are layout or leaf.** Layout/shell components compose children and
  read `$store`; leaf components are presentational — a `#[prop]` struct passed
  with `pp-bind:prop="value"` and/or `$store` reads, plus thin handlers that
  forward to the store. → skills: `pocopine-components`, `slots-and-composition`.
- **`#[component(display = "contents")]`** makes a component's inner root govern
  the parent's flex/grid layout — use it for any component that's a layout child.
- **`uses` is mandatory** for child custom tags: list every `<my-child>` /
  `<pine-icon>` / `<pine-splitter-*>` a template renders in
  `#[component(uses = [..])]`, or the macro errors.
- Organize by area: `src/model.rs`, `src/store/`, and
  `src/components/<area>/<Name>.{poco,rs}`; register everything in `main()`.

## From a design to an app

Importing a design (e.g. via the Claude Design / `claude_design` MCP, or any
mockup):

1. **Translate, don't transcribe.** Map the design's regions onto the store +
   layout/leaf components above. Don't port one giant component or inline styles
   verbatim.
2. **Theme via tokens.** Lift the palette into `app.css` `@theme` as `--color-*`
   tokens with `[data-theme="…"]` overrides; utilities compile to
   `var(--color-NAME)`, so a single `:data-theme` on the root re-skins everything.
   Convert static inline styles to utility classes; toggle state with
   `:data-active="expr"` + `data-[active=true]:…` variants; keep only genuinely
   runtime values (e.g. a per-row colour) as inline `:style`.
3. **Reuse Pine UI.** Icons → `<pine-icon>` (skill: `pine-icons`); resizable
   regions → `<pine-splitter-*>` from `pine-ui`; reach for existing components
   before hand-rolling.
4. **Verify what renders, not just that it compiles** (below).

## Gotchas that bite

- **`text-[#hex]` compiles to FONT-SIZE, not colour** — Stylekit emits
  `font-size:#fff` and the colour silently never applies (text falls back to the
  inherited colour). Define a `@theme --color-NAME` token and use `text-NAME`.
  `bg-[#hex]` / `border-[#hex]` are unambiguous and fine.
- **Only statically-literal class names are emitted** — never build a class name
  by string concatenation; toggle with `:data-*` + variants.
- **Templates read; Rust computes.** No arithmetic / method calls in `{{ }}` or
  directive expressions — derive in Rust (`#[computed]` or a store `rebuild()`).
- **Custom child tags need `uses`** (see above).

## Verifying changes

`just check` only proves the code compiles — Stylekit / theme / layout bugs only
surface at runtime. Build, `just serve` (→ `localhost:5243`), and screenshot the
running app (e.g. headless `google-chrome` driven by `playwright`); flip themes to
confirm each one reskins.

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
