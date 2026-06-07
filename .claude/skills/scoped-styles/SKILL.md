---
name: scoped-styles
description: >-
  Use when authoring component stylesheets with automatic CSS scoping to a single component.
---

# Pocopine Scoped Component Styles

Scoped styles automatically isolate a component's CSS to that component's template using data-attributes, preventing style leaks and collisions. They are the default when you associate a `.css` file with a `#[component]`.

## When to use

- **Writing component-specific CSS** that should not affect other components or the global page.
- **Integrating with global CSS variables** (tokens in `styles.css`) while keeping component rules isolated.
- **Building themeable components** that use `[data-theme="dark"]` and CSS custom properties for dark mode.
- **Opting a rule out** of scoping to target global state (e.g., `body.dark` or `html`).

## Key API / syntax

### Component attribute

```rust
#[component(template = "Component.poco", style = "Component.css")]
```

- `style = "..."` (optional): path to a `.css` file, relative to the `.rs` file.
- If the file exists and no `style` is provided, the default is inferred as `<StructName>.css`.
- Scoping is **automatic** when `style` is set; there is no `scoped = true/false` flag.

### CSS opt-out (`:global()`)

Use `:global(selector)` inside a scoped stylesheet to prevent scoping on a single rule:

```css
/* This rule stays global — not scoped. */
:global(body.dark) .wrapper { background: #000; }

/* These rules are scoped with [data-pp-HASH]. */
.button { padding: 0.5rem; }
.button:hover { background: var(--brand-soft); }
```

### Global CSS variables in templates

Define tokens in a global `styles.css` at the app root:

```css
:root {
  --brand: #f8ae45;
  --fg: #3d2415;
  --bg: #fffaf2;
  --radius: 8px;
}

[data-theme="dark"] {
  --fg: #f5ead3;
  --bg: #1a130c;
}
```

Then reference them in scoped component CSS without modification:

```css
.card { background: var(--bg); border-radius: var(--radius); }
.card:hover { background: var(--bg-hover); }
```

### Scoping mechanism

The compiler (via `#[component]` expansion in `pocopine-macros`):

1. Computes a hash of the component name: `H = hash("component-name")` → first 8 hex chars.
2. Rewrites the template: appends `data-pp-<H>` to every element.
3. Rewrites the CSS: appends `[data-pp-<H>]` to every selector's last compound (the rightmost class or element).

Example with component `site-header` and hash `a1b2c3d4`:

**Input CSS:**
```css
.site-header { position: sticky; }
.site-header-search { flex: 1; }
:global(body.dark) .wrapper { background: #000; }
```

**Output CSS after scoping:**
```css
.site-header[data-pp-a1b2c3d4] { position: sticky; }
.site-header-search[data-pp-a1b2c3d4] { flex: 1; }
body.dark .wrapper { background: #000; } /* :global() unscoped */
```

**Template with data-attributes:**
```html
<div pp-data="site-header" class="site-header" data-pp-a1b2c3d4>
  <button class="site-header-search" data-pp-a1b2c3d4>Search</button>
</div>
```

## Examples

### Example 1: Basic scoped component

**File: `src/components/site_header/mod.rs`**

```rust
#[derive(Default, Serialize, Deserialize)]
#[component(
    template = "SiteHeader.poco",
    style = "site_header.css",
    role = "panel"
)]
pub struct SiteHeader {
    pub theme: String,
}

#[handlers]
impl SiteHeader {
    pub fn toggle_theme(&mut self) {
        self.theme = if self.theme == "dark" { "light" } else { "dark" }.into();
    }
}
```

**File: `src/components/site_header/site_header.css`** (automatically scoped)

```css
.site-header {
  position: sticky;
  top: 0;
  z-index: 5;
  padding: 0.5rem 0;
  background: color-mix(in srgb, var(--bg) 88%, transparent);
  backdrop-filter: blur(10px);
}

.site-header-theme {
  width: 1.9rem;
  height: 1.9rem;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  color: var(--fg);
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  cursor: pointer;
  transition: background 0.12s;
}

.site-header-theme:hover { background: var(--bg-subtle); }
```

