---
name: slots-and-composition
description: >-
  Use when building or integrating components with default/named slots, scoped slots with pp-let, pp-as polymorphic rendering, or multi-component composition patterns in pocopine
---

# Slots & Composition

Pocopine components compose via kebab-case tags, props, and slot content insertion. Slots expose insertion points (default or named), optionally with scoped bindings that let parents read child state. The `pp-as` directive hoists a child element as the component root for polymorphic rendering.

## When to use

- Defining a compound component with reusable insertion points (`<slot>`, `<slot name="header">`)
- Publishing child state to slot content via scoped bindings (`:prop="expr"` + `pp-let="binding"`)
- Polymorphic rendering — wrapping a user's element instead of your own template wrapper
- Constraining which component types are allowed in a slot's children
- Multi-component composition: header/body/footer sections, lists with per-item rendering, menus

## Key API & Syntax

### Default & Named Slots (RFC 011)

**Component side — expose insertion points:**

```
<slot></slot>                        # default slot, unnamed
<slot name="header">Default header</slot>  # named slot with fallback
<slot name="item" :item="item">…</slot>   # scoped slot, publishes child state
```

**Consumer side — fill slots:**

```
<pine-component>
  Direct content goes to default slot
  <template pp-slot="header">Custom header</template>
  <template pp-slot="item" pp-let="ctx">
    <!-- ctx has .item, .index, etc. from :item/:index on <slot> -->
  </template>
</pine-component>
```

**Scoped slot attributes:**

- `name="id"` — slot identifier (default: `"default"`); must be a static string
- `:<prop>="<expr>"` — expose `<prop>` on the slot binding; `<expr>` evaluates in the component's scope
- *children* — fallback content shown when caller doesn't provide the slot

**Consumer attributes:**

- `pp-slot="id"` — which slot this template fills; wrapped in `<template>`
- `pp-let="var"` — introduce `var` as the scoped binding; contains all `:prop` exposures

### Typed Slot Props (RFC 084)

Scoped slots can be **typed** at compile time. The component declares a `Props` struct (same `#[derive(Props)]` used for component props) and binds the slot to it:

```rust
#[derive(Default, Props, Serialize, Deserialize)]
pub struct UploadRow {
    #[prop] pub name: String,
    #[prop] pub status: String,
    #[prop] pub progress: f64,
}

#[component(template = "UploadRoot.poco", role = "scope")]
#[slot(name = "row", props = UploadRow)]  // typed binding
pub struct UploadRoot {
    pub files: Vec<UploadFile>,
}
```

**Static mode** — explicit `:LHS=expr` on the `<slot>`:

```
<div pp-for="file in files">
  <slot name="row"
    :name="file.name"
    :status="file.status"
    :progress="file.progress"></slot>
</div>
```

Macro validates that every `#[prop]` field is covered and no extra `:keys` exist.

**Iterated mode** — auto-publish the `pp-for` loop variable when `<slot>` sits inside `pp-for`:

```
<li pp-for="file in files">
  <slot name="row"></slot>  <!-- no :LHS= needed; file is auto-published -->
</li>
```

Macro type-checks that `file`'s type matches the declared `props = T`.

### Slot Constraints (RFC 049)

Compound components can declare which child component types are allowed. The `#[slot]` attribute accepts an `accepts` list:

```rust
#[component(template = "PineContextMenuContent.poco", role = "panel")]
#[slot(default, accepts = [
    PineContextMenuItem,
    PineContextMenuSeparator,
    PineContextMenuGroup,
])]
pub struct PineContextMenuContent { /* … */ }
```

Child components not in the list cause a `rustc` compile error with a span pointing into the `.poco` file.

Alternative: `only = [...]` (stricter syntax, same effect):

```rust
#[slot(default, only = [PineTooltipTrigger, PineTooltipPortal])]
pub struct PineTooltipRoot { /* … */ }
```

### Polymorphic Rendering with pp-as (RFC 019)

The `pp-as` attribute replaces the component's template root with a single user-provided element. Use for headless UI primitives that wrap a user's tag instead of imposing their own (e.g., a Button styled as a link).

