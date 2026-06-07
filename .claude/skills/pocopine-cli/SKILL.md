---
name: pocopine-cli
description: >-
  Use when working with the pocopine-cli: build, dev watch, run, deploy, doctor, env, js, stylekit, lsp commands
---

# Pocopine CLI

The Pocopine CLI (`pocopine` command) is the build and dev-server orchestrator for Rust/WASM full-stack Pocopine projects. It wraps `wasm-pack`, `cargo`, `tailwindcss`, and the Pine Stylekit compiler, managing the dev loop and deployment lifecycle.

## When to use

- Running a typical Pocopine dev loop: `pocopine dev` to watch for changes and auto-rebuild
- One-shot builds: `pocopine build` to compile the WASM bundle and optional server binary
- Running in production shape: `pocopine run` to build once then serve (no file watcher)
- Checking tooling and project config: `pocopine doctor` before starting work
- Managing environment variables: `pocopine env set/get/list/unset` for dev-only `.env`
- Adding npm packages for typed `.client.ts` modules: `pocopine js init/install/add`
- Compiling utility CSS: `pocopine build --no-stylekit` to skip Stylekit (RFC 092) or `--stylekit` to force it on
- Deploying to Railway/Render or other adapters: `pocopine deploy --target railway` (RFC 080)
- Editor integration: `pocopine lsp` runs the language server for the VSCode `.poco` extension

## Key API / syntax

### Project configuration

All config lives in `[package.metadata.pocopine]` in `Cargo.toml` (RFC 080 §4.1):

```toml
[package.metadata.pocopine]
bin = "server"              # Cargo bin target to spawn in dev/run (delegates serving to the bin)
worker-bin = "worker"       # Optional separate worker process (requires Redis backend)
port = 3000                 # Advisory port shown in logs (bin controls actual binding)

[package.metadata.pocopine.tailwind]
input = "app.css"           # Entry CSS (defaults to app.css)
output = "pkg/tailwind.css" # Output location
version = "latest"          # Tailwind release tag (defaults to latest)
binary = "/path/to/tailwindcss"  # Optional explicit binary path

[package.metadata.pocopine.stylekit]
input = "app.css"           # Entry CSS with @theme tokens
output = "pkg/stylekit.css" # Output location
src = "src"                 # Directory scanned for .poco sources
preflight = true            # Include reset stylesheet
enabled = true              # Opt out with enabled = false

[package.metadata.pocopine.deploy.<host>]
# Host-specific config (RFC 080 §5): owner_id, workspace_id, region, org, etc.
```

### Core verbs

- **`pocopine build`** — One-shot: compile WASM (`wasm-pack build --target web`), optional server bin, bundled client modules, Tailwind (if configured), and Pine Stylekit CSS. Flags: `--release`, `--path <crate>`, `--no-stylekit`, `--stylekit`.

- **`pocopine run`** — Build once, then serve: spawns configured server bin (if set) or serves the project directory as static files on `--port` (default 5243). Production-shape: inherits shell environment unchanged (no `.env` injection). Same build stages as `build`. Exits on server error.

- **`pocopine dev`** — Build once, start file watcher on `src/` and package manifests, then auto-rebuild + reload on changes. Loads `.env` into spawned server/worker processes (dev-only). Coalesces rapid changes over 350ms. Falls back to polling (2s interval) if inotify limit exceeded. Restarts server bin on `.rs` edits; rebundles client modules on `.client.ts` changes.

- **`pocopine doctor`** — Validate local tooling (cargo, rustc, wasm-pack, node, package managers, esbuild) and project config. Checks `Cargo.toml`, `.pocopine.toml` tool overrides, server/worker bin targets, Tailwind input file, client modules setup. Flag: `--strict` to treat warnings as failures.

- **`pocopine deploy`** — Deploy to a host adapter (RFC 080): reads `[package.metadata.pocopine.deploy]` config, builds a Docker image, and runs host-API calls. Subcommands:
  - `auth <host>` / `--list` / `--revoke <host>` — manage `~/.pocopine/credentials.toml`
  - `doctor` — check docker daemon + all configured tokens
  - `status` — show current deploy state on the target (flag: `--json`)
  - `config set/get/list/revoke` — manage `~/.pocopine/config.toml` (three-tier resolution: env / project / file)
  - Flags: `--target railway|render`, `--prod` (suffixes app name, applies `[deploy.production]` overrides), `--workspace` (deploy all members with `[package.metadata.pocopine.deploy]`), `--skip-build` (reuse prior image), `--dry-run`.