### Example 2: Using `:global()` for app-level styles

**File: `src/components/tutorial/tutorial.css`**

```css
.tutorial { padding: 2.5rem 0; }
.tutorial h2 { font-size: 1.75rem; text-align: center; }

.step-num {
  width: 2.2rem;
  height: 2.2rem;
  border-radius: 50%;
  background: var(--brand);
  color: var(--brand-fg);
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-weight: 700;
}

/* Opt out: style body-level state at the app root. */
:global([data-tutorial-shown]) .tutorial { display: none; }
```

### Example 3: Dark mode via global CSS variables

**File: `styles.css` (global, app root)**

```css
:root {
  --fg: #3d2415;
  --bg: #fffaf2;
  --brand: #f8ae45;
  --border: #e5d3b0;
}

[data-theme="dark"] {
  --fg: #f5ead3;
  --bg: #1a130c;
  --border: #3a2a1a;
  --brand: #f8ae45; /* Preserved in dark mode */
}
```

**File: `src/components/showcase_card/showcase_card.css` (component)**

```css
.showcase-card {
  border: 1px solid var(--border);
  background: var(--bg);
  border-radius: var(--radius);
}

.showcase-tab[data-active="true"] {
  background: var(--brand);
  color: var(--brand-fg);
}
```

The component CSS automatically adapts to dark mode because it reads the CSS variables from `:root` — no per-component dark-mode duplication needed.

## Gotchas

### 1. Selectors spanning components

A cross-component selector like `.parent .child` in `Parent.css` targeting a `.child` inside an imported `<child-component>` **will not work** under scoping because each gets a different hash suffix. Use `:deep(.child)` instead (future feature) or refactor to avoid the cross-component dependency.

### 2. `:root`, `html`, `body` are never scoped

These pseudo-elements are exempt from scoping by design (they appear on a global allowlist). If you need a rule scoped to a component that affects `body`, use `:global()` explicitly.

### 3. Pseudo-elements (`:before`, `:after`)

The attribute is appended to the element part, not the pseudo-element:

```css
/* Input */
button::before { content: "►"; }

/* Output (scoped with data-pp-HASH) */
button[data-pp-a1b2c3d4]::before { content: "►"; }
```

### 4. `@keyframes` naming

Animation names are automatically renamed to avoid collisions:

```css
/* Input: two components both define 'spin' */
@keyframes spin { from { transform: rotate(0); } to { transform: rotate(360deg); } }
.loader { animation: spin 1s linear infinite; }

/* Output: renamed to keyframes-a1b2c3d4, reference updated */
@keyframes keyframes-a1b2c3d4 { ... }
.loader[data-pp-a1b2c3d4] { animation: keyframes-a1b2c3d4 1s linear infinite; }
```

### 5. No `:global()` around class names

`:global()` applies to selectors, not class values in HTML:

```css
/* ✓ Correct: global selector */
:global(body.dark) .card { background: #000; }

/* ✗ Wrong: won't work as intended */
:global(.card) { background: #000; }  /* This still gets scoped; use without :global() */
```

### 6. CSS parser: `lightningcss` handles edge cases

The scoper uses `lightningcss` (not regex), so it correctly handles attribute selectors with commas and special characters:

```css
/* These work correctly even with special chars */
input[data-state="active,focus"] { border-color: var(--brand); }
[aria-label*="danger"] { color: var(--destructive); }
```

## References

- **RFC 001 — Components**: `/rfcs/rfc-001-components.md` § 5.5 (Component style format and scoping spec)
- **Scoped styles guide**: `/docs/poco/03-scoped-styles.md` (detailed scoping algorithm and edge cases)
- **Macro implementation**: `crates/pocopine-macros/src/lib.rs` (parses `style = "..."` and emits scoping pass)
- **Example: website app**: `examples/website/src/components/` — real components using scoped CSS with global variables (SiteHeader, Tutorial, ShowcaseCard)
- **Global styles & dark mode**: `examples/website/styles.css` — root CSS with `@theme`-style tokens and `[data-theme="dark"]` theming