**Consumer side:**

```html
<pine-button pp-as variant="ghost">
  <a href="/docs">Read docs</a>
</pine-button>
```

**Component side (PineButton template):**

```html
<button pp-bind:class="variant == 'ghost' ? 'btn-ghost' : 'btn'">
  <slot></slot>
</button>
```

**Result:** The rendered DOM is `<a class="btn-ghost" href="/docs">Read docs</a>` — the `<button>` wrapper is discarded, and the `<a>`'s attributes + template class are merged.

**Merge rules:**

- `class` — space-concatenated; template classes appended
- `style` — semicolon-joined; template declarations appended; user wins on duplicate properties
- `pp-*` directives — copied to user element if absent; user's own wins on collision
- All other attributes (`href`, `disabled`, `aria-*`, etc.) — user wins on conflict
- `pp-data`, `pp-as` — dropped (internal)

**Constraints:**

- Component template root must have **exactly one `<slot>` and no other element children** (text/comments ignored)
- User must provide **exactly one element child**
- Named-slot templates (`<template pp-slot="...">`) inside the consumer tag are **discarded** under `pp-as`

## Examples

### Example 1: Named slots with default content

**ShowcaseCard** (from `/home/zempare-mambisi/RustProjects/pocopine/examples/website/src/components/showcase_card/`):

```html
<!-- ShowcaseCard.poco -->
<root class="showcase-card" :id="slug">
  <header class="showcase-head">
    <h2 class="showcase-title" pp-text="title"></h2>
  </header>
  <div class="showcase-body" pp-show="tab == 'preview'" role="tabpanel">
    <slot name="preview"></slot>
  </div>
  <div class="showcase-body" pp-show="tab == 'code'" role="tabpanel">
    <slot name="code"></slot>
  </div>
</root>
```

```rust
#[derive(Default, Serialize, Deserialize)]
#[component(template = "ShowcaseCard.poco", role = "panel")]
pub struct ShowcaseCard {
    #[prop] pub title: String,
    #[prop] pub slug: String,
    pub tab: String,
}
```

Usage:

```html
<showcase-card title="Button" slug="button">
  <template pp-slot="preview">
    <pine-button>Click me</pine-button>
  </template>
  <template pp-slot="code">
    <pre><code><pine-button>Click me</pine-button></code></pre>
  </template>
</showcase-card>
```

### Example 2: Default slot with props and scoped bindings

**TodoItem** (from `/home/zempare-mambisi/RustProjects/pocopine/examples/todo/`):

```html
<!-- TodoItem.poco -->
<li>
  <input type="checkbox" pp-model="done" />
  <strong pp-text="label"></strong>
  <slot></slot>
  <button pp-on:click="toggle">toggle</button>
</li>
```

```rust
#[derive(Default, Serialize, Deserialize)]
#[component]
pub struct TodoItem {
    #[prop] pub id: i32,
    #[prop] pub label: String,
    #[prop] pub done: bool,
}
```

Usage with default slot:

```html
<div>
  <todo-item id="1" label="Buy milk">
    <em> (groceries)</em>
  </todo-item>
</div>
```

### Example 3: Scoped slot with pp-let (RFC 011)

**FileBrowserUploadDock** (from `/home/zempare-mambisi/RustProjects/pocopine/examples/file-browser/`):

```html
<!-- FileBrowserUploadDock.poco — partial -->
<pine-upload-root scope="storage-browser" multiple …>
  <template pp-slot="default" pp-let="upload">
    <span pp-text="upload.status_label || 'Uploads'"></span>
    <!-- access child's exposed state via upload.X -->
    <div pp-show="!upload.files_empty">
      <span pp-text="upload.file_count_label"></span>
      <template pp-for="file in upload.files" pp-key="file.id">
        <span pp-text="file.name"></span>
      </template>
    </div>
  </template>
</pine-upload-root>
```

Here, `<pine-upload-root>` exposes `upload` object with fields like `status_label`, `files_empty`, `file_count_label`, which the parent reads via `pp-let="upload"`.

