---
name: interaction-utilities
description: >-
  Use when implementing keyboard navigation, floating positioning, element observation, focus management, scroll locking, or accessibility wiring in pocopine components
---

# Interaction Utilities

## What This Is

Pocopine's **headless interaction primitives** — directives (`pp-roving`, `pp-anchor`, `pp-resize`, `pp-intersect`, `pp-on:click.outside`) and Rust modules (`focus`, `tick`, `scroll_lock`, `id`) — that handle keyboard navigation, floating positioning, DOM observation, focus trapping, scroll locking, and a11y ID generation. All browser-native APIs, zero runtime overhead.

## When to Use

- **Keyboard navigation**: `pp-roving` for arrow-key cycling through items (tabs, menus, toolbars) or `.virtual` mode for combobox activedescendant
- **Floating panels**: `pp-anchor` for dropdowns, tooltips, popovers with auto-flip and offset
- **Dismissal**: `pp-on:click.outside` to close overlays on outside clicks
- **Scroll/resize observation**: `pp-resize` for responsive layout, `pp-intersect` for lazy-load / infinite-scroll / scroll-lock sentinels
- **Focus management**: `focus::trap()`, `focus::save()` / `focus::restore()`, `focus::auto_focus_first()` in dialog / sheet on_mount / on_unmount
- **Scroll blocking**: `scroll_lock::lock()` / `unlock()` ref-counted for nested modals (iOS rubber-band fix, scrollbar compensation)
- **A11y ID wiring**: `$id` magic in templates + `id::current()` in handlers for label/input association, aria-labelledby, role="dialog" relationships

## Key API / Syntax

### Directives (no handler args)

| Directive | Surface | Modifiers | Notes |
|---|---|---|---|
| `pp-roving` | `pp-roving[:<listbox-id>][.<orient>][.<mod>...]` | `.vertical` (default), `.horizontal`, `.both`, `.nowrap`, `.virtual` (activedescendant), `.items.<selector>` (filter items) | Container directive; Tab cycles focusable items; arrow keys navigate per orientation |
| `pp-anchor` | `pp-anchor:<placement>[.<mod>...]="<anchor>"` | `.offset.<N>`, `.flip`, `.same-width` | Placement: `top/bottom/left/right` + `start/center/end`; computes `position: fixed`; auto-repositions on scroll/resize |
| `pp-on:click.outside` | `@click.outside="handler"` | compose with `.stop`, `.once`, `.debounce[.ms]` | Capture-phase listener on `document`; fires when target outside the host element |

### Directives (handler args — `f64`)

| Directive | Handler Signature | Modifiers | Notes |
|---|---|---|---|
| `pp-resize` | `fn on_resize(&mut self, width: f64, height: f64)` | `.document` (observe documentElement), `.border-box` (instead of content-box) | ResizeObserver; fires on initial observe + every size change |
| `pp-intersect` | `fn on_show(&mut self)` or `fn on_show(&mut self, ratio: f64)` | `.once`, `.threshold.<0-100>`, `.margin.<val1>[.<val2>...]` (CSS margin syntax: px, %, or bare number) | IntersectionObserver; `.enter` / `.leave` arg variants; fires on visibility threshold |

### Rust Modules

**`pocopine::focus`**
```rust
focus::save() -> Saved
focus::restore(saved: Saved)            // no-op if element detached
focus::blur()                            // blur activeElement
focus::auto_focus_first(&el) -> bool
focus::trap(&el) -> TrapHandle           // install focus trap; release() or drop
focus::focus_no_scroll(&el)              // focus() without scrollIntoView
focus::FOCUSABLE_SELECTOR: &str          // reusable selector
```

**`pocopine::tick`**
```rust
tick::next<F: FnOnce() + 'static>(f: F)        // microtask (after sync, before paint)
tick::next_frame<F: FnOnce() + 'static>(f: F)  // requestAnimationFrame
```

**`pocopine::scroll_lock`**
```rust
scroll_lock::lock()     // 0→1 transition: pin scroll, `overflow: hidden`, pad-right compensation
scroll_lock::unlock()   // 1→0 transition: restore body styles; saturating at 0
scroll_lock::depth() -> u32
```

**`pocopine::id`**
```rust
id::current() -> Option<String>  // inside handler; returns $id of the current scope
id::generate(scope: ScopeId) -> String  // rarely called directly; use $id magic in templates
```

### Template Magic

**`$id`** — per-component-instance unique string (`pp-1`, `pp-2`, …); read once and cached. No reactivity.
- Compose via `+`: `$id + '-input'`, `$id + '-tab-' + i`
- Access in handlers via `id::current()`

## Examples

### 1. Roving Tablist with Horizontal Arrow Keys

**`PineTabsList.poco`** (real file path: `/crates/pine/src/tabs/PineTabsList.poco`)
```html
<root role="tablist"
      class="pine-tabs-list"
      :aria-orientation="orientation"
      pp-roving.horizontal>
  <slot></slot>
</root>
```
Tab stops on the list; Left/Right arrow keys cycle tabs; Shift+Home/End move to first/last.

### 2. Context Menu with Roving and Click-Outside Dismiss

