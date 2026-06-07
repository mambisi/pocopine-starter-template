---
name: background-jobs
description: >-
  Use when defining background jobs, enqueueing work, configuring workers, or troubleshooting job execution in pocopine apps
---

# Background Jobs in pocopine

The `#[pocopine::job]` macro defines server-side background jobs with automatic enqueue/schedule helpers, retry logic, and support for periodic jobs. Handlers compile to the host only; WASM gets stubs. Two backends available: Redis (durable, multi-process) or memory (process-local, for tests/embedded workers).

## When to use

- Define a job: `#[pocopine::job(queue = "...", retries = N)]` for one-time work or `#[pocopine::job(every = "...")]` / `#[pocopine::job(cron = "...")]` for periodic tasks.
- Enqueue from a server function: call `my_job_job::enqueue(payload).await` or one of the schedule helpers.
- Run workers: create a `bin/worker.rs`, set `[package.metadata.pocopine]` entries, and call `Worker::from_env()?.run().await`.
- Configure backends: set `POCOPINE_JOB_BACKEND` and `POCOPINE_REDIS_URL` environment variables.

## Key API / syntax

**Defining jobs:**
```rust
#[pocopine::job(queue = "QUEUE_NAME", retries = N)]
pub async fn my_job(input: PayloadType) -> JobResult<()> { ... }

#[pocopine::job(queue = "QUEUE_NAME", every = "15m")]
pub async fn periodic_task() -> JobResult<()> { ... }

#[pocopine::job(queue = "QUEUE_NAME", cron = "0 0 2 * * * *")]
pub async fn nightly_task() -> JobResult<()> { ... }
```

**Enqueue/schedule helpers** (auto-generated in `{job_name}_job` module):
- `enqueue(payload)` / `enqueue_with(&client, payload)` — immediate
- `schedule_in(payload, delay)` / `schedule_in_with(&client, payload, delay)` — after delay
- `schedule_at(payload, when)` / `schedule_at_with(&client, payload, when)` — at absolute time

**Clients & workers:**
- `JobClient::from_env()` — auto-selects backend from `POCOPINE_JOB_BACKEND` / `POCOPINE_REDIS_URL`
- `JobClient::new(redis_url, app_name)` — explicit Redis backend
- `JobClient::memory(app_name)` — explicit memory backend
- `Worker::from_env()` → `worker.run().await` — main worker loop
- `Worker::run_once()` — single scheduler/read/execute pass (for embedded workers)
- `Worker::drain_dead_letter()` — memory-backend only; drain capped dead-letter buffer

**Configuration** (environment variables):
- `POCOPINE_JOB_BACKEND` — `memory` or `redis` (default: auto-select)
- `POCOPINE_REDIS_URL` — Redis connection string (e.g., `redis://localhost/`)
- `POCOPINE_APP_NAME` — namespace (default: `pocopine`)
- `POCOPINE_JOB_QUEUES` — comma-separated queue names to consume (default: all registered)
- `POCOPINE_JOB_VISIBILITY_MS` — reclaim timeout (default: 60000 ms)
- `POCOPINE_JOB_PERIODIC_CATCH_UP_MAX` — max missed periodic slots to backfill (default: 16)

**Result type:**
```rust
pub type JobResult<T = ()> = Result<T, JobError>;
```

## Examples

**1. One-time job definition and enqueue:**

From `/home/zempare-mambisi/RustProjects/pocopine/examples/blog/src/lib.rs`:
```rust
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PostViewAudit {
    pub post_id: u32,
}

#[pocopine::job(queue = "blog", retries = 2)]
pub async fn record_post_view(input: PostViewAudit) -> JobResult<()> {
    tracing::info!(target: "pocopine.log", post_id = input.post_id, "post view audit");
    Ok(())
}

// In a #[server] function:
#[pocopine::server(public)]
pub async fn get_post(post_id: u32) -> ServerResult<Post> {
    #[cfg(not(target_arch = "wasm32"))]
    {
        let _ = record_post_view_job::enqueue(PostViewAudit { post_id }).await;
    }
    // ... fetch and return post
}
```

**2. Periodic job (every N interval):**

From `/home/zempare-mambisi/RustProjects/pocopine/examples/blog/src/lib.rs`:
```rust
#[pocopine::job(queue = "blog", every = "10m")]
pub async fn refresh_blog_index() -> JobResult<()> {
    tracing::info!(target: "pocopine.log", "refresh blog index");
    Ok(())
}
```

