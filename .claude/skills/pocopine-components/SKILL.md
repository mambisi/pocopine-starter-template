---
name: pocopine-components
description: >-
  Use when defining, structuring, or debugging pocopine Components — the #[component] and #[handlers] macros, #[prop]/#[model] fields, templates, lifecycle hooks, and component composition patterns.
---

## What this is

Pocopine Components are Rust structs + `.poco` templates + optional `.css` stylesheets, orchestrated by the `#[component]` and `#[handlers]` macros. They form the entire authoring model for the pocopine framework — composition is tag-based (kebab-case), state flows via props and stores, and lifecycle happens in `on_setup`, `on_mount`, `on_ready`, and `on_unmount` hooks.

## When to use

When you're:
- Declaring a new component with `#[component]`/`#[handlers]`
- Organizing state into `#[prop]` (parent-facing), `#[model]` (two-way), or plain fields
- Wiring props from parent to child via attributes or `pp-bind:`
- Implementing lifecycle hooks (`on_setup`, `on_mount`, `on_ready`, `on_unmount`)
- Composing components via custom tags in `.poco` templates
- Debugging prop application, state isolation, or scope behavior
- Using computed fields or watching field changes
- Structuring files per the naming convention (`.poco`, `.css` pairing)

## Key API / syntax

**Macros & derives:**
- `#[component]` — struct annotation; auto-derives name, template, style paths. Attributes: `name`, `template`, `template_inline`, `style`, `role`, `display`, `transition`, `transition_in`, `transition_out`, `animate`, `uses`, `extends`.
- `#[handlers]` — impl-block annotation; generates handler dispatch and lifecycle forwarding. Optional per-method annotations: `#[on_setup]`, `#[on_mount]`, `#[on_ready]`, `#[on_unmount]`.
- `#[prop]` — field attribute; marks a field as part of the parent contract (settable via HTML attrs). Optional args: `flatten = [...]` for nested props.
- `#[model]` — field attribute; enables two-way binding via `pp-model:field` in templates.
- `#[observe(KEY, via = ...)]` — field attribute; mirror a parent's injected field (RFC-036).
- `#[computed]` — method attribute; create a synthetic readonly field from a method.
- `#[watch(field_name, mode = "...")]` — method attribute; react to field changes (pending finalization per RFC-026).
- `#[store]` — struct annotation; singleton app-wide state; access via `$store.name`.

**Traits:**
- `ComponentState` — generated trait; `get(key)`, `set(key, val)`, `keys()`, `invoke(key, args)`, `setup()`, `mount()`, `on_ready()`, `unmount()`.
- `HandlerDispatch` — generated trait; `invoke_handler(key, args)`, `setup()`, `mount()`, `on_ready()`, `unmount()`, `has_setup()`, `has_on_mount()`, etc.

**Runtime:**
- `App::new().register::<T>().run()` — register components and start the app (wasm_bindgen entry point).
- `App::new().store::<S>().run()` — register a store singleton.
- `pocopine::this::<Self>()` — get the current scope in a method context.
- `$store.<name>` — magic path to access a global store in templates.

**Attributes & values:**
- `pp-data="name"` — component identity; injected by macro into template root (author omits it).
- `pp-on:event="handler"` — bind event to a handler method.
- `pp-bind:attr="field"` — reactive prop binding (parent field → child struct field).
- `pp-model:field="field"` — two-way binding (for `#[model]` fields).
- `pp-text="field"` — text node binding.
- `pp-show="expr"` — conditional visibility.

**File naming:**
- `.rs` module file — one or more component structs, helper types, handlers.
- `.poco` — template, one per component, named `<StructName>.poco` (PascalCase).
- `.css` — stylesheet, one per component (optional), named `<StructName>.css`; scoped by default.
- Layout: `src/components/counter.rs`, `Counter.poco`, `Counter.css` (or group related: `todo.rs`, `TodoList.poco`, `TodoItem.poco`).

## Examples

**Minimal component (Counter):**

```rust
// examples/counter/src/lib.rs
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
    pub fn on_mount(&mut self) {
        if self.label.is_empty() {
            self.label = "clicks".into();
        }
    }

    pub fn increment(&mut self) {
        self.count += 1;
    }

    pub fn decrement(&mut self) {
        self.count -= 1;
    }
}

#[wasm_bindgen(start)]
pub fn main() {
    App::new().register::<Counter>().run();
}
```

Template (`Counter.poco`):
```html
<div>
  <p>
    <span class="count" pp-text="count"></span>
    <span pp-text="label"></span>
  </p>
  <button pp-on:click="decrement">-</button>
  <button pp-on:click="increment">+</button>
  <button pp-on:click="reset">reset</button>
</div>
```

**Composition with props and slots (Todo):**

