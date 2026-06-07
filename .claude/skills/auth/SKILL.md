---
name: auth
description: >-
  Use when implementing authentication in pocopine apps — JWT verification, credentials, OAuth providers, session management, or guards
---

# Pocopine Authentication

This teaches the pocopine authentication domain model, JWT verification, credentials (passwords/OTP), the Provider trait, and client-side session management. The framework is provider-neutral and opinionated about security defaults (algorithm pinning, constant-time auth, Argon2id).

## Key API / Syntax

**Domain model (pocopine-auth)**
- `Principal` — request identity; `.user()` returns `Option<Arc<AuthUser>>`, `.has_role(r)` / `.has_permission(p)` for checks
- `AuthUser` — canonical user shape with `id`, `email`, `email_verified`, `name`, `roles: Vec<Role>`, `permissions: Vec<Permission>`, and `claims: HashMap<String, serde_json::Value>` for provider-specific fields
- `Role(Cow<'static, str>)` — stringly typed; `.admin()`, `.staff()`, `.user()`, `.named(s)` factory methods
- `Permission(Cow<'static, str>)` — identical shape to `Role`

**JWT verification (pocopine-auth-jwt)**
- `JwtVerifier::custom(JwtConfig)` / `JwtVerifier::from_provider(P: Provider)` — construct the verifier
- `JwtConfig` — declarative verification shape: `keys: KeySource`, `issuer: Option<String>`, `audience: Option<Vec<String>>`, `algorithms: Vec<Algorithm>` (pinned per config), `sources: Vec<TokenSource>` (Bearer, Cookie), `claim_map: ClaimMap`, `leeway: Duration`
- `KeySource::Jwks { url, cache_ttl, refresh_cooldown }` (OIDC, Firebase, Clerk, Auth0) / `KeySource::Hmac { secret }` (Supabase, pocopine-issued) / `KeySource::StaticJwks(JwkSet)` (tests)
- `Algorithm::Rs256 | Hs256 | Es256 | ...` — always pinned at config construction; never accepts `alg: none`
- `TokenSource::Bearer` / `TokenSource::Cookie(name)` — where to find tokens
- `ClaimMap { id, email, email_verified, name, roles, permissions }` — paths to extract claims; defaults to OIDC shape
- `Provider` trait — app-local or third-party configs (Firebase, Okta, Cognito) implement this; `fn jwt_config(self) -> Result<JwtConfig, JwtAuthError>`
- `JwtIssuer::hs256(secret, issuer, audience)` / `JwtIssuer::rs256(private_key, key_id, issuer, audience)` — mint session tokens

**Credentials (pocopine-auth-credentials)**
- `PasswordCredentials` trait — app implements on own user type; methods: `fn id(&self) -> &str`, `fn email(&self) -> &str`, `fn password_hash(&self) -> Option<&str>`, `fn to_auth_user(&self) -> AuthUser`
- `UserStore` trait — `async fn find_by_email(&self, email: &str) -> Result<Option<User>, Error>`, `find_by_id`, `create(email, password_hash)`
- `TokenStore` trait — for ephemeral reset/verify tokens; `async fn put(token_hash, record)`, `take(token_hash)` (single-use), `purge_expired(now_ms)`
- `Credentials::new(secret, store, tokens)` — builder; `.with_session_ttl(Duration)`, `.with_argon_params(Argon2Params)`, `.with_issuer(name)`, `.with_audience(name)`, `.with_password_validator(closure)`
- `Argon2Params` — OWASP defaults: m=64MiB, t=3, p=4; `.owasp_minimum()` rejects weaker configs
- Routes mounted by `install_routes(router)`: `POST /_pocopine/auth/signup { email, password }`, `/login`, `/logout`; returns `{ token: String, user: AuthUser }`

**Client session (pocopine-auth-client, wasm-side)**
- `auth_plugin()` — builder; `.login_route(path)`, `.with_bearer_middleware(bool)`, `.with_token_storage(impl TokenStorage)`, `.with_cross_tab_sync(bool)`, `.with_token_refresh(impl TokenRefresh)`, `.wait_for_initial_auth_check(bool)`
- `AuthSession` — plugin service; `.sign_in(token, principal)`, `.sign_out()`, `.principal()`, `.epoch()` (bumped on identity change)
- `BearerMiddleware` — installs on fetch chain; adds `Authorization: Bearer <token>` header; drops response if identity changed mid-flight
- `TokenStorage` trait — `fn load() -> Option<String>`, `save(token: &str)`, `clear()`; provided: `LocalStorage::new(key)`, `SessionStorage::new(key)`, `InMemory` (default)
- `TokenRefresh` trait — `fn refresh(&self) -> TokenRefreshFuture` (dyn Future<Output=Result<String, ServerError>>); coalesces concurrent 401s into single refresh call
- `predicate_guard(Predicate)` — adapts `require_auth()`, `require_role(r)`, `require_permission(p)`, `all_of(...)`, `any_of(...)` into route guards