### Example 4: pp-as polymorphic rendering

**ButtonDemo.poco** (from `/home/zempare-mambisi/RustProjects/pocopine/examples/website/`):

```html
<pine-button pp-as variant="ghost">
  <a href="https://github.com/mambisi/pocopine">Repo ↗</a>
</pine-button>
```

Instead of wrapping the link in a `<button>` tag, `pp-as` applies the button's styling (class, directives) directly to the `<a>`, rendering a styled link instead of a button.

## Gotchas

### Scoped slots & parent scope

**The most common mistake:** Inside a `<template pp-slot>`, directives resolve in the **caller's scope**, not the child's:

```html
<!-- WRONG ❌ -->
<upload-item :name="file.name" :status="file.status">
  <span pp-text="name"></span>     <!-- resolves to caller's name, not child's -->
</upload-item>
```

Fix: Use scoped slots to explicitly expose child fields:

```html
<!-- RIGHT ✓ -->
<slot :name="name" :status="status"></slot>    <!-- child exposes fields -->
<template pp-slot="default" pp-let="row">
  <span pp-text="row.name"></span>              <!-- bind via pp-let name -->
</template>
```

### pp-as structural constraints

- Template root **must** be a single wrapper element with only a `<slot>` child; no multiple elements, no nested divs
- Consumer **must** provide exactly one element (multiple children ignored silently)
- Named-slot templates inside consumer are **discarded** under `pp-as`

If structural rules violated, `pp-as` is ignored and the normal mount path runs (warning in console).

### Static vs iterated slot props (RFC 084)

- **Static mode:** Slot sits alone; author writes explicit `:foo="expr"` on the `<slot>` element. Used for non-repeated slots or for exposing computed/derived state.
- **Iterated mode:** Slot sits inside a `pp-for` **with zero `:LHS=` attributes**. The loop variable is auto-published.
- **Mixing modes:** Any presence of `:LHS=…` on the slot forces static mode; there's no "hybrid" option. To expose loop iteration metadata like `$index` or `$last`, use static mode and publish them explicitly.

### Component registration

Components must be registered before they can be used as tags:

```rust
#[wasm_bindgen(start)]
pub fn main() {
    App::new()
        .register::<TodoList>()
        .register::<TodoItem>()
        .run();
}
```

Unregistered tags render as `HTMLUnknownElement` (transparent to the browser) and do nothing.

### Props are one-shot, not reactive

Static attributes on tags are parsed once at `init` time:

```html
<todo-item id="1" label="Buy milk" />  <!-- static, one-shot -->
```

For reactivity, use `pp-bind:`:

```html
<todo-item pp-bind:id="todo.id" pp-bind:label="todo.label" />  <!-- reactive -->
```

## References

- **RFC 011** — Scoped slots (named slots, `pp-slot`, `pp-let`, default content) — `/rfcs/rfc-011-scoped-slots.md`
- **RFC 019** — pp-as (polymorphic rendering, asChild) — `/rfcs/rfc-019-pp-as.md`
- **RFC 049** — Typed slot contracts (accepts/only lists) — `/rfcs/rfc-049-typed-slot-contracts.md`
- **RFC 084** — Typed slot props (static & iterated modes) — `/rfcs/rfc-084-typed-slot-props.md`
- **Composition guide** — `/docs/components/03-composition.md` (tag naming, props binding, slot semantics, scoped-slot pattern)
- **Examples:**
  - ShowcaseCard (named slots): `examples/website/src/components/showcase_card/{ShowcaseCard.poco, mod.rs}`
  - TodoItem (default slot): `examples/todo/src/{TodoItem.poco, lib.rs}`
  - FileBrowserUploadDock (scoped slots): `examples/file-browser/src/components/upload_dock/FileBrowserUploadDock.poco`
  - ButtonDemo (pp-as): `examples/website/src/components/showcase/button/ButtonDemo.poco`
  - PineTooltip* (slot constraints): `crates/pine/src/tooltip/mod.rs`
