# pocopine Agent Skills

These are agent skills for working in the **pocopine** framework. Each skill auto-triggers based on its description when a relevant task is detected, loading focused guidance for that domain. Together they span authoring components and templates, building UI and styles, wiring data and backend services, and operating the toolchain.

## Core authoring

| Skill | Use when |
| --- | --- |
| `pocopine-components` | Defining, structuring, or debugging Components — `#[component]`/`#[handlers]` macros, `#[prop]`/`#[model]` fields, templates, lifecycle hooks, and composition patterns. |
| `poco-templates` | Writing or debugging `.poco` template syntax — single-root rules, component tags, SVG namespace support, or template compilation. |
| `poco-directives` | Authoring template directives (`pp-*`) — directive syntax, modifiers, args, host constraints, or migrating from removed directives (`pp-init`/`pp-cloak`/`pp-data`). |
| `poco-expressions` | Writing or debugging `{{expr}}` interpolation and pine-expr expressions — paths, operators, ternary, calls, assignment, and magic variables like `$index`/`$event`/`$store`/`$route`. |
| `slots-and-composition` | Building components with default/named slots, scoped slots with `pp-let`, `pp-as` polymorphic rendering, or multi-component composition. |
| `reactivity-and-stores` | Building state management and reactivity — the reactive model, App stores, and provide/inject context. |

## UI & styling

| Skill | Use when |
| --- | --- |
| `scoped-styles` | Authoring component stylesheets with automatic CSS scoping to a single component. |
| `pine-stylekit` | Building styles with Pine Stylekit, the Pocopine-native utility-CSS compiler, or working with `@theme` tokens and CSS generation in Rust/WASM. |
| `animation-and-motion` | Building enter/leave transitions, layout animations, stagger effects, or spring-physics motion. |
| `pine-icons` | Working with Pine icons — the `icon!` proc macro for compile-time SVG embedding, or the `<pine-icon>` primitive with `register_icons!`. |
| `pine-charts` | Building SVG-first, unstyled, accessible charts — line, area, bar, scatter, pie, or custom layered visualizations. |
| `pine-richtext` | Building rich-text editors with the Pine document model, schema setup, markdown round-trips, or table extensions. |
| `interaction-utilities` | Implementing keyboard navigation, floating positioning, element observation, focus management, scroll locking, or accessibility wiring. |

## Data & backend

| Skill | Use when |
| --- | --- |
| `routing` | Building SPA routes, implementing route guards/loaders, configuring `pp-route` links, or handling route navigation. |
| `server-functions` | Defining typed async server functions with `#[server]`, implementing access policies via guards, and calling them from the wasm client with `dispatch!`. |
| `auth` | Implementing authentication — JWT verification, credentials, OAuth providers, session management, or guards. |
| `storage` | Integrating object storage (S3/GCS/Azure) with resumable uploads, presigned/multipart/sequential strategies, or browser-based uploads. |
| `sync-and-live` | Building offline-first data sync or live invalidation — sync streams, mutations, subscriptions, or multi-tenant filtered queries with local persistence. |
| `background-jobs` | Defining background jobs, enqueueing work, configuring workers, or troubleshooting job execution. |

## Tooling & ops

| Skill | Use when |
| --- | --- |
| `pocopine-cli` | Working with the pocopine-cli — `build`, `dev` watch, `run`, `deploy`, `doctor`, `env`, `js`, `stylekit`, `lsp` commands. |
| `client-modules` | Setting up managed `.client.ts` modules for importing npm SDKs (Firebase, analytics, etc.) with typed Rust facades. |
| `plugins` | Installing app or server plugins — wiring observability, auth, live queries, or other optional integrations. |
| `deploy` | Deploying a full-stack or static app to Fly.io, Railway, Render, or other hosts using the RFC 080 deploy contract. |
| `observability` | Setting up tracing, logging, analytics, or observability events — frontend and backend. |
