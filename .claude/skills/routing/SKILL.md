---
name: routing
description: >-
  Use when building SPA routes, implementing route guards/loaders, configuring pp-route links, or handling route navigation in pocopine.
---

# SPA Routing in Pocopine

Pocopine's SPA router maps URL patterns to `#[component]` types, paints matched components into a `<pp-outlet>`, and provides URL-aware navigation via `pp-route` link interception, guards, loaders, and programmatic APIs. Routes are declared centrally in `App::new()` and behavior is attached to components via `RouteComponent` trait implementation.

## When to Use

- Declare app routes and map URL patterns to components
- Add route-level guards (sync predicates that gate route paint)
- Add route loaders (async data-fetch before component mount)
- Create client-side navigating links with `pp-route`
- Read route params, query, and path in templates or Rust code
- Handle route rejections and errors
- Implement nested layouts with multiple `<pp-outlet>`s

## Key API / Syntax

**Route Declaration & Pattern Matching:**
- `App::new().route::<Component>("/pattern")` — register a route; patterns are literal (`/about`), parameterized (`:name`), or wildcard (`*`)
- Path params like `/:id` become component `#[prop]` fields via kebab→snake coercion (`:post_id` → `post_id: T`)
- `*` wildcard matches any path not matched by earlier routes (404 fallback)

**Route Component Interface:**
```rust
pub trait RouteComponent: Component {
    fn config() -> RouteConfig<Self> {
        RouteConfig::new()
    }
}

pub struct RouteConfig<C: Component> { … }
impl<C: Component> RouteConfig<C> {
    pub fn guard(self, guard: impl RouteGuard) -> Self;
    pub fn loader<F, T>(self, loader: F) -> Self
    where F: Fn(LoaderContext) -> BoxFuture<Result<T, LoaderError>> + Send + Sync + 'static;
    pub fn meta<T: 'static>(self, key: RouteMetaKey<T>, value: T) -> Self;
    pub fn page_meta<F>(self, factory: F) -> Self where F: Fn(&RouteLocation) -> PageMeta + 'static;
}
```

**Route Guards (Sync):**
```rust
pub trait RouteGuard: 'static {
    fn decide(&self, ctx: &RouteContext) -> RouteGuardDecision;
}

pub enum RouteGuardDecision {
    Allow,
    Redirect(RouteTarget),
    Reject(RouteRejection),
}

pub enum RouteRejection {
    Unauthorized,
    Forbidden(&'static str),
    Blocked(&'static str),
    NotFound,
    Server(&'static str),
    Custom { reason: &'static str },
}
```

**Route Loaders (Async):**
```rust
pub enum LoaderError {
    Unauthorized,
    Forbidden(String),
    NotFound(String),
    Server(ServerError),
}

pub struct Loader<T: 'static> { … }
// Extract loader data in on_setup: `data: Loader<MyData>`
```

**Navigation & Links:**
- `<a href="/path" pp-route>` — intercept clicks, navigate client-side (no page reload)
- `<a href="/path" pp-route:replace>` — use `replace` instead of `push`
- `pocopine::navigate(url: &str)` — programmatic push-style navigation
- `pocopine::push(target: impl IntoRouteTarget) -> NavigationResult`
- `pocopine::replace(target: impl IntoRouteTarget) -> NavigationResult`
- `RouteTarget::path("/path")`, `RouteTarget::path_with_query("/path", query)` — typed navigation targets

**Template Binding:**
- `$route.path` — current route path (reactive)
- `$route.params.<name>` — path parameter value (reactive)
- `$route.query.<name>` — query string value (reactive)

**Outlets & Nested Layouts:**
- `<pp-outlet></pp-outlet>` — single sentinel tag where the router mounts the matched route component
- Reserved tag; apps cannot define a component named `pp-outlet`
- One outlet per app in flat routes; nested outlets (nested layouts) handled by parent route scopes

**Rejection Handling & Fallback Components:**
- `App::route_rejection_handler(handler: impl RouteRejectionHandler)` — install a handler for route rejections (e.g., unauthorized → redirect to login)
- `App::route_error_component::<C>()` — custom component for unhandled rejections (fallback: generic HTML banner)
- `App::not_found_component::<C>()` — custom 404 component when no route matches and no `*` fallback exists

## Examples

**1. Basic Flat SPA Routes:**
```rust
// examples/spa/src/lib.rs
use pocopine::prelude::*;

#[component]
pub struct AppShell {}

#[handlers]
impl AppShell {}

#[component]
pub struct BlogPost {
    #[prop]
    pub id: u32,
    pub body: String,
}

#[handlers]
impl BlogPost {
    pub fn on_mount(&mut self) {
        self.body = format!("This is post #{}.", self.id);
    }
}

impl RouteComponent for BlogPost {}

#[wasm_bindgen(start)]
pub fn main() {
    App::new()
        .register::<AppShell>()
        .route::<Home>("/")
        .route::<About>("/about")
        .route::<BlogPost>("/blog/:id")
        .route::<NotFound>("*")
        .run();
}
```

