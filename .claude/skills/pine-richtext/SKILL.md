---
name: pine-richtext
description: >-
  Use when building Rust/WASM rich-text editors with the Pine document model, schema setup, markdown round-trips, or table extensions
---

# Pine Richtext — Core Components & Extension Contract

Pine-richtext is a Rust-native rich-text document model, transform engine, and editor state layer ported from ProseMirror. It provides a schema-based type system, atomic transforms (replace, mark, wrap, lift), undo/redo via the history plugin, and markdown I/O via extension-supplied emitters and parse rules. The optional `view` feature adds a browser DOM editor surface and Pocopine component integration.

## Key API / Syntax

### Document Model

- **`Schema`** — type system declaring node specs, mark specs, and content expressions (e.g., `content("paragraph+")`). Built via `RuntimeBuilder::new().with(extensions).build()`.
- **`Node`** — immutable tree node with `type_name()`, `attrs()`, `content()`, `marks()`. Fragments use `Arc<Vec<Node>>` for cheap cloning.
- **`Fragment`** — ordered list of child nodes. Mutations via `push()`, `replace_child()` trigger copy-on-write.
- **`Mark`** — inline formatting (strong, em, link, code, custom). Added/removed atomically across ranges.
- **`Slice`** — tree fragment with `open_start` / `open_end` describing partially-open contexts (used in paste, wrap, lift).
- **`ResolvedPos`** — position + full path through tree depths. Built via `doc.resolve(pos)?`, exposes `parent()`, `index(depth)`, `before(depth)`, `after(depth)`.

### Transforms

- **`Transform::replace(from, to, slice)`** — core primitive: delete `[from..to]`, insert `slice`. Runs through a fitter chain that auto-wraps/unwraps to match schema.
- **`Transform::mark(from, to, mark, add)`** — add or remove a mark across a range.
- **`Transform::attr(pos, attr, value)`** — set a node attribute.
- **`Transform::wrap(from, to, node_type, attrs)`** — wrap range in a block. Decomposes to `ReplaceAroundStep` for mapping stability.
- **`Transform::lift(from, to, depth)`** — lift range out of its ancestors up to `depth`. Splits wrappers at each level.
- **`Step`** — immutable instruction: `Replace`, `ReplaceAround`, `AddMark`, `RemoveMark`, `Attr`, `DocAttr`. Serializes to JSON for wire transfer.
- **`StepMap` & `Mapping`** — position tracking across a chain of steps. Used for undo/redo and collaboration.

### Editor State

- **`EditorState`** — document + selection + transaction history. Built via `EditorStateConfig::new(schema)`.
- **`Selection`** — text range or node selection. Stable across mapping.
- **`Transaction`** — mutable builder; collects steps, applies them on `state.apply(tr)`.
- **`Plugin`** — per-state hook for metadata (history, decoration, input rules). Registered via extension.

### Markdown I/O (via Extension Contract)

- **`RichTextExtension::markdown_node_emitters()`** — map custom node types to `NodeEmitter` closures. Each emitter receives `&Node`, parent, index, and `EventSink` to push `pulldown_cmark::Event`s.
- **`RichTextExtension::markdown_parse_rules()`** — vector of `MarkdownParseRule`. Each rule claims a `ParseMatch` (a `pulldown_cmark::Tag` or `Event::*` variant) and maps to `ParseMapping`:
  - **`ParseMapping::Block`** — open a container builder (e.g., table, blockquote).
  - **`ParseMapping::Mark`** — push an inline mark for the scope.
  - **`ParseMapping::LeafNode`** — emit an atomic leaf (e.g., image, horizontal rule).
  - **`ParseMapping::Custom`** — escape hatch callback for contextual logic (e.g., task-list marker flagging).
- **`ParseSink`** — mutable handle passed to `Custom` callbacks; provides `set_current_item_attr()`, `flag_enclosing_list_as_task()`, schema access.
- **`EventSink`** — mutable handle passed to `NodeEmitter`; provides `push(event)`, `render_content(node)`, `render_node(node, parent, index)`.

### Tables (RFC 079)

Tables are **opt-in** via a `TablesExtension` implementing the markdown C4 contract. Schema nodes:

- **`table`** — top-level block. Attr `alignments: Vec<Option<Alignment>>` stores per-column alignment (left/center/right/default).
- **`table_row`** — direct child of table. Contains cells only.
- **`table_header_cell`** — first row's cells (rendered `<th>`).
- **`table_cell`** — body-row cells (rendered `<td>`).

Commands: `insert_table { rows, cols }`, `insert_row_above`, `insert_row_below`, `insert_column_left`, `insert_column_right`, `delete_row`, `delete_column`, `delete_table`. Key bindings: `Tab` advances cell (appends row at end), `Shift-Tab` retreats, `Enter` inserts hard break (cells are inline-only).