- **`pocopine js init`** — Create `package.json` with Pocopine client-module toolkit (esbuild, TypeScript, tsconfig).

- **`pocopine js install`** — Install dependencies via detected package manager (pnpm/npm/yarn/bun, auto-detected from lockfile or `.pocopine.toml`).

- **`pocopine js add <packages>`** — Add npm packages. Flag: `-D` / `--dev` for devDependencies.

- **`pocopine env set <key> [value]`** — Set or overwrite a key in `.env`. Reads from stdin if value omitted (hides secrets from shell history). Adds `.env` to `.gitignore` on first use. Key must match `[A-Za-z_][A-Za-z0-9_]*`.

- **`pocopine env get <key>`** — Print a single key's value; exit non-zero if unset.

- **`pocopine env list`** — List all keys in `.env`. Flag: `--show-values` to unmask.

- **`pocopine env unset <key>`** — Remove a key (idempotent).

- **`pocopine stylekit`** — Compile utility CSS from `.poco` sources in-process. Flags: `--dump` (print stylesheet to stdout), `--docs` (emit markdown utility catalog), `--metadata` (emit LSP metadata as JSON), `--no-stylekit` / `--stylekit` (override config).

- **`pocopine lsp`** — Run the language server on stdio (used by VSCode extension + other LSP clients). Reuses the framework's own `pocopine-template-parser` so editor diagnostics match compile-time errors.

### Build flow

1. `wasm-pack build --target web [--release | --dev]`
2. Client modules (`.client.ts` typed bundles) → `pkg/pocopine-client.js` via esbuild
3. Configured server/worker binaries via `cargo build --bin <name> [--release]`
4. Tailwind (if `[tailwind]` block) → `pkg/tailwind.css`
5. Pine Stylekit (RFC 092, on by default) → `pkg/stylekit.css`

**Dev watch (pocopine dev):**
- Initial full build
- Watches `src/` (recursive) and project root (non-recursive) for file changes
- Changes trigger selective rebuilds:
  - `.rs` in src/ → wasm + server bin
  - `.poco` in src/ → wasm only
  - `.client.ts` in src/ → client module rebundle + wasm rebuild
  - `package.json` → npm install + rebundle
  - Tailwind runs in separate watch child (`tailwindcss -w`)
  - Stylekit compiles in-process on each wasm rebuild (no watcher child)

## Examples

### Counter (minimal, no server bin)

From `/home/zempare-mambski/RustProjects/pocopine/examples/counter/`:

```rust
// src/lib.rs
use pocopine::prelude::*;
use serde::{Deserialize, Serialize};

#[derive(Default, Serialize, Deserialize)]
#[component]
pub struct Counter {
    #[prop]
    pub count: i32,
    #[prop]
    pub label: String,
}

#[handlers]
impl Counter {
    pub fn increment(&mut self) {
        self.count += 1;
    }
}

#[wasm_bindgen(start)]
pub fn main() {
    App::new().register::<Counter>().run();
}
```

```html
<!-- src/Counter.poco -->
<div>
  <p><span pp-text="count"></span> <span pp-text="label"></span></p>
  <button pp-on:click="decrement">-</button>
  <button pp-on:click="increment">+</button>
</div>
```

**Dev loop:** `pocopine dev` watches src/, recompiles WASM on edits, serves static files on http://localhost:5243.

### Blog (with server bin and worker)

From `/home/zempare-mambski/RustProjects/pocopine/examples/blog/Cargo.toml`:

```toml
[package.metadata.pocopine]
bin = "server"
worker-bin = "worker"
port = 3000

[[bin]]
name = "server"
path = "src/bin/server.rs"

[[bin]]
name = "worker"
path = "src/bin/worker.rs"
```

