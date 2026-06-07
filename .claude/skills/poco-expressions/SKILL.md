---
name: poco-expressions
description: >-
  Use when writing or debugging {{expr}} interpolation and pine-expr expressions in .poco templates (paths, operators, ternary, calls, assignment, magic variables like $index/$event/$store/$route).
---

# Pocopine Template Expressions (pine-expr)

## What this is

Pine-expr is pocopine's small, intentional expression language embedded in `.poco` template attributes and text interpolation. It supports paths, comparisons, logical operators, ternary, `+` concatenation, function calls, and assignment—but deliberately excludes arithmetic, method chaining, and JS globals to keep logic in Rust where the toolchain can reach it.

## When to use

- **Text interpolation**: `{{name}}`, `{{count > 0 ? 'items' : 'empty'}}` (RFC-040, double-brace)
- **Directive expressions**: `pp-show="!loading && error"`, `pp-bind:class="open ? 'is-open' : ''"`, `pp-if="role == 'admin'"`
- **Event handlers**: `@click="select(item.id)"`, `@click="open = !open"` (RFC-024)
- **Conditional & loop bindings**: `pp-key="item.id"`, anywhere an expression is needed

The expression grammar is unified: every `pp-*` directive value uses the same parser and evaluator.

## Key API / syntax

### Literals & access

- **Path**: `count`, `user.name`, `item.id` (dotted segments, no computed properties)
- **Literals**: `true`, `false`, `null`, numbers (`42`, `3.14`, `-1`), strings (`"hi"` or `'hi'`)
- **`$` magic variables**: `$index`, `$first`, `$last` (in `pp-for`), `$event` (in `pp-on`), `$el`, `$refs`, `$dispatch`, `$store`, `$route`, `$id`

### Operators (lowest to highest precedence)

- **Logical**: `||` (short-circuit), `&&` (short-circuit), `!` (unary not)
- **Comparison**: `==`, `!=`, `<`, `<=`, `>`, `>=` (strict value compare for `==`/`!=`; numeric for relations)
- **Ternary**: `cond ? a : b` (right-associative)
- **Addition**: `+` (string concat if either operand is a string; numeric add if both coerce to `f64`)
- **Parentheses**: `(expr)` to override precedence

### Calls & assignment (handler context only)

- **Call**: `handler_name(arg1, arg2, ...)` — invokes scope method, args are expressions
- **Assignment**: `field = expr` or `obj.field = expr` — writes through scope proxy's `set` trap (only in `@click`/`pp-on`)
- **Sequence**: `a; b; c` — semicolon-separated statements, evaluates left-to-right, result is last statement

### Text interpolation (RFC-040)

- **Double-brace syntax**: `{{expr}}` — delimit expressions in text. Single `{` is always literal.
- **Escape**: `\{{` → literal `{{` (rare, mostly in code samples)

## Examples

**Conditional visibility** (RFC-012):
```html
<!-- /home/zempare-mambisi/RustProjects/pocopine/examples/hn/src/components/story_list/StoryList.poco -->
<p pp-show="!loading && applied_query" class="status">…</p>
<template pp-if="kind == 'text'">…</template>
```

**Ternary in binding** (RFC-012):
```html
<!-- /home/zempare-mambisi/RustProjects/pocopine/examples/website/src/components/showcase/collapsible/CollapsibleDemo.poco -->
<span pp-text="open ? 'Hide details' : 'Show details'"></span>
<strong>Currently {{open ? 'open' : 'closed'}}.</strong>
```

**Handler calls & assignment** (RFC-024):
```html
<!-- /home/zempare-mambisi/RustProjects/pocopine/examples/keep/src/components/note_form/KeepNoteForm.poco -->
<button :data-on="color == 'coral'" @click="pick_color('coral')"></button>
<!-- In a simpler example: -->
<button @click="open = !open">Toggle</button>
<button @click="select(item.value); close()">Select & close</button>
```

