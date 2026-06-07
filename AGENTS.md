# Agent notes

This is a [pocopine](https://github.com/mambisi/pocopine) app — reactive Rust +
WebAssembly, with components authored as a `#[component]` struct paired with a
`.poco` template.

**Framework knowledge is bundled as skills.** `.claude/skills/` contains a guide
for each framework feature (components, templates, `pp-*` directives,
expressions, slots, reactivity/stores, routing, server functions, styling,
animation, icons, charts, richtext, auth, storage, sync, jobs, observability,
the CLI, client modules, plugins, deploy, interaction utilities). They
auto-trigger by topic; see `.claude/skills/README.md` for the index. Prefer them
over guessing framework APIs.

**Dev loop:** `pocopine dev` (build + live reload), `pocopine build` (release),
`pocopine doctor` (toolchain check).

**Conventions:** one `#[component]` struct + a sibling `Name.poco` template;
register components in `main()` via `App::new().register::<T>()`; `#[prop]`
fields come from host-element attributes; `#[handlers]` methods fire from
`@event` bindings; `.poco` templates must have a single root element.
