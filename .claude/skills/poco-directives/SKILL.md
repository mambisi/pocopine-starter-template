---
name: poco-directives
description: >-
  Use when authoring pocopine template directives (pp-*), understanding directive syntax, modifiers, args, host constraints, or migrating from removed directives (pp-init/pp-cloak/pp-data)
---

# pocopine pp-* Directives

Pocopine template directives declare reactivity, event handling, conditional rendering, and DOM integration. All directives use the `pp-*` prefix or shorthand prefixes (`:` for bind, `@` for on). The directive surface is specified in `crates/pocopine-directives/src/lib.rs` (the authoritative registry), with implementations in `crates/pocopine-core/src/directives/`.

## When to use

Use this guide when you need to:
- Bind reactive expressions to attributes, classes, or component props
- Handle events with modifiers (`.prevent`, `.enter`, `.debounce`, etc.)
- Render conditionally, iterate lists, or toggle visibility
- Capture element references for Rust handlers
- Animate mount/unmount with transitions or FLIP layout animation
- Set up floating-element positioning, keyboard navigation, or observer integration

## Live directive surface

All 22 live directives, with host constraints and arg requirements:

| Directive | Arg | Host | Key features |
|-----------|-----|------|--------------|
| **pp-if** | None | `<template>` only | Conditional rendering; mount/unmount plan (no runtime walker). Body must be exactly one element. |
| **pp-for** | None | `<template>` only | List iteration: `pp-for="item in items"`. Exposes `$index`, `$first`, `$last`. Pair with `pp-key` for keyed diffing. |
| **pp-show** | None | Any | Toggles `display:none` vs default. Element stays in DOM. Use with `pp-transition` for enter/leave. |
| **pp-text** | None | Any | Sets `textContent` to stringified expression. Prefer inline `{{expr}}` when mixing static + dynamic text. |
| **pp-html** | None | Any | Sets `innerHTML` to expression value. XSS surface — use only with trusted content. |
| **pp-bind** | **Required** | Any | Reactive attribute/prop binding. Shorthand: `:attr="expr"`. Special handling for `class` (string or object), `style`, and child component props. |
| **pp-on** | **Required** | Any | Event handler. Shorthand: `@event="handler"`. Modifiers: `.prevent`, `.stop`, `.self`, `.once`, `.window`, `.document`, `.capture`, `.outside`, `.debounce[.ms]`, key modifiers (`.enter`, `.escape`, `.arrow-down`, etc.), system keys (`.ctrl`, `.shift`, `.alt`, `.meta`). |
| **pp-model** | Optional | Any | Two-way binding. Native inputs: `pp-model="field"` with modifiers `.number`, `.trim`, `.lazy`. Components: `pp-model:prop="field"` (default prop: `model`). |
| **pp-ref** | None | Any | Stores element in scope for Rust access via `refs::get::<T>("name")`. Compile-time registration; no runtime overhead. |
| **pp-route** | None | Any | Marks `<a>` for SPA router interception (prevents default nav, updates outlet). |
| **pp-teleport** | None | `<template>` only | Portal: renders template body at CSS-selector target (resolved once). `pp-teleport="body"` or `pp-teleport=".outlet"`. |
| **pp-transition** | Optional | Any | Enter/leave animations. Presets: `fade`, `scale`, `fade-scale`, `zoom`, `slide-up`, `slide-down`, `slide-left`, `slide-right`, `collapse`, `none`. Asymmetric via `:in` / `:out`. Explicit class phases via `:enter`, `:enter-start`, `:enter-end`, `:leave`. |
| **pp-anchor** | **Required** | Any | Floating-element positioning. Placements: `top|bottom|left|right` × `start|center|end` (e.g., `top-start`). Modifiers: `.offset.N`, `.flip`, `.same-width`. |
| **pp-roving** | Optional | Any | Roving-tabindex keyboard nav. Modifiers: `.vertical` (default), `.horizontal`, `.both`, `.nowrap`, `.virtual` (for aria-activedescendant combobox). |
| **pp-resize** | None | Any | ResizeObserver integration. Handler signature: `(width: f64, height: f64)`. Modifiers: `.content-box`, `.border-box`, `.document`. |
| **pp-intersect** | Optional | Any | IntersectionObserver integration. Args: `:enter` / `:leave` (fire on visibility). Modifiers: `.threshold.N`, `.margin.<value>`. |
| **pp-flip** | None | Any | FLIP layout animation: element animates from old to new position on DOM mutations. Honors `prefers-reduced-motion`. Typically paired with keyed `pp-for`. |
| **pp-as** | None | Component only | Polymorphic rendering: hoists single `<slot>` root. Requires exactly one slot child in template. |
| **pp-key** | None | Any | Keyed-diffing ID for `pp-for` (typically `item.id`). *RFC-063 deferred: will converge to `:key` on row root.* |
| **pp-slot** | None | `<template>` only | Consumer-side named slot (value = slot name). Pair with `pp-let` for scoped slot bindings. *RFC-063 deferred: will converge to `pp-slot:name="binding"`.* |
| **pp-let** | None | `<template>` only | Scope variable for scoped slot props (e.g., `<template pp-slot="item" pp-let="ctx">`). *RFC-063 deferred: folds into `pp-slot:name`.* |
| **pp-stagger** | None | `<template>` only | Per-item stagger delay (ms) for `pp-for` enter animations. *RFC-063 deferred: converges to `pp-for` modifier.* |