**`PineContextMenuContent.poco`** (real file path: `/crates/pine/src/context_menu/PineContextMenuContent.poco`)
```html
<root role="menu"
      class="pine-context-menu-content"
      pp-ref="menu"
      pp-roving
      data-state="open"
      :style="'position:fixed;top:' + pointer_y + 'px;left:' + pointer_x + 'px;'"
      @click.outside="close"
      @keydown.escape.prevent="close">
  <slot></slot>
</root>
```
Arrow keys navigate menu items; click outside or Escape closes.

### 3. Dialog with Focus Trap, Scroll Lock, and $id Wiring

**Rust handler** (pattern from RFC-014):
```rust
#[handlers]
impl PineDialog {
    pub fn on_mount(&mut self) {
        use pocopine::{focus, tick, scroll_lock};
        
        self.focus_saved = Some(focus::save());
        scroll_lock::lock();
        
        if let Some(root) = refs::get("root") {
            self.focus_trap = Some(focus::trap(&root));
            tick::next(move || {
                focus::auto_focus_first(&root);
            });
        }
    }
    pub fn on_unmount(&mut self) {
        use pocopine::scroll_lock;
        scroll_lock::unlock();
        if let Some(trap) = self.focus_trap.take() {
            trap.release();
        }
        focus::blur();
        if let Some(saved) = self.focus_saved.take() {
            focus::restore(saved);
        }
    }
}
```

**Template** (RFC-018 `$id` for a11y):
```html
<div role="dialog"
     pp-bind:id="$id"
     pp-bind:aria-labelledby="$id + '-title'"
     pp-bind:aria-describedby="$id + '-desc'"
     pp-ref="root">
  <h2 pp-bind:id="$id + '-title'"><slot name="title" /></h2>
  <p pp-bind:id="$id + '-desc'"><slot name="description" /></p>
  <slot />
</div>
```

### 4. Dropdown Menu with Anchor Positioning

**Rust side** (`refs::get` resolves the trigger for `pp-anchor`):
```rust
#[handlers]
impl AppMenu {
    pub fn toggle(&mut self) {
        self.open = !self.open;
    }
}
```

**Template**:
```html
<div class="app-menu">
  <button pp-ref="trigger" @click="toggle">
    Account ▾
  </button>
  
  <template pp-teleport="body" pp-if="open">
    <div pp-anchor:bottom-end.offset.6.flip="trigger"
         class="menu-panel"
         pp-on:click.outside="open = false"
         @keydown.escape="open = false">
      <!-- menu items with pp-roving -->
      <button pp-roving>Profile</button>
      <button pp-roving>Settings</button>
      <button pp-roving @click="logout">Sign out</button>
    </div>
  </template>
</div>
```

### 5. Responsive Layout with pp-resize

```rust
#[handlers]
impl Responsive {
    pub fn on_resize(&mut self, w: f64, _h: f64) {
        self.cols = if w < 640.0 { 1 }
                    else if w < 1024.0 { 2 }
                    else { 3 };
    }
}
```

```html
<div class="grid" pp-resize="on_resize"
     :style="`grid-template-columns: repeat(${cols}, 1fr)`">
  <!-- grid cells -->
</div>
```

### 6. Infinite-Scroll Sentinel with pp-intersect

```rust
#[handlers]
impl Feed {
    pub fn load_more(&mut self) {
        if self.loading { return; }
        self.loading = true;
        // dispatch fetch and extend items
    }
}
```

```html
<ul>
  <li pp-for="item in items" pp-text="item.title"></li>
</ul>
<div class="sentinel" pp-intersect.margin.200px="load_more"></div>
```
Fires when the sentinel comes within 200px of the viewport.

### 7. Combobox with Virtual Roving (activedescendant)

```html
<input role="combobox"
       type="text"
       aria-controls="opts"
       pp-roving:opts.virtual
       @keydown.enter="select_active" />

<ul id="opts" role="listbox">
  <li role="option" id="opt-1">Apple</li>
  <li role="option" id="opt-2">Banana</li>
</ul>
```
Arrow keys move `aria-activedescendant` on the input and set `data-highlighted="true"` on each option; DOM focus stays on the input so the caret doesn't move.

## Gotchas

### Focus & Tick
- **`focus::trap` stacking**: Innermost trap (most recently installed) wins; prior traps' listeners stay active but the newest one re-anchors focus. Drop the handle to release cleanly.
- **`tick::next` vs `tick::next_frame`**: Use `next()` after reactive updates (after `set_state`), `next_frame()` when you need layout already resolved (e.g., read `getBoundingClientRect`). `pp-anchor` uses `next()` to let CSS apply before measuring.
- **`focus::auto_focus_first` returns `bool`**: If false, no focusable child found; authors can fallback to `focus_no_scroll(&container)`.

### Anchor Positioning
- **Floater not yet laid out**: `getBoundingClientRect()` returns a zero-rect on first paint; pair with `pp-transition` enter-start class to hide until first reposition.
- **Teleported anchor**: Works fine — id/selector lookup is document-wide. Keep anchor + floater in sync with `pp-if="open && anchor_present"` to avoid snapping to (0,0).
- **ResizeObserver on both anchor and floater**: Reposition triggers on either's resize; window scroll/resize also trigger. Efficient but document-wide — multiple anchors are independent.