**Magic variables in loops** (RFC-004):
```html
<template pp-for="story in stories" pp-key="story.id">
  <li class="story">
    <a pp-bind:href="story.url" pp-text="story.title"></a>
    <small pp-show="$index > 0">rank {{$index}}</small>
  </li>
</template>
```

**Store & route access**:
```html
<!-- /home/zempare-mambisi/RustProjects/pocopine/examples/keep/src/components/list_detail/KeepListDetail.poco -->
<template pp-for="row in $store.keep.pinned_notes" pp-key="row.key">…</template>
<h2 pp-show="$store.keep.section_kind == 'notes'">Notes</h2>
```

## Gotchas

### What does NOT work (intentional restrictions)

- **Arithmetic beyond `+`**: no `-`, `*`, `/`, `%`. Compute in Rust as `#[computed]` field.
- **Method calls**: `obj.method()`, `arr.length`, `str.slice()` all invalid. Use computed fields or handlers.
- **JS strict equality**: `===` and `!==` rejected. Use `==` and `!=` (pine-expr uses Rust-style equality).
- **Optional chaining / nullish coalescing**: `a?.b`, `a ?? b` not supported. Use ternary: `a == null ? fallback : a`.
- **Arrow functions, spread, regex**: not in the grammar.
- **Globals**: no `Math.*`, `Date.*`, `JSON.*`, `console.*`.

### Error handling

- **Parse errors** fire at `cargo check` time via proc-macro validation (RFC-054). The compiler prints the span and a helpful message pointing to the `.poco` file.
- **Runtime errors** (unknown handler, path not found) silently no-op — same contract as misspelled handlers today.
- **Short-circuit evaluation** in `&&`, `||`, `?:` — un-taken branches don't evaluate and don't track dependencies, so re-runs clear prior subscriptions naturally.

### Assignment gotcha (RFC-024)

- `path = expr` only works in handler context (`@click`, `pp-on:event`), not in `pp-text`/`pp-bind`/`pp-show`.
- Assigning to nested paths (`user.name = 'x'`) mutates the intermediate object; outer-key reactivity doesn't auto-trigger. For v0, assign flat fields or dispatch to a handler.

### Where computation belongs (the convention)

If you reach for an expression that doesn't parse:

1. **Pure derivation**: write `#[computed] fn done_count(items: Vec<Item>) -> usize { ... }`, then bind `pp-text="done_count"`.
2. **Needs self** (touches other fields, calls store): use `#[watch(field)]` or a plain handler method.
3. **User-action-only**: compute in the handler that handles the action.

This keeps Rust-analyzer, clippy, tests, and rename working on your logic.

## References

- **RFC-012**: Expression evaluator (paths, comparisons, logical, ternary) — `/home/zempare-mambisi/RustProjects/pocopine/rfcs/rfc-012-expression-evaluator.md`
- **RFC-024**: Call + assignment + sequences — `/home/zempare-mambisi/RustProjects/pocopine/rfcs/rfc-024-expression-values.md`
- **RFC-040**: Double-brace text interpolation `{{…}}` — `/home/zempare-mambisi/RustProjects/pocopine/rfcs/rfc-040-text-interpolation-double-brace.md`
- **RFC-004**: `pp-for` loops, `$index`/`$first`/`$last` — `/home/zempare-mambisi/RustProjects/pocopine/rfcs/rfc-004-pp-for.md`
- **Parser & AST**: `crates/pocopine-expr/src/lib.rs` — grammar, lexer, parser, all `Expr` variants
- **Evaluator**: `crates/pocopine-core/src/expr.rs` — runtime evaluation, scope proxy integration
- **Magics**: `crates/pocopine-core/src/magics.rs` — `$el`, `$refs`, `$dispatch`, `$event`, `$store`, `$route`, `$id`
- **Loops**: `crates/pocopine-core/src/loop_scope.rs` — `$index`, `$first`, `$last` resolution
- **Docs**: `docs/poco/04-expressions.md` — surface, conventions, derived fields (`#[computed]`, `#[watch]`)
