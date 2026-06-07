---
name: pine-stylekit
description: >-
  Use when building styles with Pine Stylekit, the Pocopine-native utility-CSS compiler, or working with @theme tokens and CSS generation in Rust/WASM projects
---

## What this is

Pine Stylekit is Pocopine's native utility-CSS compiler. You write Tailwind-*shaped* utility classes in `.poco` templates; Stylekit reads your `@theme` tokens from CSS, extracts classes through the real Pocopine parser (not text scanning), and emits deterministic static CSS at build time with no browser runtime.

## When to use this

- Writing utility classes in `.poco` templates (e.g., `class="flex items-center bg-surface"`)
- Defining or managing design tokens in `@theme { … }` CSS blocks
- Troubleshooting unknown-utility or type errors during build
- Understanding how classes compile to CSS rules or how variants work
- Setting up Stylekit configuration in `Cargo.toml` or migrating from Tailwind
- Working with LSP metadata or editor autocomplete for utilities

## Key API / Syntax

**@theme tokens (CSS, single source of truth):**
```css
@theme {
  --color-surface: #ffffff;
  --color-ink-100: #18171a;
  --spacing: 0.25rem;
  --shadow-card: 0 1px 2px rgba(20, 18, 28, 0.05);
}
```

**Class grammar (Tailwind-shaped):**
```
class = [variant:]* base[-[value]]
variant = hover | focus-visible | data-[k=v] | aria-[k=v] | sm | md | lg | xl | 2xl
base = utility-name or utility-scale (e.g., flex, items-center, p-4, text-[13px])
```

**Core utilities and families** (from `crates/pocopine-stylekit/src/catalog.rs`):
- Display: `flex`, `block`, `grid`, `hidden`, `inline-flex`
- Layout: `items-center`, `justify-center`, `flex-col`, `gap-*`, `space-y-*`
- Spacing: `p-*` (padding), `m-*` (margin), directional (`px`, `py`, `mt`, etc.)
- Sizing: `w-*`, `h-*`, `min-w-*`, `max-w-*`, `size-*`
- Color: `bg-*`, `text-*`, `border-*` (all token-backed; fallback Tailwind palette)
- Typography: `font-*`, `text-*` (size or color), `leading-*`, `tracking-*`
- Border/radius: `border-*`, `rounded-*`, `shadow-*`
- Variants: `hover:`, `focus:`, `disabled:`, `active:`, `data-[…]:`, `aria-[…]:`, responsive (`sm:`, `md:`, `lg:`, `xl:`, `2xl:`)

**Arbitrary values (typed):**
- Length: `w-[12px]`, `h-[calc(100%-2rem)]`
- Color: `bg-[#00ff00]`, `text-[oklch(0.5 0.1 0)]`
- Number: `opacity-[0.75]`, `z-[999]`

**Rust API** (from `crates/pocopine-stylekit/src/lib.rs`):
```rust
// Compiler entry point
pub struct Compiler { registry, tokens, options }
impl Compiler {
    pub fn new(tokens: ThemeTokens, options: CompileOptions) -> Self
    pub fn compile(&self, used: &[extract::UsedClass]) -> Compilation
}

// Token model (CSS-first)
impl ThemeTokens {
    pub fn from_css(css: &str) -> Self  // Parse @theme blocks
    pub fn var_for(&self, family: &str, name: &str) -> Option<String>
    pub fn to_manifest_json(&self) -> String  // For LSP/diagnostics
}

// Utility resolution
impl Registry {
    pub fn builtin() -> Self
    pub fn emit_into(/* ... */) -> Result<Compilation, Diagnostic>
}
```

**Configuration** (in `Cargo.toml`):
```toml
[package.metadata.pocopine.stylekit]
input = "app.css"           # CSS with @theme tokens
output = "pkg/stylekit.css" # Generated stylesheet
src = "src"                 # Directory with .poco files
preflight = true            # Include base reset
enabled = true              # Set false to opt out
```

## Examples

**1. Static class extraction from a .poco template:**

File: `/home/zempare-mambisi/RustProjects/pocopine/examples/file-browser/src/components/sidebar/FileBrowserSidebar.poco`

```html
<div class="flex flex-wrap items-center justify-between gap-3">
  <pine-toggle-group-item value="all"
    class="inline-flex h-8 cursor-pointer items-center rounded-full 
           border border-line bg-surface px-3 text-[12.5px] font-medium 
           text-ink-70 transition hover:bg-ink-10 
           data-[state=on]:border-ink-100 data-[state=on]:bg-ink-100 
           data-[state=on]:text-surface">
    All
  </pine-toggle-group-item>
</div>
```

Each class is extracted via the Pocopine parser AST (not text), spans are attached, and the compiler matches them against the registry.

**2. @theme tokens with CSS custom properties:**

File: `/home/zempare-mambisi/RustProjects/pocopine/examples/file-browser/app.css` (first 50 lines)

```css
@theme {
  --color-surface: #ffffff;
  --color-ink-100: #18171a;
  --color-ink-70: #4a4750;
  --color-accent: oklch(0.54 0.13 252);
  --color-accent-soft: oklch(0.95 0.03 252);
  --shadow-card: 0 1px 2px rgba(20, 18, 28, 0.05);
}

/* Dark theme override */
[data-theme="dark"] {
  --color-surface: #161519;
  --color-ink-100: #f4f3f6;
}
```

