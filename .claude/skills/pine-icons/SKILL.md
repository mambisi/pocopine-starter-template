---
name: pine-icons
description: >-
  Use when working with the pocopine Pine icons feature — the `icon!` proc macro for compile-time Rust SVG embedding, or the `<pine-icon>` template primitive with `register_icons!` for tree-shaking-friendly template rendering.
---

## What this is

Pine icons is a tree-shaking-friendly Tabler Icons integration for pocopine. It provides two paths: the `icon!` proc macro for embed-time SVG literals in Rust handlers, and the `register_icons!` + `<pine-icon>` pattern for template-driven rendering where only declared icons ship in the WASM binary.

## When to use

- **In Rust handlers**: Use `icon!("name")` to resolve an icon at compile time and get its SVG as a `&'static str`. Each call is tree-shaken independently — unused icons never ship.
- **In `.poco` templates**: Use `register_icons![…]` at app startup to declare which icons your app needs, then render them with `<pine-icon name="…">`. Only registered icons land in the binary.
- **Dynamic icon selection**: Use `<pine-icon :name="data.icon">` for reactive names if all possible values are pre-registered.
- **Conditional logic in handlers**: Use `icon!()` when the icon choice is driven by Rust `if`/`match` branches that return an SVG string to store in a component field.

## Key API / syntax

### `icon!` macro (Rust, compile-time)

```rust
use pine_icons::icon;

// Outline variant (default)
let svg = icon!("user");

// Explicit variant
let svg = icon!(filled / "star");
let svg = icon!(outline / "chevron-down");  // same as icon!("chevron-down")
```

Returns a `&'static str` containing the SVG body. Unknown names produce a compile-time error with jaro-winkler "did you mean?" suggestions.

### `register_icons!` macro (Rust, app startup)

```rust
#[wasm_bindgen(start)]
fn main() {
    pine_icons::register_icons![
        "user",
        "chevron-down",
        filled / "star",
    ];
    App::new()
        .register::<pine_icons::PineIcon>()
        .run();
}
```

Lists icon names (outline by default, or `variant / "name"` for explicit variant) that will be compiled into the registry. Each entry becomes an `IconEntry` in a thread-local `REGISTRY` vec; only these icons ship in the binary.

### `<pine-icon>` component (templates)

Attributes:
- `name` (required): Icon name in kebab-case. Can be static (`name="user"`) or reactive (`:name="expr"`).
- `variant` (optional): `"outline"` (default) or `"filled"`. Reactive via `:variant="expr"`.
- `size` (optional): CSS pixel size (default 20). Reactive via `:size="expr"`.

```html
<pine-icon name="user"></pine-icon>
<pine-icon name="star" variant="filled" size="16"></pine-icon>
<pine-icon :name="theme == 'dark' ? 'sun' : 'moon'"></pine-icon>
```

The component renders as a `<span role="visual">` containing the raw SVG. Inherits `currentColor` for `fill` and `stroke`, so text color propagates naturally.

### Registry lookup API (Rust, runtime)

```rust
// Look up a registered icon by variant + name
pine_icons::lookup("outline", "user")      // Option<&'static str>
pine_icons::lookup_with_hash("filled", "star")  // Option<(&'static str, u64)>

// SVG hash is FNV-1a (O(1) change detection; avoids string compare)
pine_icons::EMPTY_ICON  // ("", 0u64) — sentinel for misses

pine_icons::registry_len()  // Number of registered icons (testing/devtools)
```

## Examples

### Example 1: Static icon in a Rust handler (compile-time)

From `/home/zempare-mambisi/RustProjects/pocopine/crates/pine-icons/src/lib.rs`:

```rust
use pine_icons::icon;

fn toolbar_class_for(busy: bool) -> &'static str {
    if busy { icon!("loader-2") } else { icon!("check") }
}
```

Each branch resolves independently; unused icons are tree-shaken.

### Example 2: Template-driven icons with registration

From `/home/zempare-mambisi/RustProjects/pocopine/examples/keep/src/app.rs`:

```rust
#[wasm_bindgen(start)]
pub fn main() {
    pine_icons::register_icons![
        "menu-2",
        "search",
        "x",
        "refresh",
        "settings",
        "moon",
        "sun",
        "tag",
        "archive",
        filled / "pin",
        filled / "bulb",
    ];
    App::new()
        .register::<pine_icons::PineIcon>()
        .run();
}
```

Then in `.poco` template:

```html
<pine-icon name="search" size="20"></pine-icon>
<pine-icon name="sun" variant="outline"></pine-icon>
<pine-icon name="pin" variant="filled"></pine-icon>
```

### Example 3: Reactive icon selection

From `/home/zempare-mambisi/RustProjects/pocopine/docs/icons.md`:

```html
<!-- Icon flips with theme; both 'sun' and 'moon' must be registered -->
<pine-icon :name="theme == 'dark' ? 'sun' : 'moon'"></pine-icon>
```

## Gotchas

- **Registration is mandatory**: Only icons listed in `register_icons![…]` land in the binary. Using `<pine-icon name="unregistered">` renders nothing and logs a one-line warning in dev builds; misses fail silently in release.
- **Typos are caught only for `icon!`**: The `icon!("typo")` macro fails at compile time with a suggestion. Template names are resolved at render time via `lookup()` — author typos only show as dev console warnings.
- **`variant` defaults to `"outline"`**: Passing an empty string or omitting the attribute falls back to outline. Passing an invalid variant (not `"outline"` or `"filled"`) renders nothing.
- **SVG is raw HTML**: The `<pine-icon>` component uses `pp-html` to inject the SVG. Do not accept untrusted icon names from user input (use a fixed set of registered names only).
- **Size 0 falls back to 20**: If `size="0"` is passed or the prop is unset, the rendered box is `20px × 20px`.
- **Per-icon parse cost on every render**: The component re-injects SVG via `innerHTML` on every prop change. Use `svg_hash` to skip redundant updates (the component does this internally via `#[watch]`).
- **Styling via inheritance**: Icons inherit `currentColor`. To change fill/stroke, set `color` on the parent or use a wrapper with specific colors. Size is controlled by the `size` prop, but can be overridden with CSS on `.pine-icon` or the SVG directly.
- **RFC 063 rewrite pending**: RFC 063 §4.4 specifies a future modernization to per-icon components (like `lucide-react`), retiring the current `pp-html` + registry pattern. The current API is stable and production-ready, but new code may eventually migrate.

## References

- **Crates**: 
  - `crates/pine-icons/src/lib.rs` — registry API, `register_icons!` macro
  - `crates/pine-icons/src/primitive.rs` — `PineIcon` component with `#[watch]` handlers
  - `crates/pine-icons-macros/src/lib.rs` — `icon!` and `register_icons!` proc-macro implementation
- **Documentation**:
  - `docs/icons.md` — user guide (styling, syncing with upstream, tree-shaking rationale)
  - `rfcs/rfc-063-directive-cleanup-vue-alignment.md` §4.4 — future per-icon component rewrite
- **Examples**:
  - `examples/keep/src/app.rs` — full `register_icons!` list with filled variants
  - `examples/file-browser/src/lib.rs` — another real app registration
  - `crates/pine-icons/tests/manifest.rs` — test examples of `icon!()` and `register_icons![]`
- **Assets**: `crates/pine-icons/assets/tabler/` — vendored Tabler Icons; sync via `scripts/sync-tabler-icons.sh`
