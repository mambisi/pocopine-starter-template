---
name: poco-templates
description: >-
  Use when writing or debugging pocopine .poco template syntax, single-root rules, component tags, SVG namespace support, or template compilation in the pocopine framework.
---

## What this is

`.poco` templates are plain HTML with `pp-*` directives that define the view layer in pocopine, a Rust/WASM full-stack framework. Templates must follow the single-root rule, use kebab-case for component tags, and support structured SVG with namespace awareness.

## When to use

- Writing or debugging `.poco` template markup (HTML + directives)
- Enforcing or understanding the single-root template rule (RFC 045)
- Using component tags (kebab-case custom elements)
- Working with the `<root>` placeholder for role-based primitives (RFC 033)
- Handling SVG templates and namespace rules (RFC 068)
- Understanding how templates compile at macro time (RFC 050, RFC 058)
- Troubleshooting template parser errors or validation failures

## Key API / syntax

**Template structure:**
- **Single root element required** — exactly one top-level HTML element per `.poco` file (RFC 045). Validated at Rust compile time via `#[component]` macro.
- **`<root>` placeholder** — used in role-based primitives (RFC 033). The `#[component(role = "interactive|visual|panel|...")]` attribute rewrites `<root>` to the appropriate HTML tag (`<button>`, `<span>`, `<div>`, etc.) at registration time.
- **Kebab-case component tags** — custom elements must use lowercase with hyphens: `<pine-button>`, `<my-component>`. These are mounted as child components, not native HTML.
- **Directives** — `pp-*` attributes bind behavior:
  - `pp-data="name"` — scope binding (on root only, auto-injected by macro)
  - `pp-on:event="handler"` — event listeners with modifiers (`.stop`, `.prevent`)
  - `pp-text="field"` — text interpolation
  - `pp-show="bool_expr"` — conditional visibility
  - `pp-for="item in items"` — list iteration
  - `:attr="expr"` or `pp-bind:attr="expr"` — attribute binding
  - `@click="handler"` — shorthand for `pp-on:click`
  - `pp-if="bool_expr"` — conditional rendering
  - `pp-model:attr="field"` — two-way binding

**SVG support (RFC 068):**
- `<svg>` and SVG elements (`<g>`, `<line>`, `<circle>`, `<rect>`, etc.) are native plan targets — directives on them are compiled like HTML elements.
- `<template pp-for>` inside SVG is treated as a controller anchor (not an HTML template) — rows are inserted before the anchor in the SVG namespace.
- SVG macro bodies parse through `document.createElementNS()` to preserve namespace, not through `innerHTML`.

**Template validation (RFC 050):**
- **Forbidden self-close syntax** — `<slot/>`, `<root/>`, custom elements like `<my-comp/>` are rejected. Write `<slot></slot>` instead. Self-closing is only allowed for HTML void elements (`<br/>`, `<img/>`) and inside `<svg>` / `<math>` (foreign content).
- **Parse modes** — `parse()` returns AST + all errors; `parse_strict()` only fails on framework-owned errors (anchored byte ranges), tolerating html5ever spec-recovery notices (unanchored).
- **Synthetic elements** — html5ever's auto-inserted elements (e.g., `<tbody>` in tables) are marked `synthetic = true` and must be filtered by structural checks. Use `ast.element_roots()` (not `ast.roots.len()`) to count roots — it excludes synthetic nodes, text, comments.

**Compilation (RFC 058):**
- Templates are read and validated at Rust macro expansion time via `include_str!()` and `parse_strict()`.
- The macro emits a `const _: () = match check_single_root(...) { ... }` item that validates the root count during const evaluation; violations surface as Rust compile errors on the `#[component]` attribute.
- Generated code mounts through explicit view functions, not runtime DOM scanning.

## Examples

**Single-root component with directives:**
```html
<!-- Counter.poco (from docs/poco/01-format.md) -->
<div pp-data="counter" pp-init="init" class="wrapper">
  <button pp-on:click="decrement">-</button>
  <span class="count" pp-text="count"></span>
  <button pp-on:click="increment">+</button>
</div>
```

**Role-based primitive using `<root>` placeholder:**
```html
<!-- PineAvatarRoot.poco (RFC 033) -->
<root class="pine-avatar-root" :data-loaded="loaded">
  <slot></slot>
</root>
```
Paired with Rust:
```rust
#[component(name = "pine-avatar-root", template = "PineAvatarRoot.poco", role = "visual")]
pub struct PineAvatarRoot { pub loaded: bool }
```
Renders as `<span class="pine-avatar-root" data-loaded="..." data-pine-role="visual">`.

