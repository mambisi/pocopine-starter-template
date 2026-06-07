---
name: plugins
description: >-
  Use when installing app or server plugins—wiring observability, auth, live queries, or other optional integrations into a pocopine app.
---

# App & Server Plugins in Pocopine

Pocopine provides a first-class plugin system for both frontend (`AppPlugin`) and backend (`ServerPlugin`) to inject optional integrations—observability, auth, live queries, devtools—without editing core or copying boilerplate.

## When to Use

- **App plugins**: Installing analytics, auth session UI, logging, live-query clients, or devtools into a compiled or builder-style `App`.
- **Server plugins**: Adding HTTP request telemetry, tracing layers, health endpoints, server-function hooks, or observability exporters to an axum `Router`.
- **Component lifecycle hooks**: Emitting custom observability events when components mount, ready, or unmount.
- **Middleware & observability**: Decorating requests and responses without writing custom axum layers directly.

## Key API / Syntax

### App Plugins (RFC-076)

**Core trait:**
```rust
pub trait AppPlugin {
    fn name(&self) -> &'static str { std::any::type_name::<Self>() }
    fn install(self, app: App) -> App;
}
```

**Installing plugins:**
- `App::plugin(plugin)` — builder method; plugin closures also implement `AppPlugin`.
- `App::provide_plugin(service)` — inside `install`, register a runtime service.
- `App::hook_plugin::<Service, Event>()` — register a `Hook<Event>` impl on the service.
- `App::hook_component_plugin::<Service, Component, Event>()` — fire hook only for a specific component type.

**Extracting services in components:**
- `Plugin<T>` — required; panics if `T` not installed.
- `Option<Plugin<T>>` — optional; returns `None` if missing.
- `self.plugin::<T>()` — extract from a method; required form.
- `self.plugins().get::<T>()` — extract from a method; optional form.

**Lifecycle events:**
- `AppBootStarted`, `AppBootCompleted`, `AppBootFailed`
- `ComponentSetup`, `ComponentMounted`, `ComponentReady`, `ComponentUnmounted`
- `RouteNavigationStarted`, `RouteNavigationCompleted`, `RouteNavigationFailed`
- `ServerFunctionClientStarted`, `ServerFunctionClientCompleted`, `ServerFunctionClientFailed`

**Macro support:**
```rust
pocopine::app! {
    plugins: [plugin1(), plugin2()],
    components: [...],
    routes: [...],
}
```

### Server Plugins (RFC-077)

**Core trait:**
```rust
pub trait ServerPlugin {
    fn name(&self) -> &'static str { std::any::type_name::<Self>() }
    fn install(self, server: Server) -> Server;
}
```

**Installing plugins:**
- `Server::new(router).plugin(plugin)` — builder method; closures also implement `ServerPlugin`.
- `Server::provide_plugin(service)` — register an `Arc<T>` runtime service.
- `Server::hook_plugin::<Service, Event>()` — register a `ServerHook<Event>` impl.

**Lifecycle events:**
- `ServerBootStarted`, `ServerListening`, `ServerBootFailed`
- `HttpRequestStarted`, `HttpRequestCompleted`, `HttpRequestFailed`
- `ServerFunctionStarted`, `ServerFunctionCompleted`, `ServerFunctionRejected`, `ServerFunctionFailed`

**Hook trait:**
```rust
pub trait ServerHook<E>: Send + Sync + 'static {
    fn call(&self, event: E);
}
```

## Examples

### Example 1: App Plugin with Lifecycle Hooks

From `/home/zempare-mambisi/RustProjects/pocopine/crates/pocopine-sync-query/src/plugin.rs`:

```rust
pub fn query_client_plugin() -> QueryClientPlugin {
    QueryClientPlugin::default()
}

impl AppPlugin for QueryClientPlugin {
    fn name(&self) -> &'static str {
        "pocopine-sync-query"
    }

    fn install(self, app: App) -> App {
        app.provide_plugin::<Rc<QueryClient>>(
            Rc::new(self.into_client())
        )
    }
}
```

Usage in a component:
```rust
fn on_ready(&self, query: Plugin<Rc<QueryClient>>) {
    query.observe(MyQuery);
}
```