Markdown: Tables serialize/parse as GFM `|---|` pipe-format. No rowspan/colspan. Alignment stored in table attrs, rendered via `style="text-align:..."` per cell.

## Examples

### Setting up a runtime with extensions

```rust
// /home/zempare-mambisi/RustProjects/pocopine/examples/richtext/src/lib.rs (lines 20-26)
use pine_richtext::extensions::{
    CoreMarksExtension, MarkdownShortcutsExtension, SmartTypographyExtension, TaskListExtension,
};
use pine_richtext::runtime::{self, RuntimeBuilder};

let doc_runtime = RuntimeBuilder::new()
    .name("doc")
    .with(CoreNodesExtension)
    .with(ListsExtension)
    .with(TaskListExtension::new())
    .with(CoreInlineExtension)
    .with(CoreMarksExtension)
    .with(HistoryExtension)
    .build();
runtime::registry::register("doc", doc_runtime);
```

### Markdown emitter for a custom node type

```rust
// /home/zempare-mambski/RustProjects/pocopine/crates/pine-richtext/src/extensions/task_list.rs (lines 142–172)
fn markdown_node_emitters(&self) -> Vec<(String, NodeEmitter)> {
    vec![
        (
            "task_item".into(),
            Arc::new(|node, _parent, _index, sink: &mut EventSink<'_>| {
                let checked = node.attrs()
                    .get("checked")
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false);
                sink.push(MdEvent::Start(MdTag::Item));
                sink.push(MdEvent::TaskListMarker(checked));  // GFM [ ] or [x]
                sink.render_content(node);
                sink.push(MdEvent::End(MdTagEnd::Item));
            }),
        ),
    ]
}
```

### Markdown parse rule for a table-like block

```rust
// RFC 079 example (conceptual; not yet implemented in examples)
fn markdown_parse_rules(&self) -> Vec<MarkdownParseRule> {
    vec![
        MarkdownParseRule {
            matches: ParseMatch::Tag(TagKind::Table),
            maps_to: ParseMapping::Block {
                node_type: "table".into(),
                get_attrs: Some(Arc::new(|event| {
                    let mut attrs = Attrs::new();
                    if let Event::Start(Tag::Table(alignments)) = event {
                        let v: Vec<Value> = alignments.iter()
                            .map(|a| alignment_to_json(a))
                            .collect();
                        attrs.insert("alignments".into(), json!(v));
                    }
                    attrs
                })),
            },
        },
    ]
}
```

### Dispatching a transform in a handler

```rust
// /home/zempare-mambski/RustProjects/pocopine/examples/richtext/src/lib.rs (lines 127–135)
pub fn wrap_in_blockquote(&mut self) {
    self.with_editor(|e| {
        e.dispatch(CommandRequest::WrapIn {
            node_type: "blockquote".into(),
            attrs: Attrs::new(),
        })
    });
}
```

## Gotchas

- **Fragments use `Arc<Vec<Node>>`**: clones are refcount bumps, not deep copies. Preserve this invariant; removing `Arc` regresses benchmarks ~20,000×.
- **Mark exclusion defaults to self-exclusion**: `MarkSpec::new("em")` auto-excludes other "em" marks. Call `.excludes("")` to allow stacking.
- **Table support is opt-in**: without a `Table` parse rule, GFM pipe-table markdown is silently dropped and treated as plain text. Enable tables via extension.
- **Defining-context nodes are special**: `NodeSpec { defining_for_content: true }` (blockquote, code_block, list_item) preserve their structure on paste instead of unwrapping. Don't set this flag unless semantically necessary.
- **Markdown round-trip idempotence**: `parse(serialize(doc))` must equal the original doc. Non-GFM markdown features (merged cells, nested blocks in table cells, captions) cannot round-trip.
- **Selection invariants**: cross-cell text selections are allowed, but operations treat each cell independently. Node selection on a table cell is valid (used by delete-row/delete-column).
- **The replace pipeline runs fitters in order**: defining-context fitters must run before the plain replace, otherwise wrapped slices unwrap into the cursor's paragraph.

## References

- **Crate**: `crates/pine-richtext` — model, transform, state, extensions, markdown, history, view.
- **RFC 079**: `/rfcs/rfc-079-pine-richtext-tables-extension.md` — schema, commands, key bindings, markdown emit/parse, DOM rendering for tables.
- **Architecture guide**: `crates/pine-richtext/docs/ARCHITECTURE.md` — ResolvedPos, Fragment refcount trick, replace pipeline, step mapping, wrap/lift, mark exclusion, defining-context merge.
- **Extensions guide**: `crates/pine-richtext/docs/extensions.md` — runtime builder, extension contract, node-view components, backward compatibility.
- **Example**: `examples/richtext` — kitchen-sink demo with two runtimes (doc editor + minimal comment box), toolbar commands, markdown import/export, task-list custom element.