**3. Worker binary setup:**

From `/home/zempare-mambisi/RustProjects/pocopine/examples/blog/src/bin/worker.rs`:
```rust
#[cfg(not(target_arch = "wasm32"))]
#[tokio::main]
async fn main() -> pocopine::JobResult<()> {
    use blog as _;
    use pocopine_logging::init_default;

    init_default().map_err(|err| pocopine::JobError::Env(err.to_string()))?;
    tracing::info!(target: "pocopine.log", "running blog worker");
    pocopine::Worker::from_env()?.run().await
}

#[cfg(target_arch = "wasm32")]
fn main() {}
```

## Gotchas

**Attribute constraints:**
- Job functions must be `async` and return `JobResult<()>` (not `Result<_, _>`).
- One-time jobs take exactly one owned (non-reference) payload argument; periodic jobs take zero arguments.
- The payload type must implement `Serialize` + `Deserialize`.
- Job names are module-qualified paths (`module::path::job_name`); register via `inventory` at link time.

**Backend selection:**
- Memory backend is process-local and **not shared** across server/worker binaries. Use it only for embedded workers or single-process tests.
- If `POCOPINE_JOB_BACKEND=memory` and a separate `worker-bin` is configured, the CLI rejects it with an error; `pocopine dev` defaults to Redis if unset.
- Multi-process deployments must use Redis; leaving both env vars unset silently defaults to memory, which is a footgun.

**Retry and visibility semantics:**
- **At-least-once:** handlers must be idempotent or finish well under `visibility_timeout` (60s default). Jobs slow longer than the timeout may be reclaimed and re-run by another worker.
- **Reclaim attempt accounting:** when a stale job is claimed, `attempt` is incremented before re-execution. If `attempt >= max_attempts` at reclaim time, it goes straight to dead-letter.
- **Exponential backoff:** retry delay grows from 1s (attempt 2) to 60s (capped), with hash-jittered spread per job so different jobs don't collide.

**Periodic jobs:**
- `every = "15m"` accepts units: `ms`, `s`, `m`, `h`, `d`. Zero intervals are rejected at compile time.
- `cron = "0 0 2 * * * *"` uses the `cron` crate syntax (7 fields: sec min hour dom mon dow year). Invalid expressions are rejected at compile time.
- Periodic jobs enqueue with `()` as the payload (unit type).
- Catch-up after downtime: if the worker was offline, missed cron firings are backfilled up to `max_periodic_catch_up` (16 by default) in one iteration. Operators can widen this with `POCOPINE_JOB_PERIODIC_CATCH_UP_MAX` for explicit backfill.

**Dead-letter and monitoring:**
- Redis backend: read the dead-letter stream at `pocopine:{app}:dead` directly (e.g., `XRANGE pocopine:my-app:dead - +`).
- Memory backend: periodically call `worker.drain_dead_letter() -> Vec<DeadLetter>` and persist elsewhere; the buffer is capped at 1024 entries (oldest dropped first).
- Worker startup logs a banner saying which backend is bound; check logs to confirm Redis was wired up correctly.

## References

**Crate:** `/home/zempare-mambisi/RustProjects/pocopine/crates/pocopine-jobs/src/lib.rs` (runtime: `JobClient`, `Worker`, `JobDescriptor`, envelopes, retry/dead-letter logic)

**Macro:** `/home/zempare-mambisi/RustProjects/pocopine/crates/pocopine-macros/src/lib.rs` lines 4950–5194 (attribute parsing, code generation for `{job_name}_job` module helpers, descriptor submission)

**RFC:** `rfcs/rfc-067-redis-background-jobs.md` (design, failure model, at-least-once contract, visibility timeout semantics, cron/interval syntax)

**Architecture & internals:** `docs/jobs.md` (state machine, Redis Streams/sorted-set topology, Lua scripts, reclaim logic, periodic scheduling, verification commands)

**Tests:** `/home/zempare-mambisi/RustProjects/pocopine/crates/pocopine/tests/job_macro.rs` (compile checks, job descriptor registration), `crates/pocopine/tests/jobs_redis.rs` (integration suite covering enqueue, retry, dead-letter, reclaim, periodic firings)

**Example:** `/home/zempare-mambisi/RustProjects/pocopine/examples/blog/src/lib.rs` (job definition, enqueue from server function), `examples/blog/src/bin/worker.rs` (worker binary template)