**2. pp-route Links & $route Magic:**
```html
<!-- examples/spa/src/AppShell.poco -->
<div class="shell">
  <nav class="nav">
    <a href="/" pp-route>home</a>
    <a href="/blog/42" pp-route>post 42</a>
    <a href="/about" pp-route:replace>about</a>
  </nav>
  <main>
    <pp-outlet></pp-outlet>
  </main>
  <footer>
    <small>Current path: <code pp-text="$route.path"></code></small>
  </footer>
</div>
```

**3. Route Guards & Loaders:**
```rust
// docs/route-guards-and-loaders.md pattern
use pocopine::prelude::*;

#[component(template = "Dashboard.poco")]
pub struct Dashboard {
    pub user: AuthUser,
    pub stats: DashboardStats,
}

#[handlers]
impl Dashboard {
    pub fn on_setup(&mut self, data: Loader<DashboardData>) {
        self.user = data.user.clone();
        self.stats = data.stats.clone();
    }
}

impl RouteComponent for Dashboard {
    fn config() -> RouteConfig<Self> {
        RouteConfig::new()
            .guard(|ctx: &RouteContext| {
                if AuthSession::current().is_authenticated() {
                    RouteGuardDecision::Allow
                } else {
                    RouteGuardDecision::Reject(RouteRejection::Unauthorized)
                }
            })
            .loader(|_ctx| async move {
                let (user, stats) = futures::try_join!(
                    api::current_user(),
                    api::dashboard_stats(),
                )?;
                Ok(DashboardData { user, stats })
            })
    }
}

// In App::new():
App::new()
    .route_rejection_handler(|ctx, rejection| match rejection {
        RouteRejection::Unauthorized => {
            let target = ReturnTo::current()
                .append_to(RouteTarget::path("/login"), "next");
            Some(RouteRejectionAction::Redirect(target))
        }
        _ => None,
    })
    .route::<Dashboard>("/dashboard")
    .route::<Login>("/login")
    .run();
```

## Gotchas

**Client Guards Are UX Only, Not Security Boundaries:**
- Guards prevent paint and flicker but do not protect data
- Every sensitive `#[server]` function **must** carry its own `#[server(guard = …)]` on the server side
- Same `Predicate` value can be used on both client (guard) and server sides via adapters

**Route Params Are Strings & Coerced via Attributes:**
- Path params like `/:id` are captured as strings in `$route.params.id`
- Components receive them as `#[prop]` fields after type coercion (kebab-case → snake_case)
- Invalid types panic; ensure the component's field type matches what the route can provide

**One Loader Per Route:**
- `RouteConfig::loader(...)` may be called at most once per route config
- Multiple parallel async fetches compose inside one loader via `futures::try_join!`
- Loader data has per-mount lifetime—cleared when the component unmounts; no implicit cache

**pp-route Link Interception Conditions:**
- Only intercepts clicks when: no modifier keys, primary button, not `target="_blank"`, same-origin, app-local URL
- URLs under `/_pocopine/*` are never intercepted (reserved server-function namespace)
- Falls through to browser behavior otherwise (external links, new tab, etc.)

**`$route` Is Read-Only in Templates:**
- Writing `$route.path = "/foo"` has no effect
- Use `pocopine::navigate()` or `push()/replace()` from Rust instead

**Reserved Outlet Tag:**
- Components cannot be named `pp-outlet` (reserved sentinel)
- Only one `<pp-outlet>` per route component in flat routing
- Nested outlets (nested layouts) not yet implemented in flat v1; RFC-089 Phase 2 planned

**Wildcard Matching Fallback:**
- `*` pattern must be registered last (matched after all other routes)
- If no route matches and no `*` fallback, the `not_found_component` (if configured) mounts instead

**`ReturnTo` Path-Only Validation:**
- Used for post-redirect-to-original-location; RFC-078 §5.10.2 enforces strict validation
- Rejects protocol-relative URLs (`//evil.com`), backslash tricks, control characters, double-encoding attacks
- Invalid values silently become `ReturnTo::none()`—a redirect without a return param, not an open-redirect

## References

**RFCs:**
- RFC-003 (Client-side SPA router): `/rfcs/rfc-003-router.md` — core router design, outlets, path params, `$route` magic
- RFC-078 (Route guards, loaders, fetch middleware): `/rfcs/rfc-078-client-route-guards-and-loaders.md` — guard/loader traits, rejection chains, fetch middleware, security model
- RFC-089 (SPA router parity & nested outlets): `/rfcs/rfc-089-spa-router-parity.md` — typed navigation targets, programmatic push/replace, nested layouts, meta, redirects, aliases

**Documentation:**
- `/docs/route-guards-and-loaders.md` — end-to-end guide with guard/loader patterns, rejection chains, `ReturnTo`, auth plugin integration

**Crate:**
- `pocopine-core` router module: `/crates/pocopine-core/src/router.rs` — route matching, navigation, outlet management, guard/loader dispatch
- `app.rs`: `RouteComponent`, `RouteConfig`, `RouteGuard`, `RouteLoader`, `RouteRejectionHandler` trait definitions

**Examples:**
- `/examples/spa/src/` — minimal flat SPA with four routes, param passing, `$route.path` binding
- `/examples/hn/src/` — larger example with param-driven data loading and nested component state