## Shorthands & arg syntax

**Bind shorthand** (`:attr`): expands to `pp-bind:attr`
```html
<!-- Long form -->
<button pp-bind:class="btn_class" pp-bind:disabled="busy">Save</button>

<!-- Short form (identical semantics) -->
<button :class="btn_class" :disabled="busy">Save</button>
```

**On shorthand** (`@event`): expands to `pp-on:event`
```html
<!-- Long form -->
<input pp-on:keydown.enter="submit" pp-on:click.prevent="handle" />

<!-- Short form (identical semantics) -->
<input @keydown.enter="submit" @click.prevent="handle" />
```

**Parsing rule**: `parse_directive_attr("pp-on:click.prevent.stop")` → head=`"on"`, arg=`"click"`, modifiers=`["prevent", "stop"]`. Shorthands rewrite before dispatch: `:class` → `pp-bind:class`, `@click` → `pp-on:click`.

## Modifiers

Modifiers appear after the arg, separated by `.`. Order is irrelevant. Multiple modifiers compose:

**Event modifiers (`pp-on:`)**
- `.prevent` — calls `preventDefault()` before handler
- `.stop` — calls `stopPropagation()`
- `.self` — fires only when `event.target === el`
- `.once` — listener removed after one fire
- `.window` — attach to `window` instead of `el`
- `.document` — attach to `document` instead of `el`
- `.capture` — install in capture phase
- `.passive` — set passive flag on listener
- `.outside` — fires only when target is outside `el` (implies capture)
- `.debounce[.N]` — wait `N` ms of quiet (default 300) after last event

**Key modifiers (`pp-on:keydown|keyup|keypress`)**
- Named keys: `.escape` / `.esc`, `.enter`, `.tab`, `.space`, `.backspace`, `.delete` / `.del`, `.arrow-up` / `.up`, `.arrow-down` / `.down`, `.arrow-left` / `.left`, `.arrow-right` / `.right`, `.home`, `.end`, `.page-up`, `.page-down`
- System keys: `.ctrl`, `.shift`, `.alt`, `.meta`
- Any single-letter/word: `.k` fires on the `k` key; `.slash` fires on `/`; matching is case-insensitive (`ev.key.to_lowercase()`)
- All key modifiers work on `KeyboardEvent` only; non-keyboard events fail the filter silently

Example:
```html
<!-- Named key -->
<input @keydown.escape="close" />

<!-- System + key combo (both required) -->
<div @keydown.ctrl.k="open_command_palette"></div>

<!-- Mixed with event modifiers -->
<form @keydown.enter.prevent.stop="submit" />
```