### Example 2: Auth Client Plugin with Builder

From `/home/zempare-mambisi/RustProjects/pocopine/crates/pocopine-auth-client/src/plugin.rs`:

```rust
impl AppPlugin for AuthPluginBuilder {
    fn name(&self) -> &'static str {
        "pocopine-auth-client"
    }

    fn install(self, app: App) -> App {
        if let Some(storage) = self.token_storage {
            install_storage(storage);
            crate::hydrate_from_storage();
        }
        
        let session = AuthSession::new();
        app.provide_plugin(session)
            .route_rejection_handler(UnauthorizedRedirect {
                login_route: self.login_route,
                param: self.return_to_query_param,
            })
    }
}

// Usage:
auth_plugin()
    .login_route("/login")
    .with_bearer_middleware(true)
    .with_token_storage(LocalStorage::new("token"))
```

### Example 3: Server Plugin with Event Hooks

From `/home/zempare-mambisi/RustProjects/pocopine/crates/pocopine-server/tests/server_plugin.rs`:

```rust
impl ServerHook<ServerBootStarted> for EventLog {
    fn call(&self, event: ServerBootStarted) {
        self.record(format!("boot:{}", event.addr));
    }
}

impl ServerPlugin for EventLog {
    fn name(&self) -> &'static str {
        "event-logger"
    }

    fn install(self, server: Server) -> Server {
        server
            .provide_plugin(self.clone())
            .hook_plugin::<EventLog, ServerBootStarted>()
    }
}

// In main:
Server::new(router)
    .plugin(EventLog::default())
    .serve("0.0.0.0:3000")
    .await
```

## Gotchas

1. **Hook/Service Ordering**: If a hook is registered before its service is provided, boot validation will catch it and render a detailed error. Install services *before* or *after* hooks—validator doesn't care about order, only completeness.

2. **Duplicate Services**: Calling `provide_plugin` twice with the same type panics immediately, naming both providers. This is intentional—fail loud, not silently overwrite.

3. **Plugin Lifecycle is Sync**: `install` runs synchronously during builder assembly. Async setup should spawn tasks from `install` or attach a `before_mount` / `after_mount` hook.

4. **No Dynamic Uninstall**: Installed services and hooks live for the app's lifetime. There is no removal or hot-swap API; dynamically-loaded plugins are out of scope.

5. **Server Registry is Process-Global**: A second `Server::serve` call in the same process replaces the first's plugin registry. Tests should call `pocopine_server::__reset_for_test()` between serves.

6. **Macro Apps Can Inspect Manifest**: When using `pocopine::app! { plugins: [...] }`, plugins see static component and route metadata before mount, but *cannot* register additional components or routes. The static registry contract (RFC-060) is preserved.

7. **Layer Order in Server Plugins**: `Server::layer()` wraps only routes that exist at the call site. Add routes first, then layers, to avoid silently bypassing middleware.

8. **App-Level Performance**: Component mount/unmount hot paths use a bitmask cache to skip plugin-only metadata stamps when no hooks are registered. This is automatic; plugins stay cheap when unused.

## References

- **App plugin lifecycle**: `crates/pocopine-core/src/plugin.rs` — the trait, registry, and event dispatch.
- **Server plugin lifecycle**: `crates/pocopine-server/src/plugin.rs` — the trait, registry, and hook bitmask gating.
- **Auth plugin example**: `crates/pocopine-auth-client/src/plugin.rs` — builder pattern, lifecycle hooks, optional storage.
- **Query plugin example**: `crates/pocopine-sync-query/src/plugin.rs` — minimal `Rc<T>` service provision.
- **Server plugin tests**: `crates/pocopine-server/tests/server_plugin.rs` — boot event ordering, validation errors.
- **RFC-076**: `rfcs/rfc-076-app-plugin-lifecycle.md` — design, lifecycle order, observability shape.
- **RFC-077**: `rfcs/rfc-077-server-plugin-lifecycle.md` — host-side plugin shape, HTTP events, validation.
- **App plugins guide**: `docs/app-plugins.md` — full lifecycle order, four integration paths, testing contract.
- **Server plugins guide**: `docs/server-plugins.md` — quickstart, layer ordering, cost model, `active_plugin` lookups.
