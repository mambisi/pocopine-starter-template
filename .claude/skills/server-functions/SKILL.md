---
name: server-functions
description: >-
  Use when defining typed async server functions with `#[server]` macro, implementing access policies via guards, and calling them from the wasm client with `dispatch!` for async state updates.
---

# Server Functions

The `#[server]` proc-macro compiles to two cfg-gated definitions: a **typed JSON client stub** on wasm32 that POSTs to `/_pocopine/<path>`, and a **server-side async handler** plus route auto-registration on the host. Every server function must declare an explicit access policy (`public` or `guard = ...`). The client calls server functions from event handlers via `dispatch!(server_fn().await, |s, result| { /* update state */ })`, which spawns async work and merges the result back into component state.

## When to use

* Calling a database query or external API from the wasm client without hand-writing fetch/route pairs
* Protecting endpoints with bearer tokens, roles, or custom session logic via `#[server(guard = ...)]`
* Merging async server results into component state using `dispatch!` (avoids manual scope/handle plumbing)
* Separating host-only logic (database code) from shared types (request/response DTOs)

## Key API / syntax

### Attribute forms

```rust
#[pocopine::server(public)]
#[pocopine::server(guard = path::to::guard)]
#[pocopine::server(guard = "path::to::guard")]
```

* `public` — intentionally open endpoint; suppresses the missing-policy warning.
* `guard = path` — protect the route; the guard runs **before** the function body and must return `ServerResult<()>`.

### Types

* **`ServerResult<T>`** — alias for `Result<T, ServerError>`; all server functions return this.
* **`ServerError`** — enum with variants: `App(String)`, `Unauthorized(String)`, `Forbidden(String)`, `BadRequest(String)`, `Network(String)` (client-side only).
* **`RequestContext`** — passed to guard functions; contains `method()`, `uri()`, `headers()`, `header(name)`, `bearer_token()`, `cookie(name)`, `session_id()`, and `pub user: Principal`.
* **`Principal`** — auth identity with methods like `is_authenticated()`, `has_role()`, `has_permission()`.
* **`AuthUser`** — user identity struct with `id`, `roles`, `permissions`; inserted into request extensions by middleware.

### Guard contract

A guard is a free async function:

```rust
pub async fn require_user(
    ctx: pocopine::auth::RequestContext,
) -> ServerResult<()> {
    // inspect ctx, return Ok or ServerError
}
```

### Built-in guards

```rust
pocopine::auth::require_login     // any authenticated user
pocopine::auth::require_admin     // admin role
pocopine::auth::require_staff     // staff role
```

Built-in helpers for custom guards:

```rust
pocopine::auth::ensure_login(ctx)              // -> ServerResult<()>
pocopine::auth::ensure_role(ctx, &role)        // -> ServerResult<()>
pocopine::auth::ensure_permission(ctx, &perm)  // -> ServerResult<()>
```

### Dispatch macro

```rust
dispatch!(
    async_expression.await,
    |s, result| {
        // s: &mut Self (the component)
        // result: Result of async_expression
    }
);
```

Spawns async work using the component's scope handle and updates component state when the result arrives. Must be called inside a `#[handlers]` method.

### Protected! macro

Inline role guard — generates a private guard and expands to `#[server(guard = generated)]`:

```rust
pocopine::protected! {
    require |ctx| ctx.user.has_role(Role::admin());

    async fn admin_action(input: Input) -> ServerResult<Output> {
        // protected by admin role
    }
}
```

The `require |ctx| ...` check is synchronous; async auth work belongs in a named guard function.

## Examples

### Public endpoint with client call

**Server (host-only):**

```rust
// examples/blog/src/lib.rs
#[pocopine::server(public)]
pub async fn get_post(post_id: u32) -> ServerResult<Post> {
    match post_id {
        1 => Ok(Post {
            id: 1,
            title: "Hello from pocopine".into(),
            body: "...".into(),
        }),
        _ => Err(pocopine::ServerError::App(format!("no post with id {post_id}"))),
    }
}
```

**Client (wasm):**