### Roving Navigation
- **Base roving (tabindex mode)**: Focus transfers to items; initial tabindex state checks `[tabindex="0"]` (author can pre-set preferred start). No handler args.
- **Virtual roving (`.virtual`)**: Requires `:<listbox-id>` argument pointing to the listbox's DOM id. Host stays focused; items get `data-highlighted`. Hidden items skipped (checked: `[hidden]`, `display: none`, `aria-hidden="true"`). Auto-stamp missing ids as `data-pine-roving-id="pine-roving-{n}"`.
- **Item filtering (`.items.<selector>`)**: Default is `[role="option"]` in virtual, focusable elements in base mode.

### Resize & Intersect
- **`pp-resize` on document**: `.document` swaps the target to `documentElement` (whole viewport), not the host. Each directive instance has its own observer — independent.
- **`pp-intersect` with `.once`**: Disconnects after the first *matching* fire (enter or leave). `.leave.once` still requires at least one `:enter` first.
- **Threshold/margin parsing**: Unknown modifiers silently ignored. `.threshold.<N>` where N is `0–100` (percentage). `.margin` accepts `px`, `%`, or bare numbers (treated as px).
- **`pp-intersect` on initially off-screen elements**: Synthetic initial callback fires with `isIntersecting=false`; `.leave` won't fire until after a true `:enter` to avoid spurious early fires.

### Scroll Lock
- **Ref-counting**: Every `lock()` increments; every `unlock()` decrements (saturating at 0). Nested overlays call lock/unlock symmetrically; the counter ensures the scroll stays locked until the outermost overlay closes.
- **Scrollbar compensation**: Measures `window.innerWidth - documentElement.clientWidth` to get the true gutter width, pads `body.padding-right` to prevent layout shift.
- **Existing `overflow: hidden`**: Measured gutter is 0; no padding added; counter still increments so `unlock()` works.

### ID Magic (`$id`)
- **Frozen at mount**: Reading `$id` caches the value per component instance. Two bindings see the same string; no reactivity.
- **Handler access**: `id::current()` returns `Option<String>` — `None` outside a handler. Check before using.
- **Loop scopes**: Each `pp-for` iteration is a separate scope; each iteration gets its own unique `$id`. Correct for keyed lists.
- **Cache cleared on unmount**: `Scope::remove` calls `id::clear_scope()`, so long-lived pages don't leak cache entries.

### Click-Outside
- **Capture phase**: Listener attaches to `document` with `capture: true` so it fires before other handlers and can't be suppressed by `stopPropagation()` on descendants.
- **Teleported overlays**: If the overlay is teleported to `<body>`, clicks inside it still fire `:outside` on the trigger (the overlay isn't in the trigger's subtree). Authors ensure the overlay's own click handlers suppress propagation or re-target properly.
- **Modifiers**: `.prevent` is ignored (would break page navigation). `.stop` is honoured. `.self` + `.outside` is nonsensical (never fires).

## References

**Directives & Modules**:
- RFC-014 (focus utilities): `crates/pocopine-core/src/focus.rs`, `crates/pocopine-core/src/tick.rs`
- RFC-015 (pp-anchor): `crates/pocopine-core/src/directives/anchor.rs`
- RFC-016 (pp-resize / pp-intersect): `crates/pocopine-core/src/directives/resize.rs`, `crates/pocopine-core/src/directives/intersect.rs`
- RFC-017 (pp-on:click.outside): `crates/pocopine-core/src/directives/on.rs`
- RFC-018 (id magic): `crates/pocopine-core/src/id.rs`
- RFC-021 (scroll_lock): `crates/pocopine-core/src/scroll_lock.rs`
- RFC-034 (pp-roving.virtual): `crates/pocopine-core/src/directives/roving.rs`

**Directive Registry & Parsing**:
- `crates/pocopine-directives/src/lib.rs` — live directive specs, modifiers, removed directives, parse_directive_attr

**Pine Components** (real-world examples):
- `crates/pine/src/tabs/PineTabsList.poco` — roving.horizontal
- `crates/pine/src/context_menu/PineContextMenuContent.poco` — roving + click.outside + keydown.escape
- `crates/pine/src/popover/mod.rs` — anchor + click.outside + focus trap pattern
- `crates/pine/src/scroll_area/PineScrollAreaViewport.poco` — resize observer for responsive layout

**Expression Evaluator**:
- `crates/pocopine-core/src/expr.rs` — `$id` magic, `+` operator (string concat / numeric add)
- `crates/pocopine-core/src/magics.rs` — magic variable resolution

**Composition with Other Directives**:
- `pp-ref` — store elements for focus/anchor resolution
- `pp-teleport` — portal rendering (essential for anchored overlays, focus traps)
- `pp-if` / `pp-show` — conditional visibility (affects hidden-item detection in roving.virtual)
- `pp-transition` — pair with anchor/roving for smooth animations
- `@keydown`, `@click` — keyboard/mouse events that compose with roving, anchor, scroll-lock patterns