**SVG with `pp-for` controller anchor (RFC 068):**
```html
<!-- ChartGrid.poco -->
<svg viewBox="0 0 100 100">
  <g>
    <template pp-for="line in grid" pp-key="line.key">
      <line :x1="line.x1" :y1="line.y1" :x2="line.x2" :y2="line.y2"></line>
    </template>
  </g>
</svg>
```
The `<template>` is mounted as a controller anchor (not HTMLTemplateElement) in the SVG namespace; rows are `SVGLineElement` instances.

**Hero component with directives and custom tags:**
```html
<!-- Hero.poco (examples/website/src/components/hero/Hero.poco) -->
<root class="hero">
  <img class="hero-mascot" src="/mascot.svg" alt="pocopine mascot">
  <h1><span class="brand">poco</span>pine</h1>
  <p class="tagline">A reactive Rust/WASM UI framework...</p>
  <div class="hero-actions"
       pp-intersect:enter.margin.-72="hide_header_github"
       pp-intersect:leave.margin.-72="show_header_github">
    <button class="cta-primary" @click="open_site_palette">
      Get started <kbd class="cta-kbd">⌘K</kbd>
    </button>
  </div>
</root>
```

## Gotchas

**Single-root violation** — Templates with two or more top-level elements are rejected at Rust compile time:
```html
<!-- ❌ REJECTED -->
<div>first</div>
<div>second</div>
```
Error: `pocopine: template for component \`my-comp\` has more than one root element (pocopine templates require exactly one root)`. Wrap in a container or use one root.

**Forbidden self-close on custom / pseudo-elements** — `<slot/>`, `<root/>`, `<my-component/>` are syntax errors. Only void elements and foreign-content children (SVG/MathML) allow self-closing:
```html
<!-- ❌ REJECTED -->
<div><slot/></div>

<!-- ✅ ACCEPTED -->
<div><slot></slot></div>
<svg><circle r="5"/></svg>
<input type="text" />
```

**Second root is silently dropped at runtime** — RFC 045 enforces single-root at compile time. If lenient mode is enabled (`POCOPINE_TEMPLATES_LENIENT=1`), multi-root templates compile with a warning but only the first root renders. Directives on the orphaned second root never fire.

**SVG namespace requires native element classification** — SVG elements must be recognized by the macro classifier as native DOM targets, not custom components. Custom SVG elements are not supported in phase 1 (RFC 068). Standard SVG elements (`<g>`, `<line>`, `<rect>`, `<circle>`, `<path>`, etc.) are classified automatically.

**Text nodes and comments at root level preserved in AST** — `TemplateAst.roots` includes text, comments, and synthetic nodes. Use `TemplateAst::element_roots()` to filter to non-synthetic authored elements only — this is the canonical method for root counting (RFC 045).

**No embedded Rust or CSS** — `.poco` is **only** HTML with `pp-*` directives. Rust lives in `.rs` files; CSS in `.css` files. No `<script>` or `<style>` blocks.

**Attribute values are bare identifiers (phase 1)** — Directive attributes like `pp-on:click="handler"` and `:attr="field"` accept field/handler names. Full Rust expressions in attribute values (`pp-on:click="self.count += 1"`) are a future milestone; today the runtime treats values as identifiers.

## References

**RFCs:**
- **RFC 045** — Single-root `.poco` templates enforced at compile time (`check_single_root` const validator, `E0080` compile error).
- **RFC 033** — Primitive roles and `<root>` placeholder rewriting (`role = "visual|interactive|panel|..."` maps to semantic HTML).
- **RFC 050** — HTML5ever compile-time parser; forbidden self-close rule; parse-error policy (framework-owned vs spec-recovery).
- **RFC 058** — Compiled views: macro-generated mount code replaces runtime walker; explicit child-component mounts.
- **RFC 068** — SVG namespace support; `<template pp-for>` as controller anchor inside SVG; namespace-aware body parsing.

**Crates:**
- `pocopine-template-parser` — Wraps `html5ever` + `markup5ever_rcdom`; produces `TemplateAst`; entry points `parse()` and `parse_strict()`.
- `pocopine-core::templates` — `check_single_root()` const validator; `RootCheck` enum.
- `pocopine-macros` — `#[component]` macro; wires template validation into `const _` items; emits view code.

**Documentation:**
- `/docs/poco/01-format.md` — File format; three-file convention; rules for `.poco`, `.rs`, `.css`.
- `/docs/poco/02-compilation.md` — Compile-time checks; error diagnostics.

**Tests & examples:**
- `/crates/pocopine-template-parser/src/lib.rs` — Parser unit tests covering single-root, void elements, synthetic nodes, byte-range fidelity, foster-parenting, self-close rules.
- `/examples/website/src/components/hero/Hero.poco` — Role placeholder and complex directives.
- `/examples/keep/src/components/note_card/KeepNoteCard.poco` — List iteration, conditionals, attribute binding.
