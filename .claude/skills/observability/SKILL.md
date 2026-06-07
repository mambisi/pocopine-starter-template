---
name: observability
description: >-
  Use when setting up tracing, logging, analytics, or observability events in a pocopine application—both frontend and backend.
---

## What this is

Pocopine's observability system unifies browser logging, backend logging, structured tracing, and analytics under a shared event contract using the `tracing` crate. It spans three crates: `pocopine-observe` (event schema and privacy labels), `pocopine-logging` (log formatting and export), and `pocopine-analytics` (analytics fan-out with redaction).

## When to use

- Emit debug logs in browser console or server stderr/stdout
- Create trace spans for timing and causality
- Emit stable, schema-versioned analytics events
- Configure server-side observability for HTTP requests, server functions, or app boot events
- Install privacy redaction for analytics sinks
- Export traces to OpenTelemetry or JSON-lines analytics files

## Key API / syntax

**Event classes and targets:**
- `ObservedEvent::log(name)` → `pocopine.log` target, operational records
- `ObservedEvent::trace(name)` → `pocopine.trace` target, timing and causality
- `ObservedEvent::metric(name)` → `pocopine.metric` target, measured values
- `ObservedEvent::analytics(name)` → `pocopine.analytics` target, product events

**Field privacy labels:**
- `FieldPrivacy::Public` — exported everywhere by default
- `FieldPrivacy::Pseudonymous` — requires explicit policy; dropped unless opt-in
- `FieldPrivacy::Sensitive` — dropped unless trusted sink explicitly allows

**Event context (optional):**
- `service`, `environment`, `route`, `component`, `trace_id`, `session_id`, `user_id_hash`

**Browser logging setup:**
- `init_console_logging(ConsoleLoggingConfig::debug())` — compact text logs, filters to `pocopine.*` targets
- `init_console_logging(ConsoleLoggingConfig::json())` — structured console objects with level, target, message, fields
- `frontend_observability()` — plugin for app! macro; subscribes to framework lifecycle hooks
- `Plugin<FrontendObservability>.emit(event)` — emit custom analytics from components

**Server logging setup:**
- `init_server_logging(ServerLoggingConfig::json())` — structured JSON logs to stdout
- `init_server_logging(ServerLoggingConfig::compact())` — human-readable development logs
- `with_env_filter("info,pocopine=debug")` — override RUST_LOG
- `with_otlp(OtlpConfig::grpc("http://localhost:4317"))` — export traces to OpenTelemetry

**Server-side observability plugin:**
- `server_observability()` — hooks for boot, HTTP requests, server functions
- `ServerObservabilityConfig::new().with_service("api").with_environment("prod")`
- `.with_http_requests(true)`, `.with_server_functions(true)`, `.with_boot(true)` to selectively enable
- `.with_unmatched_paths(true)` to include raw paths for 404s (default omits for privacy)

**Analytics client and sinks:**
- `AnalyticsClient::new().with_sink(sink)` — attach one or more redacting sinks
- `analytics.emit(event)` → `AnalyticsReport` with `all_succeeded()`, `failed` count
- `analytics.flush()` — drain buffered events before graceful shutdown
- `JsonLinesAnalyticsSink::stdout()` — write `\n`-delimited JSON to stdout/stderr/file
- `BoundedAnalyticsSink::new(sink, capacity)` — wrap with backpressure, drop counter, metrics
- `sink.metrics()` → `{pending, enqueued, dropped, delivered, failed}`

**Context and tracing targets:**
Always use explicit `target`:
```rust
tracing::info!(target: "pocopine.log", "message");
```
Without target, logs filter to module path and may not reach console.

## Examples

**Browser console logging with plugin:**
```rust
// examples/observability-frontend/src/lib.rs
#[wasm_bindgen(start)]
pub fn main() {
    let observability = pocopine::logging::frontend_observability_with_config(
        FrontendObservabilityConfig::default()
            .with_service("observability-frontend")
            .with_environment("dev"),
    );
    pocopine::app! {
        components: [AppShell, HomePage],
        plugins: [observability],
        routes: [("/", HomePage)],
    };
}
```

**Emit analytics from a component:**
```rust
// examples/observability-frontend/src/lib.rs (simplified)
#[handlers]
impl HomePage {
    pub fn track_feature(&mut self) {
        self.plugin::<FrontendObservability>().emit(
            ObservedEvent::analytics("feature_used")
                .field("feature", "button_click", FieldPrivacy::Public)
                .field("count", self.tracked, FieldPrivacy::Public),
        );
    }
}
```

**Server logging and observability:**
```rust
// examples/observability-smoke/src/bin/server.rs
#[tokio::main]
async fn main() -> std::io::Result<()> {
    init_server_logging(
        ServerLoggingConfig::json()
            .with_env_filter("info,pocopine=debug")
            .with_otlp(OtlpConfig::from_env()),
    )?;
    
    let router = Router::new();
    Server::new(router)
        .plugin(server_observability_with_config(
            ServerObservabilityConfig::new()
                .with_service("blog-api")
                .with_environment("production"),
        ))
        .serve("0.0.0.0:3000")
        .await
}
```

**Analytics with redaction and JSON export:**
```rust
// examples/observability-smoke/src/bin/analytics_exporter.rs
let exporter = BoundedAnalyticsSink::new(JsonLinesAnalyticsSink::stdout(), 16);
let analytics = AnalyticsClient::new().with_sink(exporter);

analytics.emit(
    pocopine::analytics::route_view("/report/:id")
        .field("surface", "app", FieldPrivacy::Public)
        .field("user_hash", hash, FieldPrivacy::Pseudonymous),
);
analytics.flush()?;
```

## Gotchas

**Target filtering:** Browser console only shows logs with target starting with `pocopine` by default. Always emit with `target: "pocopine.log"`, `"pocopine.trace"`, etc., or configure `without_target_prefix()` to see all logs.

**Field count limit:** Events reserve eight field slots. If you exceed that, `observed_field_overflowed = true` is set, but the event still records the full count in `observed_field_count`. Keep framework events coarse; do not ship wide payloads of internal state.

**Privacy redaction happens at dispatch time, not emission:** `ObservedEvent::analytics(...)` defaults to `FieldPrivacy::Pseudonymous`. Call `.field(..., FieldPrivacy::Public)` explicitly for fields that are safe to export. `AnalyticsClient` redacts before invoking sinks, so sinks always receive a safe subset.

**Exporter failure does not fail the app:** Sink panics are caught and reported as delivery failures. If a sink returns an error, `AnalyticsClient` continues with other sinks. Use `BoundedAnalyticsSink` for backpressure; it rejects new events when full and exposes drop counters.

**Libraries do not install subscribers:** Framework crates emit `tracing` events or `ObservedEvent`s. The final application binary (in `main()` or `#[wasm_bindgen(start)]`) installs logging and analytics.

**Context is optional:** `ObservedEvent` context fields (`service`, `route`, `component`, etc.) are all `Option<String>`. The plugin and app are responsible for populating them. Missing fields export as `observed_context_has_service = false` so exporters can distinguish absence from empty strings.

## References

- **RFC:** [rfc-069-observability.md](../rfcs/rfc-069-observability.md) — design, crate boundaries, privacy rules, reliability rules
- **Documentation:** [docs/logging-tracing-observer.md](../docs/logging-tracing-observer.md) — mental model, feature setup, recipes, OTLP export
- **Crates:** `/crates/pocopine-observe`, `/crates/pocopine-logging`, `/crates/pocopine-analytics`
- **Examples:** `/examples/observability-smoke` (server logging + OTLP), `/examples/observability-frontend` (browser + analytics)