**Bind modifiers (`pp-bind:`)**
- No modifiers; all changes go through `class` / `style` special-casing or plain `setAttribute`

**Model modifiers (`pp-model`)**
- `.number` — coerce input value to `Number`
- `.trim` — strip whitespace
- `.lazy` — sync on `change` instead of `input`

**Transition modifiers (`pp-transition`)**
- None (use the `:in` / `:out` args for asymmetry, or `:enter` / `:leave` for explicit class control)

**Anchor modifiers (`pp-anchor:placement`)**
- `.offset.N` — pixel offset from the computed edge
- `.flip` — auto-flip when near viewport edge
- `.same-width` — match anchor element width

**Roving modifiers (`pp-roving`)**
- `.vertical` — arrow keys move focus vertically (default)
- `.horizontal` — arrow keys move focus horizontally
- `.both` — arrow keys in both directions
- `.nowrap` — focus wraps at edges (default: wrap)
- `.virtual` — use `aria-activedescendant` instead of DOM focus (combobox pattern)

**Resize modifiers (`pp-resize`)**
- `.content-box` — measure content box (default)
- `.border-box` — measure including border
- `.document` — observe document resize (fallback for ResizeObserver polyfills)

**Intersect modifiers (`pp-intersect`)**
- `.threshold.N` — fire when visibility crosses `N` (0–1, default 0.5)
- `.margin.<value>` — expand the intersection root margin (e.g., `.margin.100px`)

## Code examples

**Conditional rendering with transition:**
```html
<!-- From: /home/zempare-mambski/RustProjects/pocopine/examples/hn/src/components/story_detail/StoryDetail.poco -->
<template pp-if="text">
  <div class="story-text"
       pp-html="text"
       pp-transition:enter="pp-fade-enter"
       pp-transition:enter-start="pp-fade-enter-start"
       pp-transition:enter-end="pp-fade-enter-end"></div>
</template>
```

**Two-way binding and event handling:**
```html
<!-- From: /home/zempare-mambski/RustProjects/pocopine/examples/site/src/Contact.poco -->
<form class="contact-form" pp-on:submit.prevent="submit">
  <input type="text" pp-model="name" autocomplete="name" />
  <input type="email" pp-model="email" autocomplete="email" />
  <textarea pp-model="message" rows="6"></textarea>
  <button type="submit" class="btn primary" pp-show="!submitting">Send</button>
</form>
```

**List iteration with keying and polymorphic rendering:**
```html
<!-- From: /home/zempare-mambski/RustProjects/pocopine/examples/counter/src/Counter.poco -->
<template pp-for="item in items" pp-key="item.id">
  <my-list-item pp-bind:item="item" pp-bind:selected="item.id === selected"></my-list-item>
</template>

<!-- Polymorphic slot rendering -->
<!-- From: /home/zempare-mambski/RustProjects/pocopine/crates/pine/src/popover/PinePopoverTrigger.poco -->
<root pp-as
      class="pine-popover-trigger"
      pp-ref="trigger"
      :aria-expanded="open ? 'true' : 'false'"
      aria-haspopup="dialog"
      @pointerdown.stop
      @click.stop="toggle">
  <slot></slot>
</root>
```

**Keyboard navigation and layout observation:**
```html
<!-- Roving tabindex (from PineTabsList) -->
<root role="tablist" class="pine-tabs-list" pp-roving.horizontal>
  <slot></slot>
</root>

<!-- ResizeObserver (from PineScrollAreaViewport) -->
<div @scroll="on_scroll" pp-resize.border-box="on_resize">
  <slot></slot>
</div>
```

## Removed directives (RFC-063)

Three directives were deleted in v2. Using them triggers a `compile_error!`:

