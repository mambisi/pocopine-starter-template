# pocopine starter

A small but real [pocopine](https://github.com/mambisi/pocopine) app — a
welcome page built from a few composed components, showing props, slots,
events, reactive state, and theming. Use it as the starting point for a new
project: click **“Use this template”** on GitHub (or `git clone`), then rename
the package in `Cargo.toml` and start editing `src/WelcomeApp.poco`.

## Prerequisites

- **Rust** — the pinned nightly in `rust-toolchain.toml` is installed automatically.
- **wasm target** — `rustup target add wasm32-unknown-unknown`
- **wasm-pack** — `cargo install wasm-pack`
- **the pocopine CLI** —
  `cargo install --git https://github.com/mambisi/pocopine pocopine-cli`

Run `pocopine doctor` to check your toolchain.

## Develop

```bash
pocopine dev      # build + serve, rebuilding on change
pocopine build    # one-shot build (wasm bundle + assets)
```

Open the URL `pocopine dev` prints. Edit `src/Counter.poco` or `src/lib.rs` and
the page reloads.

## Layout

```
Cargo.toml          package + pocopine git dep + the Stylekit config
rust-toolchain.toml pinned nightly + the wasm32 target
app.css             Pine Stylekit @theme tokens (compiled to pkg/stylekit.css)
index.html          host page; links the compiled CSS, mounts <welcome-app> under [pp-app]
src/lib.rs          all #[component] structs + #[handlers] + the wasm entrypoint
src/WelcomeApp.poco the root page (hero, demo, cards) — edit me first
src/WelcomeItem.poco a card component with a title prop + default <slot>
src/Counter.poco    the interactive counter component
```

A component is a Rust struct (`#[component]`) plus a sibling `.poco` template of
the same name, registered in `main()` via `App::new().register::<T>()`. `#[prop]`
fields are seeded from host-element attributes (`<counter label="clicks">`);
`#[handlers]` methods fire from `@event` / `pp-on:` bindings; `pp-text` / `{{ … }}`
read state; `<slot>` projects child content (see `WelcomeItem`). Components
compose by tag — `WelcomeApp` renders `<counter>` and `<welcome-item>`.

Styling uses **Pine Stylekit** (RFC-092): utility classes (`flex`, `p-4`,
`bg-card`, `rounded-lg`, `hover:bg-ink-10`, …) in the templates compile against
the `@theme` tokens in `app.css` to `pkg/stylekit.css`, which `index.html` links.
Rebrand by editing the tokens. (Prefer scoped CSS instead? Drop the
`[package.metadata.pocopine.stylekit]` block and use `#[component(style = "Foo.css")]`.)

## Editor support

Install the **Poco LSP** VS Code extension (`pocopine.vscode-poco`) for `.poco`
syntax highlighting, completion, diagnostics, hover, and goto-definition. This
repo recommends it via `.vscode/extensions.json`.

## AI agents

This template ships the pocopine framework's feature guides as Claude Code
skills in `.claude/skills/` — one per feature (components, templates, directives,
routing, server functions, styling, auth, storage, sync, and more). An agent
working in your project picks them up automatically; see
`.claude/skills/README.md` for the index, and `AGENTS.md` for conventions.

## License

MIT — see `LICENSE`.
