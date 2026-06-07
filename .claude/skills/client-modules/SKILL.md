---
name: client-modules
description: >-
  Use when setting up or working with Pocopine's managed .client.ts modules for importing npm SDKs (Firebase, analytics, etc.) with typed Rust facades
---

# Managed Client Modules

Use Pocopine's managed `.client.ts` modules to import npm SDKs (Firebase, Stripe, analytics) without breaking the "`.poco` is templates, `.rs` is logic" contract. The CLI owns TypeScript tooling, type-checking, and bundling; the `#[client_module]` macro reads explicit types from your `.client.ts` file and generates a typed Rust facade.

## When to use

- Importing npm packages into a Pocopine app (Firebase Auth, PostHog, Stripe, canvas libraries)
- Creating a small browser-only adapter that wraps SDK calls and returns plain JSON
- Exposing async methods or subscription callbacks from JavaScript to Rust
- Keeping SDKs decoupled from Pocopine's reactive core (no store mutations or UI rendering from client modules)

## Key API / Syntax

**File layout** — put `.client.ts` files under `src/`:
- `src/Firebase.client.ts` registers as module name `firebase`
- `src/FirebaseAuth.client.ts` registers as `firebase-auth` (kebab case)
- Module names must be unique; duplicates cause a build error

**Rust macro** — `#[pocopine::client_module(...)]`:
```rust
#[pocopine::client_module("Firebase.client.ts")]
pub mod client {
    use super::bindings::FirebaseUser;
}
```

Attributes:
- `#[pocopine::client_module("path.client.ts")]` — required file path (relative to the module)
- `#[pocopine::client_module(file = "...", name = "override")]` — explicit module name (otherwise derived from filename)

Generated facade methods (per `.client.ts` signature):
- `Module::required()` — returns `Result<Module, Error>` (fails if module not found)
- `Module::optional()` — returns `Result<Option<Module>, Error>` (graceful None)
- `module.call_async::<T>(method_name)` — call async function, get `Result<T, Error>`
- `module.subscribe::<T>(scope, method_name, handler)` — subscribe to callback-based method, auto-unsubscribe on scope drop

**TypeScript contract** — `.client.ts` default export:
```typescript
export default {
  async methodName(): Promise<ReturnType> { ... },
  onEventName(callback: (value: EventType) => void): () => void { ... },
};
```

Async methods must have explicit `Promise<T>` return type. Subscription methods must have a `callback` parameter with explicit callback type. Both convert to snake_case Rust method names (`signIn` → `sign_in`, `onAuthStateChanged` → `on_auth_state_changed`).

**Type binding** — use `pocopine-ts-rs` to generate `.ts` bindings from Rust DTOs:
```rust
#[derive(serde::Deserialize)]
#[cfg_attr(test, derive(pocopine_ts_rs::TS))]
#[cfg_attr(test, ts(export, export_to = "../src/firebase/bindings.ts"))]
#[serde(rename_all = "camelCase")]
pub struct FirebaseUser { pub token: String, pub uid: String, ... }
```

Run `cargo test -p your-app export_bindings` to refresh `bindings.ts`.

**CLI commands**:
- `pocopine js init` — create/update `package.json` with esbuild and TypeScript
- `pocopine js install` — install npm packages (respects existing lock file: pnpm/npm/yarn/bun)
- `pocopine js add firebase` — add package and update `package.json`
- `pocopine js add -D typescript@latest` — add dev dependencies
- `pocopine build` / `pocopine dev` — auto-install missing deps, type-check, bundle

## Examples

**Firebase Auth adapter** (from `examples/keep/src/firebase/`):

```typescript
// Firebase.client.ts
import { initializeApp } from "firebase/app";
import { getAuth, signInWithPopup, onAuthStateChanged } from "firebase/auth";
import type { FirebaseAuthUser } from "./bindings";

type AuthStateCallback = (user: FirebaseAuthUser | null) => void;
type Unsubscribe = () => void;

const auth = getAuth(initializeApp({ projectId: "my-project" }));

export default {
  async signIn(): Promise<FirebaseAuthUser | null> {
    const credential = await signInWithPopup(auth, provider);
    return userPayload(credential.user);
  },
  onAuthStateChanged(callback: AuthStateCallback): Unsubscribe {
    return onAuthStateChanged(auth, async (user) => {
      callback(await userPayload(user));
    });
  },
};
```

**Rust facade** (from `examples/keep/src/firebase/mod.rs`):

```rust
#[pocopine::client_module("Firebase.client.ts")]
pub mod client {
    use super::bindings::FirebaseAuthUser;
}
```

**Usage in app plugins** (from `examples/keep/src/firebase/auth.rs`):

```rust
#[cfg(target_arch = "wasm32")]
impl KeepFirebaseAuth {
    pub async fn sign_in(&self) -> Result<Option<FirebaseAuthUser>, String> {
        let module = crate::firebase::client::required()?;
        module.sign_in().await.map_err(|err| err.to_string())
    }

    pub fn subscribe(
        &self,
        scope: ScopeId,
        mut handler: impl FnMut(Result<Option<FirebaseAuthUser>, String>) + 'static,
    ) -> Result<(), String> {
        let module = crate::firebase::client::required()?;
        module.on_auth_state_changed(scope, move |result| {
            handler(result.map_err(|err| err.to_string()));
        })
    }
}
```

## Gotchas

- **No `.client.js`** — typed `.client.ts` only; untyped JS rejects at compile time (use DiscoveryPolicy::TypedOnly)
- **No JSX/TSX, no framework islands** — `.client.jsx` and `.client.tsx` are explicitly rejected
- **Module singletons** — client modules are app-wide singletons; no per-component instances
- **JSON-only return values** — async methods return serde-deserializable types; no DOM, callbacks, or side effects
- **Callback signature is strict** — subscription callbacks must have a single parameter with explicit type; `() => void` unsubscribe returns are detected by name
- **Scope-managed subscriptions** — subscriptions auto-unsubscribe when the component scope drops; do not manually call the unsubscribe function
- **camelCase to snake_case** — `signIn()` becomes `sign_in()`, `onAuthStateChanged()` becomes `on_auth_state_changed()` in Rust
- **No default exports in generated bindings.ts** — the TS file contains only type/interface declarations, not runtime values
- **build/dev watch** — `.client.ts` changes rebuild the bundle; `package.json` changes rerun install and rebundle
- **Lock file detection** — if multiple lock files exist (pnpm-lock.yaml + package-lock.json), `pocopine doctor` warns; determinism breaks

## References

- **Docs**: `/docs/client-modules.md` — contract, compilation pipeline, commands, dev mode
- **RFC**: `rfcs/rfc-037-js-bridge.md` — design, motivation, author surface (Phase 1 shipped)
- **Codegen crate**: `crates/pocopine-client-codegen/src/lib.rs` — facade extraction, discovery, and entry generation
- **Macro**: `crates/pocopine-macros/src/lib.rs` — `#[client_module]` expansion and method code generation
- **ts-rs fork**: `crates/pocopine-ts-rs/src/lib.rs` — Rust → TypeScript DTO type generation (`#[derive(TS)]`)
- **Example**: `examples/keep/src/firebase/` — complete Firebase Auth integration with CLI and store
