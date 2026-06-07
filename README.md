# pocopine starter

A minimal [pocopine](https://github.com/mambisi/pocopine) app: one `#[component]`
(Rust) paired with a `.poco` template. Use it as the starting point for a new
project — click **“Use this template”** on GitHub (or `git clone`), then rename
the package in `Cargo.toml`.

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
Cargo.toml          package + the pocopine git dependency
rust-toolchain.toml pinned nightly + the wasm32 target
index.html          host page; mounts <counter> under [pp-app]
src/lib.rs          the #[component] struct + #[handlers] impl
src/Counter.poco    its template (paired to the struct by filename)
```

A component is a Rust struct (`#[component]`) plus a sibling `.poco` template of
the same name. `#[prop]` fields can be seeded from host-element attributes;
`#[handlers]` methods are called from `pp-on:`/`@` events; `pp-text`/`{{ … }}`
read state.

## Editor support

Install the **Poco LSP** VS Code extension (`pocopine.vscode-poco`) for `.poco`
syntax highlighting, completion, diagnostics, hover, and goto-definition. This
repo recommends it via `.vscode/extensions.json`.

## License

MIT — see `LICENSE`.