The compiler reads all `@theme { … }` blocks, makes tokens available as `var(--color-*)` in utility CSS output, and emits them to `:root` in the generated stylesheet.

**3. Compilation in Rust (from `crates/pocopine-stylekit/src/lib.rs`):**

```rust
// Parse @theme from CSS
let tokens = ThemeTokens::from_css(css_input);

// Create compiler with tokens + options
let compiler = Compiler::new(tokens, CompileOptions::default());

// Extract classes from .poco files (via AST)
let used_classes = extract_poco(0, poco_source);

// Compile to CSS + diagnostics
let compilation = compiler.compile(&used_classes);
if compilation.has_errors() {
    eprintln!("Build failed: {}", compilation.diagnostics.len());
} else {
    println!("{}", compilation.css);
}
```

## Gotchas

**Tailwind-shaped, not Tailwind-compatible.** The supported utility set is the documented catalog (RFC 092 D3); anything outside it is an error. `bg-slate-700` from Tailwind's palette works (built-in fallback), but `grid-auto-flow-*` does not — add it to the registry by PR if broadly useful.

**Dynamic classes are caught.** `class="flex {muted ? 'opacity-50' : ''}"` produces a diagnostic with a migration hint to a static map (`{ 'opacity-50': muted }`). Opaque string concatenation is never silently ignored.

**Type errors in arbitrary values.** `w-[red]` is rejected — width expects a length (`px`, `rem`, `%`, `calc()`, `min()`, `max()`, `clamp()`) or `var(--…)`. The compiler emits a type error with the expected kind.

**Unknown tokens are errors.** `text-brand` where `--color-brand` is not defined lists the available colors in the family (`color-*`).

**Cascading and breakpoint order matter.** Responsive variants (sm/md/lg/xl/2xl) emit after base rules and in ascending min-width order, so a larger breakpoint wins. `data-[…]:` and `aria-[…]:` attribute variants emit after pseudo-class variants (`hover:`, `focus:`) so state attributes keep their styling when hovered.

**Classes are deduplicated and sorted.** If `.poco` uses the same class twice, it appears once in the output. Classes sort by cascade key (breakpoint, then state) to match Tailwind's layering.

**Component classes are not utilities.** If your CSS defines `.btn { }`, declare it in `known_classes` (via `CompileOptions`) so Stylekit skips it instead of erroring.

**Later @theme blocks override earlier ones,** matching CSS cascade. Multiple `@theme` blocks in the input are merged; the last value for a token wins.

## References

- **RFC 092** (tracking issue #169): `/home/zempare-mambisi/RustProjects/pocopine/rfcs/rfc-092-pocopine-stylekit.md` — The decision document covering naming (crate placement), CLI (opt-in flag), Tailwind compatibility promise (shaped not compatible), token model (CSS-first `@theme`), extraction contract (AST not text), and phased plan.
- **Crate roots:**
  - `/home/zempare-mambisi/RustProjects/pocopine/crates/pocopine-stylekit/src/lib.rs` — Compiler facade, pipeline, `Compilation` output, cascade ordering
  - `/home/zempare-mambisi/RustProjects/pocopine/crates/pocopine-stylekit/src/tokens.rs` — `ThemeTokens::from_css`, token lookup, manifest/`:root` emission
  - `/home/zempare-mambisi/RustProjects/pocopine/crates/pocopine-stylekit/src/registry.rs` — Utility resolution, family dispatch, variant handling, arbitrary value typing
  - `/home/zempare-mambisi/RustProjects/pocopine/crates/pocopine-stylekit/src/catalog.rs` — Documented utility families, `Catalog::to_markdown` (human docs), `to_metadata_json` (LSP/editor metadata)
  - `/home/zempare-mambisi/RustProjects/pocopine/crates/pocopine-stylekit/src/emit.rs` — CSS rule rendering, selector escaping for `:`, `[`, `]`, etc.
  - `/home/zempare-mambisi/RustProjects/pocopine/crates/pocopine-stylekit/src/extract.rs` — Class extraction from `.poco` AST, opaque dynamic binding detection
  - `/home/zempare-mambisi/RustProjects/pocopine/crates/pocopine-stylekit/src/project.rs` — Project-level compile entry, Preflight base reset, `ProjectCss` output
- **Docs:**
  - `/home/zempare-mambisi/RustProjects/pocopine/docs/pine-stylekit.md` — User guide: setup, `@theme`, recipes, diagnostics, editor support, migration from Tailwind, full utility catalog
- **Example:**
  - `/home/zempare-mambisi/RustProjects/pocopine/examples/file-browser/` — File browser app using Stylekit; app.css has the `@theme`, .poco files use classes; builds to `pkg/stylekit.css`
- **CLI:**
  - `pocopine build [--stylekit]` / `pocopine dev [--stylekit]` — Build/dev with compilation in-process
  - `pocopine stylekit --docs` — Regenerate the utility catalog (markdown)
  - `pocopine stylekit --metadata` — Emit JSON metadata for LSP/autocomplete (pair with `ThemeTokens::to_manifest_json`)
  - `pocopine stylekit --check` — Validate a project without writing output
