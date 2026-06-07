---
name: reactivity-and-stores
description: >-
  Use when building state management and reactivity in pocopine — understand the reactive model, App stores, and provide/inject context
---

## What This Is

Pocopine's reactivity system automatically updates templates and effects whenever component state changes. **Stores** are singleton components for global state shared across your app. **Provide/inject** enables parent components to pass context down to descendants through the scope chain.

## When to Use

- Building components with local or global state (`#[component]` struct fields, `#[store]` singletons)
- Tracking state changes automatically in templates (via the proxy's `get`/`set` traps and dependency tracking)
- Sharing data across component boundaries (App stores via `$store.<name>` in templates, `pocopine::store::<T>()` in Rust)
- Wiring parent-to-child context without tight coupling (parent `provide()`, child `inject()`)
- Writing async handlers that update state when futures complete (`dispatch!` macro or `Handle::update`)

## Key API / Syntax

### Reactivity Engine

- **`effect(f: impl Fn() + 'static)`** — Run closure; subscribe to any `(ScopeId, key)` accessed during execution. Reruns when subscribed fields change.
- **`signal(v: T) -> (Signal<T>, Setter<T>)`** — Create a typed reactive cell; split read/write pair.
- **`rw_signal(v: T) -> RwSignal<T>`** — Combined read+write handle for a reactive cell.
- **`Computed<T>`** — A derived value that auto-memoizes and updates when its source signals change.
- **`track(scope_id, key)` / `trigger(scope_id, key)`** — Low-level: manually subscribe/notify inside an effect.
- **Thread-locals**: `DEPS`, `REVERSE`, `SIGNAL_DEPS`, `SIGNAL_REVERSE`, `QUEUE`, `CLEANUPS` drive the effect engine.

### Stores

- **`#[store] struct T`** — Macro that emits a singleton `#[component]`. Accessible via `$store.<kebab-case>` in templates and `pocopine::store::<T>()` in Rust.
- **`Store` trait** — Implemented by `#[store]` macros; requires sibling `#[handlers] impl` (empty is fine).
- **`Handle<T>`** — Typed reference to a component or store scope. Use `handle.update(|s| { ... })` to mutate and trigger reactivity.
- **`pocopine::store::<T>()`** — Short-hand for `T::__handle()`. Returns a `Handle<T>` to the singleton.
- **`handle.update(f)` / `handle.with(f)`** — Mutate (reactive) or read (non-reactive) the underlying state.

### Provide / Inject

- **`ContextKey<T>`** — Opaque, unique, typed context key. Created via `create_context!` macro or `ContextKey::new("debug-name")`.
- **`provide(key: &ContextKey<T>, value: T)`** — Store `value` under `key` on the current scope; descendants can inject it.
- **`inject(key: &ContextKey<T>) -> Option<T>`** — Walk up scope-parent chain; return first matching key's value (must be `T: Clone`).
- **Scope-parent tracking** — Recorded at mount via `context::set_parent(child, parent)`. Teleported / slotted content preserves authoring parent.

### Component State

- **Local state** — Struct fields; read/write via templates and handlers.
- **Parent→child** — Attributes on child tags (static or `pp-bind:` reactive).
- **Child→parent** — `$dispatch` events captured with `pp-on:event`.
- **Async updates** — `dispatch!(server_fn(args).await, |s, result| { ... })`; expands to `spawn_local` + `Handle::update`.

## Examples

### 1. Stores (App-Wide State)

From `/home/zempare-mambisi/RustProjects/pocopine/examples/todo/src/lib.rs`:

```rust
#[derive(Serialize, Deserialize)]
#[store]
pub struct Preferences {
    pub theme: String,
}

impl Default for Preferences {
    fn default() -> Self {
        Self { theme: "light".into() }
    }
}

#[handlers]
impl Preferences {}

#[wasm_bindgen(start)]
fn main() {
    App::new()
        .register::<TodoList>()
        .store::<Preferences>()
        .run();
}
```

Template access: `<span pp-text="$store.preferences.theme"></span>`  
Rust access: `pocopine::store::<Preferences>().update(|p| p.theme = "dark".into())`

### 2. Server Functions with Async State Updates

From `/home/zempare-mambisi/RustProjects/pocopine/examples/blog/src/lib.rs`:

```rust
#[pocopine::server]
pub async fn get_post(post_id: u32) -> ServerResult<Post> {
    match post_id {
        1 => Ok(Post { id: 1, title: "Hello".into(), body: "...".into() }),
        _ => Err(ServerError::App(format!("no post {post_id}")))
    }
}

#[derive(Default, Serialize, Deserialize)]
#[component]
pub struct BlogPost {
    #[prop]
    pub post_id: u32,
    pub title: String,
    pub loading: bool,
}

#[handlers]
impl BlogPost {
    pub fn on_mount(&mut self) {
        self.loading = true;
        let post_id = self.post_id;
        dispatch!(get_post(post_id).await, |s, result| {
            s.loading = false;
            match result {
                Ok(p) => s.title = p.title,
                Err(e) => { /* handle error */ }
            }
        });
    }
}
```

### 3. Provide/Inject for Parent-Child Context

From RFC-027 pattern (root provides itself to children):

```rust
#[handlers]
impl DropdownMenuRoot {
    pub fn on_mount(&mut self) {
        pocopine::provide("dropdown-menu", pocopine::this::<Self>());
    }
}

#[handlers]
impl DropdownMenuItem {
    pub fn on_click(&mut self) {
        if let Some(menu) = pocopine::inject::<Handle<DropdownMenuRoot>>("dropdown-menu") {
            menu.update(|m| m.close());
        }
    }
}
```

## Gotchas

- **Reactivity is per-field, by name** — No nested object or array element tracking. Track only top-level fields.
- **Handler mutations trigger all keys** — `Scope::invoke` calls `trigger_scope(id)` after any handler, not per-field. Use `dispatch!` for granular updates from async.
- **Proxy serialization cost** — Every template `get` serializes through `serde_wasm_bindgen::to_value`. Hot reads should use `Signal<T>` or handle `with()` instead.
- **Stores require `#[handlers]`** — Even an empty `impl` block is mandatory alongside `#[store]`.
- **Parent-scoped provides are per-scope** — Calling `provide(key, v1)` then `provide(key, v2)` from the same scope replaces v1 inline (no stack).
- **Inject before parent-provided → None** — Children mount before parents in pre-order walk. Use `on_ready` / post-walk hooks if inject must wait.
- **Field cache invalidation** — `Handle::update` drops the entire field cache; next template proxy reads fetch fresh state from Rust.

## References

- **Crates**: `crates/pocopine-core/src/` — `reactive.rs`, `signal.rs`, `store.rs`, `context.rs`, `handle.rs`, `scope.rs`
- **RFCs**:
  - RFC-002: App builder, stores, server functions
  - RFC-027: Provide/inject parent-scope context
- **Docs**:
  - `docs/reactivity/01-current-design.md` — The five thread-locals, effect lifecycle, dependency tracking
  - `docs/reactivity/03-signals.md` — Signal types, computed, watch, on_cleanup, batch API (design sketch)
  - `docs/components/02-state.md` — Four state patterns (local, parent→child, child→parent, stores), async data with `dispatch!`
