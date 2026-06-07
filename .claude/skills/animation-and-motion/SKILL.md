---
name: animation-and-motion
description: >-
  Use when building enter/leave transitions, layout animations, stagger effects, or spring-physics motion in pocopine components
---

pocopine provides three layers of animation: CSS-class-based transitions on mount/unmount, layout animation (FLIP) for reorders, and programmatic WAAPI + spring physics via `pine-motion`.

## Key API / syntax

**Declarative (RFC-038 / RFC-039):**
- `pp-transition="<preset>"` — symmetric enter + leave (shorthand on element or `#[component(transition = …)]`)
- `pp-transition:in="<preset>" pp-transition:out="<preset>"` — asymmetric (or `transition_in` / `transition_out` macro args)
- `pp-transition:enter`, `:enter-start`, `:enter-end`, `:leave`, `:leave-start`, `:leave-end` — six-phase class attributes
- `pp-flip` — layout animation on any element; watches DOM mutations and FLIP-animates position shifts
- `animate="flip"` — keyed `pp-for` reorder animation on components
- `data-pp-motion="always" | "reduce"` — per-element motion preference override

**Preset names:** `fade`, `scale`, `fade-scale`, `zoom`, `slide-up`, `slide-down`, `slide-left`, `slide-right`, `collapse`, `none`

**Programmatic (pocopine::animate):**
- `animate(el, keyframes, options) -> AnimationHandle` — Web Animations API wrapper
- `apply_preset(el, in_name, out_name)` — stamp preset onto element
- `flip_from_snapshot(el, old_rect, opts)` — manual FLIP
- `enter_subtree_staggered(root, stagger_ms, on_done)` — sequenced reveals
- `motion::effective_for(el) -> MotionPreference` — read prefers-reduced-motion

**pine-motion (higher-level):**
- `Spring::visual(duration_s, bounce)` / `Spring::physics(stiffness, damping, mass)` — GPU-sampled springs
- `Easing::Spring(s)` / `Easing::APPLE` / `Easing::EASE_OUT_QUAD` — named + spring timing
- `Stagger::new(each_ms).from(Origin::Center)` — stagger config
- `drag(el, DragConfig)` — element-follows-pointer with momentum

## Examples

**1. Component with default transition:**
```rust
#[derive(Default, Serialize, Deserialize)]
#[component(template = "MyPanel.poco", transition = "fade-scale")]
pub struct MyPanel {
    #[prop] pub open: bool,
}
```
Mount via `pp-if` and the `fade-scale` preset runs automatically. (RFC-038)

**2. Six-phase class transition in template (hn/src/components/story_detail/StoryDetail.poco):**
```html
<div pp-transition:enter="pp-fade-enter"
     pp-transition:enter-start="pp-fade-enter-start"
     pp-transition:enter-end="pp-fade-enter-end"
     pp-transition:leave="pp-fade-leave"
     pp-transition:leave-start="pp-fade-leave-start"
     pp-transition:leave-end="pp-fade-leave-end">
  <!-- content -->
</div>
```
Author defines CSS classes; directive swaps them through enter/leave phases.

**3. FLIP layout animation on list reorder:**
```html
<ul pp-flip-container>
  <template pp-for="item in items" pp-key="item">
    <li pp-flip>{item}</li>
  </template>
</ul>
```
Registers each `<li>` for layout animation. On reorder, MutationObserver detects shift and animates position delta.

**4. Programmatic WAAPI with spring (pine-motion):**
```rust
use pine_motion::{animate, Spring};

animate(
    &el,
    &[("opacity", "0", "1"), ("transform", "scale(0.8)", "scale(1)")],
    Spring::visual(0.3, 0.25).into_timing(), // sampled to linear(...) for GPU
);
```

## Gotchas

- **Presets are CSS-class-based.** Each preset is three atom CSS classes (`pp-tx-<name>-base`, `-from`, `-to`) stamped onto the six `pp-transition:*` attributes. The attribute names are fixed; customize durations/easing via CSS custom properties (`--pp-tx-duration`, `--pp-tx-<name>-duration`).
- **prefers-reduced-motion is respected by default.** Transitions fire synchronously when the user prefers reduced motion (or set `data-pp-motion="always"` on the element). WAAPI respects `respect_motion_preference: true` in `AnimateOptions` (default).
- **pp-flip tracks DOM mutations only.** Font load, scrollbar appearance, or CSS-only layout shifts need `pp-resize` (ResizeObserver path deferred; see RFC-039 §7).
- **Class persistence on settle.** After `pp-transition:enter` completes, the base + end classes remain on the element to avoid flicker. They clear on the next `enter()` call or in `leave()`.
- **FLIP cancels previous animation.** Rapid reorders on the same element cancel the in-flight FLIP and start a new one from the current position.
- **stagger_ms in macro deferred.** Use `pocopine::animate::enter_subtree_staggered(root, 30, cb)` directly; the `#[component(stagger_ms = N)]` macro arg is not yet implemented (RFC-039 §6).
- **Duration timeout has 1s safety backstop.** `leave_subtree` times out after 1000ms if a competing call cancels leaves; this keeps leaked clones from lingering indefinitely.

## References

- **RFCs:** RFC-038 (native animations, presets, FLIP), RFC-039 (v2 enhancements, prefers-reduced-motion, pp-flip, stagger)
- **Crates:**
  - `crates/pocopine-core/src/directives/transition.rs` — six-phase state machine
  - `crates/pocopine-core/src/directives/flip.rs` — pp-flip directive
  - `crates/pocopine-core/src/animate/mod.rs` — public API surface
  - `crates/pocopine-core/src/animate/motion.rs` — prefers-reduced-motion detection
  - `crates/pocopine-core/src/animate/waapi.rs` — WAAPI wrapper + AnimationHandle
  - `crates/pocopine-core/src/animate/presets.rs` — preset registry + atoms
  - `crates/pine-motion/src/spring.rs` — spring physics + sampling
  - `crates/pine-motion/src/easing.rs` — named easings + linear-easing sampler
  - `crates/pine-motion/src/stagger.rs` — stagger + origin modes
- **Docs:** `docs/animation.md` (high-level guide), `docs/animation-perf.md` (RFC-039 §3 cache justification)
- **Examples:** `examples/keep/src/components/auth_gate/KeepAuthGate.poco` (preset usage), `examples/hn/src/components/story_detail/StoryDetail.poco` (six-phase attributes)