**Guards & predicates (pocopine-auth, both sides)**
- `#[pocopine::server(guard = require_login)]` — enforces authentication on the server; fails with `ServerError::Unauthorized` if anonymous
- `#[pocopine::server(guard = require_role("admin"))]` — enforces specific role
- `#[pocopine::server(public)]` — no guard; anonymous ok
- `#[server(idempotent)]` — marks read-only functions safe to replay on token refresh

## Examples

**1. First-party email + password (server side)**
```rust
// From crates/pocopine-auth-credentials examples
use pocopine_auth_credentials::Credentials;
use pocopine_auth_jwt::{JwtVerifier, SecretBytes};
use pocopine_server::{axum::Router, RouterAuthExt, Server};

#[tokio::main]
async fn main() -> std::io::Result<()> {
    let secret = SecretBytes::new(
        std::env::var("POCOPINE_AUTH_SECRET")
            .expect("set POCOPINE_AUTH_SECRET to >= 32 random bytes"),
    );
    let pool = sqlx::PgPool::connect(&std::env::var("DATABASE_URL").unwrap()).await?;

    let creds = Credentials::new(
        secret,
        my_app::PgUserStore { pool: pool.clone() },
        my_app::PgTokenStore { pool },
    );

    let verifier = JwtVerifier::custom(creds.verifier_config())?;

    Server::new(Router::new())
        .with_auth(verifier)
        .plugin(creds)
        .serve("0.0.0.0:3000")
        .await
}
```

**2. Firebase auth provider (app code)**
```rust
// From docs/auth-jwt-providers.md
use pocopine_auth_jwt::{JwtVerifier, Provider};
use std::time::Duration;

#[non_exhaustive]
pub struct Firebase {
    pub project_id: String,
    pub session_cookie: bool,
    pub cache_ttl: Duration,
    pub refresh_cooldown: Duration,
    pub leeway: Duration,
}

impl Firebase {
    pub fn new(project_id: impl Into<String>) -> Self {
        Self {
            project_id: project_id.into(),
            session_cookie: false,
            cache_ttl: Duration::from_secs(3600),
            refresh_cooldown: Duration::from_secs(30),
            leeway: Duration::from_secs(60),
        }
    }
}

impl Provider for Firebase {
    fn jwt_config(self) -> Result<JwtConfig, JwtAuthError> {
        let mut sources = vec![TokenSource::Bearer];
        if self.session_cookie {
            sources.push(TokenSource::Cookie(Cow::Borrowed("__session")));
        }
        Ok(JwtConfig {
            keys: KeySource::Jwks {
                url: "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com".into(),
                cache_ttl: self.cache_ttl,
                refresh_cooldown: self.refresh_cooldown,
            },
            issuer: Some(format!("https://securetoken.google.com/{}", self.project_id)),
            audience: Some(vec![self.project_id]),
            algorithms: vec![Algorithm::Rs256],
            leeway: self.leeway,
            sources,
            revocation: None,
            claim_map: ClaimMap::oidc(),
            required_scopes: vec![],
        })
    }
}

let verifier = JwtVerifier::from_provider(Firebase::new("my-project-id"))?;
```

**3. Client-side session + guards**
```rust
// From docs/auth-client.md
use pocopine_auth_client::{auth_plugin, predicate_guard, AuthSession};
use pocopine_auth::require_auth;
use pocopine_core::{Plugin, RouteComponent, RouteConfig};

#[derive(Default)]
pub struct Dashboard {
    user_email: String,
}

impl RouteComponent for Dashboard {
    fn config() -> RouteConfig<Self> {
        RouteConfig::new()
            .guard(predicate_guard(require_auth()))
    }
}

impl Dashboard {
    pub fn on_setup(&mut self, session: Plugin<AuthSession>) {
        if let Some(user) = session.principal().user() {
            self.user_email = user.email.clone().unwrap_or_default();
        }
    }
}

pocopine::app! {
    components: [Dashboard],
    plugins: [
        auth_plugin()
            .login_route("/login")
            .with_bearer_middleware(true)
            .with_token_storage(pocopine_auth_client::storage::LocalStorage::new("auth_token"))
            .with_cross_tab_sync(true),
    ],
    routes: [("/dashboard", Dashboard)],
}
```

**4. Guarded server function**
```rust
// From crates/pocopine/tests/auth_middleware.rs
use pocopine_auth::require_login;

#[pocopine::server(guard = require_login, idempotent)]
async fn get_dashboard_data() -> pocopine::ServerResult<DashboardData> {
    let principal = pocopine::server::principal()?;
    let user = principal.require_user()?;
    // Use user.id, user.email, user.roles, etc.
    Ok(DashboardData { /* ... */ })
}
```