```rust
// examples/blog/src/lib.rs
#[handlers]
impl BlogPost {
    pub fn on_mount(&mut self) {
        self.loading = true;
        let post_id = self.post_id;
        dispatch!(get_post(post_id).await, |s, result| {
            s.loading = false;
            match result {
                Ok(p) => {
                    s.title = p.title;
                    s.body = p.body;
                    s.error.clear();
                }
                Err(e) => {
                    s.error = e.to_string();
                }
            }
        });
    }
}
```

The generated route is `POST /_pocopine/get_post_<hash>` with request body `[32]` (the `post_id`). The response is JSON-serialized `Result<Post, ServerError>`.

### Guarded endpoint with bearer token

**Server:**

```rust
// crates/pocopine/tests/server_auth.rs
async fn require_token(ctx: pocopine_server::auth::RequestContext) -> ServerResult<()> {
    match ctx.bearer_token() {
        Some("test-token") => Ok(()),
        Some(_) => Err(ServerError::forbidden("invalid bearer token")),
        None => Err(ServerError::unauthorized("missing bearer token")),
    }
}

#[pocopine::server(guard = require_token)]
async fn guarded_echo(value: String) -> ServerResult<String> {
    Ok(value)
}
```

The route helper `__guarded_echo_route()` is auto-generated and auto-registered by `pocopine_server::Server::new()`. The guard runs before deserialization; a failed guard returns `ServerError::{Unauthorized, Forbidden}` without touching the function body.

### Protected! with inline role check

```rust
// crates/pocopine/tests/server_auth.rs
pocopine::protected! {
    require |ctx| ctx.user.has_role(&Role::admin());

    async fn admin_echo(value: String) -> ServerResult<String> {
        Ok(value)
    }
}
```

The `protected!` macro generates `__pocopine_guard_admin_echo()` internally and emits `#[server(guard = __pocopine_guard_admin_echo)]` on the function.

## Gotchas

* **Missing policy triggers a compile-time warning.** All `#[server]` functions without `public` or `guard = ...` emit `pocopine #[server] function has no access policy`. Plan to migrate existing code; future versions may make this a hard error.
* **Guard runs before body deserialization.** This keeps auth failures from accidentally consuming the JSON payload before the argument extractor runs.
* **ServerError::Network only exists on the client.** The host can only emit `App`, `Unauthorized`, `Forbidden`, `BadRequest`; the wasm client synthesizes `Network` on fetch/decode failures.
* **No `self` or borrowed args.** Server functions must be free async functions with owned arguments only; `Result<T, ServerError>` is the required return type.
* **dispatch! is wasm-only.** The macro expands only in cfg(target_arch = "wasm32"). Host tests use tokio/axum directly.
* **Body limit.** Default is 2 MiB per request. Override via `POCOPINE_SERVER_FUNCTION_BODY_LIMIT` env var (accepts suffixes: `kb`, `kib`, `mb`, `mib`).
* **Route path is deterministic but opaque.** Paths include a content-addressed hash suffix (`/_pocopine/get_post_<hash>`) to avoid collisions across modules. Use the macro-generated `__get_post_path()` function to query the path in tests.
* **Cookies are simple.** `RequestContext::cookie(name)` does not parse RFC 6265 quoted values; use the `cookie` crate for complex cases.
* **Auth middleware runs once per request.** Install via `RouterAuthExt::with_auth()` **after** routes are registered; middleware added afterwards silently bypasses protection.

## References

* **Crates:** `pocopine` (client macro, types), `pocopine-server` (host route installation, auth middleware), `pocopine-auth` (RequestContext, guards, Principal/AuthUser)
* **RFC 066:** Server-function auth and access policy — `/rfcs/rfc-066-server-function-auth.md` (implemented; defines guard contract, policy syntax, and error vocabulary)
* **RFC 002:** Application framework, stores, server functions — `/rfcs/rfc-002-app-stores-servers.md` (original `#[server]` design and dispatch! macro)
* **Examples:** `/examples/blog/src/lib.rs` (public endpoint + dispatch! pattern)
* **Tests:** `/crates/pocopine/tests/server_auth.rs` (guards, protected! macro, RequestContext usage)
* **Host API:** `pocopine_server::install_server_functions()`, `pocopine_server::Server::new()`, `pocopine_server::RouterAuthExt`