**Dev loop:** `pocopine dev` spawns both server and worker, watches src/, restarts them on `.rs` changes, rebuilds WASM on `.poco` changes. Environment variables from `.env` are injected into both processes.

### Firebase client module (typed `.client.ts`)

From `/home/zempare-mambski/RustProjects/pocopine/examples/keep/src/firebase/Firebase.client.ts`:

```typescript
import { initializeApp } from "firebase/app";
import { getAuth, signInWithPopup } from "firebase/auth";
import type { FirebaseAuthUser } from "./bindings";

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);

export async function signIn(): Promise<FirebaseAuthUser | null> {
  const result = await signInWithPopup(auth, provider);
  return {
    token: await result.user.getIdToken(),
    uid: result.user.uid,
  };
}
```

**Dev loop:** `pocopine js init` creates `package.json`, `pocopine js add firebase` adds the dependency, `pocopine dev` auto-bundles on `.client.ts` edits and npm install.

## Gotchas

- **`pocopine run` does NOT load `.env`** — values stay in development only. Use shell env or a secrets manager for production.
- **Stylekit runs by default (RFC 092)** — projects with only Tailwind should omit the `[stylekit]` block or set `enabled = false` to skip it. `--no-stylekit` disables it for a single build.
- **Package manager detection** — `pocopine js` auto-detects from lockfile (`pnpm-lock.yaml`, `package-lock.json`, `yarn.lock`, `bun.lock`, `bun.lockb`). Override via `[tools].package-manager` in `.pocopine.toml` or `POCOPINE_JS_PM` env var.
- **Worker process requires Redis** — `worker-bin` in separate process mode needs `POCOPINE_REDIS_URL` (or `redis://127.0.0.1/` in `pocopine dev`). For embedded workers, omit `worker-bin`.
- **Client modules require esbuild + TypeScript** — `pocopine js init` installs them; `pocopine doctor` warns if missing. TypeScript detection happens at build time; unsupported formats (`.client.js`, `.client.jsx`, `.client.tsx`) are flagged.
- **inotify fallback** — if native watcher hits the per-user file limit, falls back to polling (2s) with a stderr warning. Raise `fs.inotify.max_user_watches` on Linux to restore speed.
- **`.env` is dotenv format** — values with spaces must be quoted; multiline values are rejected by `env::set`.
- **Deploy config is RFC 080 § 4.1** — lives in `Cargo.toml` under `[package.metadata.pocopine.deploy.<host>]`. RFC notes the long-term home is a separate `Pocopine.toml`.

## References

- **Main CLI entry:** `/home/zempare-mambski/RustProjects/pocopine/crates/pocopine-cli/src/main.rs`
- **Args parsing:** `crates/pocopine-cli/src/args.rs` (clap Subcommand definitions)
- **Build stage:** `crates/pocopine-cli/src/build.rs` (wasm-pack + cargo wrapping)
- **Dev watch:** `crates/pocopine-cli/src/dev.rs` (file watcher + coalescing + selective rebuild logic)
- **Deploy:** `crates/pocopine-cli/src/deploy.rs` + `pocopine-deploy` crate (adapter pipeline)
- **Doctor:** `crates/pocopine-cli/src/doctor.rs` (tooling + config validation)
- **Client modules:** `crates/pocopine-cli/src/client_modules.rs` (esbuild bundling, `pocopine-client-codegen`)
- **Stylekit:** `crates/pocopine-cli/src/stylekit.rs` (in-process CSS compilation, RFC 092 D2/D6)
- **Environment:** `crates/pocopine-cli/src/env.rs` (dotenv parsing + dev-mode injection)
- **LSP:** `crates/pocopine-cli/src/lsp.rs` (stdio-backed language server, uses `pocopine-template-parser`)
- **RFC 080:** `/rfcs/rfc-080-deploy-contract.md` (deploy config contract, host adapters, env vars)
- **RFC 092:** `/rfcs/rfc-092-pocopine-stylekit.md` (utility-CSS compiler, `@theme` tokens, Tailwind parity)
- **Docs:** `/docs/poco/` (template format), `/docs/client-modules.md` (typed `.client.ts` modules), `/docs/pine-stylekit.md` (Stylekit reference)