## Gotchas

**JWT confusion attacks.** `JwtConfig::validate()` runs at construction and rejects algorithm-pinning mismatches (HS256 + JWKS, RS256 + HMAC) with a panic. This is intentional and enforces security invariants at deployment time, not request time. Preset constructors are guaranteed correct; custom configs must get this right.

**`alg: none` impossible by construction.** The `Algorithm` enum has no `None` variant; the whitelist cannot include it.

**Bearer vs. Cookie precedence.** If both are configured and a request supplies both, Bearer wins (OIDC convention). The cookie is ignored.

**JWKS cache on `kid` miss.** If a token's `kid` (key ID) isn't in the cache, the verifier fetches fresh JWKS. To defend against adversarial clients sending random `kid` values, a per-config `refresh_cooldown` (default 30s) rate-limits fetches. Legitimate key rotation is usually hours apart.

**`Role` no longer an enum.** Old code using `Role::Admin` breaks; migrate to `Role::admin()` factory or `.named("admin")` for custom roles. This closes the magic-string deserialization footgun (a JWT claim `"admin"` won't auto-promote to a privileged variant).

**Principal is cheap to clone.** User is `Option<Arc<AuthUser>>`, so cloning the principal is O(1). Middleware and guards can pass it around freely.

**`Principal::user()` is `Option<Arc<AuthUser>>`.** Access the user with `.user()`, not direct field access; the field is private.

**Credentials doesn't define a User type.** The framework doesn't own user identity — apps do. Implement `PasswordCredentials` on your own struct (Postgres row, custom struct, anything). This lets apps that need multi-credential flows (password + OAuth + passkey) use a single user table.

**`PasswordCredentials::password_hash()` returns `Option<&str>`.** This is intentional — OAuth-only users have `None`, and the login handler treats that the same as "user not found," defending against "is this email a Google account?" enumeration.

**Email lowercased before store lookup.** The credentials router lowercases email before calling `UserStore::find_by_email`, so a plain `UNIQUE` constraint in Postgres suffices (no `LOWER()`-indexed expression needed).

**Token storage is required for cross-tab sync.** `with_cross_tab_sync(true)` without `with_token_storage(...)` broadcasts sign-in/out to peer tabs but they have no way to read the new token. The broadcast tells peers "something changed" but carries no token over the channel.

**Route guards are UX, not authorization.** Client-side guards prevent paint of forbidden pages. The security boundary is the server. Every guarded `#[server]` function must carry its own `#[server(guard = ...)]` policy; a determined attacker can edit their JWT in localStorage or call the function directly with curl.

**Refresh only works on `#[server(idempotent)]`.** Non-idempotent calls (those that create/delete/modify) are not retried on 401, even if refresh succeeds. Mark all GET-shaped and read-only POST calls with `idempotent` so the bearer middleware can refresh + replay them transparently.

**Secret rotation requires coordination.** `POCOPINE_AUTH_SECRET` rotation blocks until all verifiers are updated and in-flight tokens are expired.

## References

**RFCs**
- RFC-070 — JWT-based authentication verification (`crates/pocopine-auth-jwt`; one engine, declarative config per provider, algorithm pinning, JWKS caching, verifier middleware flow)
- RFC-074 — `pocopine-auth-credentials` and the `Provider` trait (first-party email + password, argon2id, constant-time login, extensible provider shape for third-party IdPs)

**Crates**
- `pocopine-auth` — `Principal`, `AuthUser`, `Role`, `Permission`, `Predicate` (guard combinators), `AuthProvider` / `SessionStore` traits
- `pocopine-auth-jwt` — `JwtVerifier`, `JwtConfig`, `KeySource`, `TokenSource`, `ClaimMap`, `Provider` trait, `JwtIssuer`, `Algorithm` pinning, `SecretBytes`
- `pocopine-auth-credentials` — `Credentials` builder, `PasswordCredentials` trait, `UserStore` / `TokenStore` traits, `Argon2Params` (OWASP defaults)
- `pocopine-auth-client` — `auth_plugin()`, `AuthSession`, `BearerMiddleware`, `TokenStorage` trait, `TokenRefresh` trait, `predicate_guard()`

**Docs**
- `docs/auth-jwt-providers.md` — Provider contract, integration test pattern, community provider crates list
- `docs/auth-credentials.md` — Postgres + sqlx end-to-end walkthrough for signup/login/logout with `PasswordCredentials`, `UserStore`, `TokenStore`
- `docs/auth-client.md` — Wasm-side full walkthrough: bearer middleware, `AuthSession`, token storage, cross-tab sync, refresh, guards
- `docs/auth-phone-otp-tutorial.md` — Build-it-yourself OTP pattern using the same primitives (Twilio + `JwtIssuer`, single-use hashed tokens, rate limiting); production-ready until `pocopine-auth-otp` ships