```rust
// examples/todo/src/lib.rs — multiple components
#[derive(Default, Serialize, Deserialize)]
#[component]
pub struct TodoList {
    pub title: String,
    pub current_label: String,
}

#[handlers]
impl TodoList {
    pub fn on_mount(&mut self) {
        if self.title.is_empty() {
            self.title = "Things to do".into();
        }
    }
}

#[derive(Default, Serialize, Deserialize)]
#[component]
pub struct TodoItem {
    #[prop]
    pub id: i32,
    #[prop]
    pub label: String,
    #[prop]
    pub done: bool,
}

#[handlers]
impl TodoItem {
    pub fn toggle(&mut self) {
        self.done = !self.done;
    }
}

#[wasm_bindgen(start)]
pub fn main() {
    App::new()
        .register::<TodoList>()
        .register::<TodoItem>()
        .run();
}
```

Parent template (`TodoList.poco`):
```html
<div>
  <h2 pp-text="title"></h2>
  <ul>
    <todo-item id="1" label="Buy milk"><em> (groceries)</em></todo-item>
    <todo-item pp-bind:id="current.id" pp-bind:label="current_label">
      <em> (live via pp-bind)</em>
    </todo-item>
  </ul>
</div>
```

Child template (`TodoItem.poco`):
```html
<li>
  <input type="checkbox" pp-model="done" />
  <strong pp-text="label"></strong>
  <slot></slot>
  <button pp-on:click="toggle">toggle</button>
</li>
```

## Gotchas

- **Required derives:** `#[component]` requires `#[derive(Default, Serialize, Deserialize)]` on the struct. Both are non-negotiable for the macro and proxy machinery.
- **All state is `pub`:** Only public fields are accessible from templates. Private fields vanish from the proxy and cannot be data-bound.
- **`#[prop]` fields are explicit:** By default, fields are internal state (parent can't write them). Mark fields with `#[prop]` to allow parent attributes to set them. RFC-031 distinguishes props (parent contract) from state (internal).
- **Templates lack `pp-data`:** The macro injects `pp-data="component-name"` into the `.poco` root; author templates omit it. Collision with HTML elements (e.g., `Button` struct) is rejected at compile time.
- **Single root element per template:** `.poco` files must have exactly one top-level element; comments and text don't count. The parser emits a compile error with source-file annotation if violated.
- **Props are one-way parent → child:** Children cannot write props back to the parent. Use `pp-on:event` / `$dispatch` for child-to-parent signals or `pp-model:` for controlled two-way binding.
- **Lifecycle hook order:** `on_setup` (before template walk), `on_mount` (after subtree bound), `on_ready` (scheduled post-mount on `tick::next`), `on_unmount` (before teardown).
- **Slots are default only:** v0 supports one unnamed `<slot>` per template. Named slots and `pp-for` iteration are deferred (gated by reactivity features).
- **Handler methods take `&mut self`:** Current milestone doesn't support event parameters; read state directly from fields. Event/arg support is RFC-008 (future).
- **Template attribute values are bare identifiers:** No Rust expressions in `pp-*` values yet (`pp-text="field.subfield"` not valid). Use `#[computed]` methods for derived reads.
- **Component tag name is auto-kebab-cased:** `Counter` → `<counter>`, `TodoItem` → `<todo-item>`. Override with `#[component(name = "...")]` if needed (e.g., to avoid HTML collision).
- **Store access is `$store.<field_name>`:** The magic `$store` path in templates reads the singleton; no `#[store]` instance is ever constructed by user code.

## References

**Crates:**
- `pocopine-macros` — `#[component]`, `#[handlers]`, `#[prop]`, `#[model]`, `#[computed]`, `#[store]` macros.
- `pocopine-core` — `ComponentState`, `HandlerDispatch`, `Scope`, scope lifecycle, proxy bridge.

**RFCs:**
- RFC-001 — Components (core spec, state tiers, file layout, template format, slots, lifecycle).
- RFC-031 — Prop vs state (distinguishes `#[prop]` explicit fields from internal state).
- RFC-032 — Lifecycle element param (context extractors for hooks).
- RFC-044 — Model fields (`#[model]` two-way binding, flattening).
- RFC-049 — Typed slot contracts (slot-content type safety).

**Docs:**
- `docs/components/01-structure.md` — file layout, module shape, handler conventions, naming.
- `docs/components/02-state.md` — state tiers (local, parent→child, child→parent, global store).
- `docs/components/03-composition.md` — child-component tags, props, reactivity, slot capture.
- `docs/poco/01-format.md` — `.poco` template syntax (directives, attributes, single-root rule).
- `docs/poco/03-scoped-styles.md` — CSS scoping via data-attributes, `:global(...)` opt-out.

**Examples:**
- `examples/counter/src/lib.rs` + `Counter.poco` — minimal single-component demo with props.
- `examples/todo/src/lib.rs` + `TodoList.poco`/`TodoItem.poco` — multi-component composition, default slot, store access.