| Removed | Why | Migration |
|---------|-----|-----------|
| **pp-init** | Pre-`#[handlers]` Alpine pattern; redundant with `on_setup` lifecycle hook | Use `#[handlers] impl Foo { fn on_setup(&mut self) { } }` |
| **pp-cloak** | Guarded FOUC on Alpine's runtime parser; post-RFC-061 mount is synchronous | Delete the attribute; no replacement needed. |
| **pp-data** | Internal scope marker; macro auto-stamps all component roots | Delete the attribute. Was never meant for author use. |

## Key constraints & patterns

1. **Host-only constraints**: `pp-if`, `pp-for`, `pp-teleport`, `pp-slot`, `pp-let`, `pp-stagger` require `<template>` host. `pp-as` requires a component tag (kebab-case with hyphen) or `<root>`. All others accept any element.

2. **Argument requirements**:
   - `pp-bind` and `pp-on` require an arg (the attribute name / event name)
   - `pp-model`, `pp-transition`, `pp-intersect`, `pp-anchor` take an optional arg
   - All others forbid args (ignore them if present)

3. **Keyed iteration**: Pair `pp-for` with `pp-key` (on the same template or child element) for correct diffing. Without a key, list reorders may reuse the wrong component state. Keys must be stable values (typically `item.id`).

4. **Two-way binding to components**: `pp-model:prop="field"` requires the target component to emit `pp:update:prop` custom events (or `pp:update:model` for the arg-less case). Native `<input>` / `<textarea>` / `<select>` only listen for `input` / `change` events.

5. **Scope markers**: All component roots auto-receive a `data-pp-scope-id` stamp (RFC-063 internal change; no author-facing `pp-data` attribute). This is invisible; don't rely on it in CSS selectors.

6. **Transition presets**: Built-ins are `fade`, `scale`, `fade-scale`, `zoom`, `slide-up`, `slide-down`, `slide-left`, `slide-right`, `collapse`, `none`. Custom presets registered via `pocopine::animate::register_preset` at app boot work everywhere the built-ins do.

7. **Portal targets**: `pp-teleport="body"` and `pp-teleport=".outlet"` resolve the selector once at mount (not reactively); the element must exist in the DOM at that moment.

8. **Modifiers order**: Modifier order doesn't matter (`@click.prevent.stop` ≡ `@click.stop.prevent`), but for readability, event-control modifiers typically come first, then key/system modifiers.

9. **Expression context**: All directive expressions (in quotes: `pp-text="expr"`, `:disabled="expr"`, `@click="handler()"`) execute in the component's scope, with access to `#[state]` fields, `$index` / `$first` / `$last` (in `pp-for`), `$event` (in `pp-on`), and any `pp-let` bindings.

## References

- **Directive registry & parsing**: `crates/pocopine-directives/src/lib.rs` (types: `DirectiveSpec`, `ParsedAttr`, `ArgReq`, `Host`; function: `parse_directive_attr`)
- **Core implementations**: `crates/pocopine-core/src/directives/` (one module per directive: `bind.rs`, `on.rs`, `model.rs`, `if_.rs`, `for_.rs`, `transition.rs`, `anchor.rs`, `roving.rs`, `resize.rs`, `intersect.rs`, `flip.rs`, `teleport.rs`, `text.rs`, `html.rs`, `ref_.rs`, `show.rs`)
- **RFC-013**: Key modifiers on `pp-on` (`rfcs/rfc-013-pp-on-key-modifiers.md`)
- **RFC-020**: `:attr` and `@event` shorthand prefixes (`rfcs/rfc-020-shorthand-prefixes.md`)
- **RFC-063**: Directive cleanup — delete `pp-init`, `pp-cloak`, `pp-data`; converge `pp-let`, `pp-key`, `pp-stagger` (deferred) (`rfcs/rfc-063-directive-cleanup-vue-alignment.md`)
- **Animation guide**: `docs/animation.md` (transition presets, FLIP, custom presets, programmatic WAAPI)
- **Component lifecycle**: `#[handlers]` with `on_setup`, `on_mount`, `on_unmount` lifecycle hooks (see `#[component]` macro docs)
